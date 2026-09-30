#!/usr/bin/env python3
"""
debug_host.py - host de la debug unit: carga del programa por UART y control del CPU.

Uso:
    python3 debug_host.py --port /dev/ttyUSB1 load test_program.hex step 3 dump
    python3 debug_host.py --port COM4 load prog.bin run pause dump

Acciones (se ejecutan en orden, en una sola conexion):
    load <archivo>  carga el programa: .bin crudo (objcopy -O binary) o texto
                    con una palabra hex de 32 bits por linea (formato $readmemh)
    step [n]        avanza n ciclos (default 1)
    run             ejecucion continua
    wait [seg]      espera el aviso de halt hasta seg segundos (default 5)
    pause           detiene la ejecucion continua
    reset           reset del CPU (PC = 0); el programa se conserva
    dump            lee el bus de debug: IF/ID, salidas de ID armadas como
                    instruccion y banco de registros

Despues de run, usar wait o pause antes de dump: si el CPU llega a halt, el aviso
'H' se enviaria antes que la respuesta del dump.
Protocolo: encabezado de debug_unit.v. Requiere pyserial (pip install pyserial).
"""
import argparse
import sys

# ----------------------------------------------------------------- mapa de debug
# Mismo orden que el mapa de debug de cpu.v. Al agregar etapas, extender
# print_dump() con las palabras nuevas (se agregan al final).
#   0 IF/ID pc   1 IF/ID instr   2 IF/ID pc+4
#   3 ID control   4 ID {funct3, rd, rs2, rs1}   5 ID rs1_data   6 ID rs2_data
#   7 ID imm   8 ID destino de JAL   9..40 x0..x31
DBG_REGS = 9

ALU_A = {0: "rs1", 1: "pc", 2: "0"}
RESULT = {0: "alu", 1: "mem", 2: "pc+4"}
ALU_OPS = {0b0000: "add", 0b1000: "sub", 0b0001: "sll", 0b0010: "slt", 0b0011: "sltu",
           0b0100: "xor", 0b0101: "srl", 0b1101: "sra", 0b0110: "or", 0b0111: "and"}
ALU_OPS_IMM = {0b0000: "addi", 0b0001: "slli", 0b0010: "slti", 0b0011: "sltiu", 0b0100: "xori",
               0b0101: "srli", 0b1101: "srai", 0b0110: "ori", 0b0111: "andi"}
BRANCHES = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}
LOADS = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
STORES = {0: "sb", 1: "sh", 2: "sw"}


def signed32(v):
    return v - (1 << 32) if v & 0x80000000 else v


def decode_id(words):
    """Palabras 3..8 del dump -> salidas de ID."""
    ctrl, fields, rs1_data, rs2_data, imm, jal_target = words[3:9]
    return {
        "reg_write": ctrl & 1, "mem_read": (ctrl >> 1) & 1, "mem_write": (ctrl >> 2) & 1,
        "branch": (ctrl >> 3) & 1, "jal": (ctrl >> 4) & 1, "jalr": (ctrl >> 5) & 1,
        "halt": (ctrl >> 6) & 1, "illegal": (ctrl >> 7) & 1, "alu_src_b": (ctrl >> 8) & 1,
        "alu_src_a": (ctrl >> 9) & 3, "result_src": (ctrl >> 11) & 3, "alu_op": (ctrl >> 13) & 0xF,
        "rs1": fields & 0x1F, "rs2": (fields >> 5) & 0x1F, "rd": (fields >> 10) & 0x1F,
        "funct3": (fields >> 15) & 7,
        "rs1_data": rs1_data, "rs2_data": rs2_data, "imm": imm, "jal_target": jal_target,
    }


def asm_from_id(d, pc):
    """Arma la instruccion solo con las salidas de ID (mismo criterio que id_monitor.v)."""
    imm, simm = d["imm"], signed32(d["imm"])
    rd, rs1, rs2, f3 = d["rd"], d["rs1"], d["rs2"], d["funct3"]
    target = (pc + imm) & 0xFFFFFFFF
    if d["illegal"]:
        return "<ilegal>"
    if d["halt"]:
        return "ebreak" if imm & 1 else "ecall"
    if d["jal"]:
        return f"jal x{rd},0x{target:x}"
    if d["jalr"]:
        return f"jalr x{rd},{simm}(x{rs1})"
    if d["branch"]:
        return f"{BRANCHES.get(f3, 'b?')} x{rs1},x{rs2},0x{target:x}"
    if d["mem_read"]:
        return f"{LOADS.get(f3, 'l?')} x{rd},{simm}(x{rs1})"
    if d["mem_write"]:
        return f"{STORES.get(f3, 's?')} x{rs2},{simm}(x{rs1})"
    if d["alu_src_a"] == 2:
        return f"lui x{rd},0x{imm >> 12:x}"
    if d["alu_src_a"] == 1:
        return f"auipc x{rd},0x{imm >> 12:x}"
    if d["alu_src_b"] == 0:
        return f"{ALU_OPS.get(d['alu_op'], 'alu?')} x{rd},x{rs1},x{rs2}"
    name = ALU_OPS_IMM.get(d["alu_op"], "alu?")
    if (d["alu_op"] & 7) in (1, 5):
        return f"{name} x{rd},x{rs1},0x{imm & 0x1F:x}"
    return f"{name} x{rd},x{rs1},{simm}"


def print_dump(words):
    n = len(words)
    if n >= 3:
        print(f"IF/ID  pc=0x{words[0]:08x}  instr=0x{words[1]:08x}  pc+4=0x{words[2]:08x}")
    if n >= 9:
        d = decode_id(words)
        print(f"ID     {asm_from_id(d, words[0])}")
        print(f"       rd=x{d['rd']} rs1=x{d['rs1']} (0x{d['rs1_data']:08x}) rs2=x{d['rs2']} "
              f"(0x{d['rs2_data']:08x}) imm=0x{d['imm']:08x} funct3={d['funct3']:03b} "
              f"destino_jal=0x{d['jal_target']:08x}")
        print(f"       alu: a={ALU_A.get(d['alu_src_a'], '?')} b={'imm' if d['alu_src_b'] else 'rs2'} "
              f"op={ALU_OPS.get(d['alu_op'], '?')} | wb: reg_write={d['reg_write']} "
              f"res={RESULT.get(d['result_src'], '?')} | mem: read={d['mem_read']} write={d['mem_write']} "
              f"| branch={d['branch']} jal={d['jal']} jalr={d['jalr']} halt={d['halt']} "
              f"illegal={d['illegal']}")
    if n >= DBG_REGS + 32:
        print("Registros")
        for r in range(0, 32, 4):
            print("       " + "   ".join(f"x{r + i:<2}= 0x{words[DBG_REGS + r + i]:08x}" for i in range(4)))
    for i in range(DBG_REGS + 32, n):
        print(f"{i:4d}  dbg[{i}] 0x{words[i]:08x}")

CMD_LOAD, CMD_STEP, CMD_RUN, CMD_PAUSE, CMD_RESET, CMD_DUMP = b"L", b"S", b"R", b"P", b"X", b"D"
RSP_OK, RSP_ERR, RSP_HALT, RSP_UNK = b"K", b"E", b"H", b"?"


class ProtocolError(Exception):
    pass


def read_program(path):
    """Devuelve la lista de palabras de 32 bits del programa."""
    if path.lower().endswith(".bin"):
        with open(path, "rb") as f:
            data = f.read()
        if len(data) % 4:
            data += bytes(4 - len(data) % 4)
        return [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]

    words = []
    with open(path) as f:
        for lineno, line in enumerate(f, 1):
            line = line.split("//")[0].split("#")[0]
            for tok in line.split():
                if tok.startswith("@"):
                    raise ValueError(f"{path}:{lineno}: direcciones '@' no soportadas")
                tok = tok.replace("_", "")
                if tok.lower().startswith("0x"):
                    tok = tok[2:]
                value = int(tok, 16)
                if value > 0xFFFFFFFF:
                    raise ValueError(f"{path}:{lineno}: '{tok}' no entra en 32 bits")
                words.append(value)
    return words


def encode_load(words):
    """Trama de carga: 'L', n (16 bits little-endian) y cada palabra en little-endian."""
    if len(words) > 0xFFFF:
        raise ValueError("el programa supera las 65535 instrucciones")
    frame = bytearray(CMD_LOAD)
    frame += len(words).to_bytes(2, "little")
    for w in words:
        frame += w.to_bytes(4, "little")
    return bytes(frame)


def decode_words(data):
    """Palabras de 32 bits little-endian."""
    return [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]


class DebugHost:
    def __init__(self, ser):
        self.ser = ser

    def _read(self, n, timeout):
        self.ser.timeout = timeout
        data = self.ser.read(n)
        if len(data) != n:
            raise ProtocolError(f"se esperaban {n} bytes y llegaron {len(data)}")
        return data

    def _tx_time(self, n_bytes):
        return n_bytes * 10 / self.ser.baudrate

    def _expect_ok(self, reply, what):
        if reply == RSP_OK:
            return
        if reply == RSP_ERR:
            raise ProtocolError(f"{what}: el programa no entra en la memoria de instrucciones")
        if reply == RSP_UNK:
            raise ProtocolError(f"{what}: comando no reconocido por la FPGA")
        raise ProtocolError(f"{what}: respuesta inesperada {reply!r}")

    def load(self, words):
        frame = encode_load(words)
        self.ser.write(frame)
        self._expect_ok(self._read(1, self._tx_time(len(frame)) + 1.0), "load")

    def step(self, n=1):
        for i in range(n):
            self.ser.write(CMD_STEP)
            reply = self._read(1, 1.0)
            if reply == RSP_HALT:
                print(f"halt: se ejecutaron {i} de {n} pasos")
                return False
            self._expect_ok(reply, "step")
        return True

    def run(self):
        self.ser.write(CMD_RUN)
        reply = self._read(1, 1.0)
        if reply == RSP_HALT:
            print("el CPU esta en halt: no arranca (usar reset o load)")
            return False
        self._expect_ok(reply, "run")
        return True

    def wait_halt(self, seconds):
        self.ser.timeout = seconds
        reply = self.ser.read(1)
        if reply == RSP_HALT:
            print("halt")
            return True
        if reply:
            raise ProtocolError(f"wait: respuesta inesperada {reply!r}")
        print(f"sin halt despues de {seconds} s")
        return False

    def pause(self):
        self.ser.write(CMD_PAUSE)
        reply = self._read(1, 1.0)
        if reply == RSP_HALT:                          # llego a halt antes de la pausa
            print("halt")
            reply = self._read(1, 1.0)
        self._expect_ok(reply, "pause")

    def reset(self):
        self.ser.write(CMD_RESET)
        self._expect_ok(self._read(1, 1.0), "reset")

    def dump(self):
        self.ser.write(CMD_DUMP)
        count = int.from_bytes(self._read(2, 1.0), "little")
        words = decode_words(self._read(4 * count, self._tx_time(4 * count) + 1.0))
        print_dump(words)
        return words


def run_actions(host, actions):
    i = 0
    while i < len(actions):
        action = actions[i].lower()
        i += 1
        if action == "load":
            if i >= len(actions):
                raise SystemExit("load: falta el archivo")
            words = read_program(actions[i])
            i += 1
            host.load(words)
            print(f"load: {len(words)} instrucciones")
        elif action == "step":
            n = 1
            if i < len(actions) and actions[i].isdigit():
                n = int(actions[i])
                i += 1
            host.step(n)
        elif action == "run":
            host.run()
        elif action == "wait":
            seconds = 5.0
            if i < len(actions) and actions[i].replace(".", "", 1).isdigit():
                seconds = float(actions[i])
                i += 1
            host.wait_halt(seconds)
        elif action == "pause":
            host.pause()
        elif action == "reset":
            host.reset()
        elif action == "dump":
            host.dump()
        else:
            raise SystemExit(f"accion desconocida: {action}")


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Host de la debug unit del RISC-V",
        epilog=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--port", required=True, help="puerto serie (ej. /dev/ttyUSB1 o COM4)")
    ap.add_argument("--baud", type=int, default=19200, help="baud rate (default 19200)")
    ap.add_argument("actions", nargs="+", help="acciones a ejecutar en orden")
    args = ap.parse_args(argv)

    import serial

    with serial.Serial(args.port, args.baud, bytesize=8, parity="N", stopbits=1, timeout=1) as ser:
        ser.reset_input_buffer()
        try:
            run_actions(DebugHost(ser), args.actions)
        except ProtocolError as e:
            sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
