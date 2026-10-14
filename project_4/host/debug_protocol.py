"""
debug_protocol.py - cliente del protocolo UART de la debug unit y decodificacion del dump.

Protocolo (ver project_4.srcs/sources_1/new/debug_unit.v):
    'L' n_lo n_hi + 4n bytes LE -> 'K' | 'E'     carga de programa
    'S' -> 'K' | 'H'     un ciclo        'R' -> 'K' | 'H'   ejecucion continua
    'P' -> 'K'           pausa           'X' -> 'K'         reset del CPU
    'D' -> count_lo count_hi + count palabras de 32 bits LE (bus de debug)
    'H' espontaneo cuando el CPU llega a halt durante 'R'.

Mapa del dump: encabezado de riscv_pipeline.v. Si se agregan palabras, se agregan
siempre al final y se extiende decode_dump().
"""

CMD_LOAD, CMD_STEP, CMD_RUN, CMD_PAUSE, CMD_RESET, CMD_DUMP = b"L", b"S", b"R", b"P", b"X", b"D"
RSP_OK, RSP_ERR, RSP_HALT, RSP_UNK = b"K", b"E", b"H", b"?"

DBG_REGS = 22
DBG_DMEM = 54

ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4",
       "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4",
       "t5", "t6"]


class ProtocolError(Exception):
    pass


def encode_load(words):
    """Trama de carga: 'L', n (16 bits LE) y cada palabra en little-endian."""
    if len(words) > 0xFFFF:
        raise ValueError("el programa supera las 65535 instrucciones")
    frame = bytearray(CMD_LOAD)
    frame += len(words).to_bytes(2, "little")
    for w in words:
        frame += (w & 0xFFFFFFFF).to_bytes(4, "little")
    return bytes(frame)


def decode_words(data):
    return [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]


def read_program(path):
    """Palabras de 32 bits de un .bin crudo o de un texto con una palabra hex por linea."""
    if path.lower().endswith(".bin"):
        with open(path, "rb") as f:
            data = f.read()
        data += bytes(-len(data) % 4)
        return decode_words(data)
    words = []
    with open(path) as f:
        for lineno, line in enumerate(f, 1):
            line = line.split("//")[0].split("#")[0]
            for tok in line.split():
                tok = tok.replace("_", "")
                if tok.lower().startswith("0x"):
                    tok = tok[2:]
                value = int(tok, 16)
                if value > 0xFFFFFFFF:
                    raise ValueError(f"{path}:{lineno}: '{tok}' no entra en 32 bits")
                words.append(value)
    return words


class DebugLink:
    """Cliente del protocolo sobre un puerto serie (objeto con write/read/timeout/baudrate)."""

    def __init__(self, ser):
        self.ser = ser

    def _read(self, n, timeout):
        self.ser.timeout = timeout
        data = self.ser.read(n)
        if len(data) != n:
            raise ProtocolError(f"se esperaban {n} bytes y llegaron {len(data)} (timeout)")
        return data

    def _tx_time(self, n_bytes):
        return n_bytes * 10 / self.ser.baudrate

    @staticmethod
    def _check(reply, what):
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
        self._check(self._read(1, self._tx_time(len(frame)) + 1.0), "load")

    def step(self):
        """Un ciclo. Devuelve False si el CPU esta en halt."""
        self.ser.write(CMD_STEP)
        reply = self._read(1, 1.0)
        if reply == RSP_HALT:
            return False
        self._check(reply, "step")
        return True

    def run(self):
        """Ejecucion continua. Devuelve False si el CPU ya esta en halt."""
        self.ser.write(CMD_RUN)
        reply = self._read(1, 1.0)
        if reply == RSP_HALT:
            return False
        self._check(reply, "run")
        return True

    def poll_halt(self, timeout=0.0):
        """True si llego el aviso espontaneo de halt."""
        self.ser.timeout = timeout
        reply = self.ser.read(1)
        if reply == RSP_HALT:
            return True
        if reply:
            raise ProtocolError(f"respuesta inesperada {reply!r}")
        return False

    def pause(self):
        """Detiene la ejecucion. Devuelve True si el halt llego antes de la pausa."""
        self.ser.write(CMD_PAUSE)
        halted = False
        reply = self._read(1, 1.0)
        if reply == RSP_HALT:
            halted = True
            reply = self._read(1, 1.0)
        self._check(reply, "pause")
        return halted

    def reset(self):
        self.ser.write(CMD_RESET)
        self._check(self._read(1, 1.0), "reset")

    def dump(self):
        self.ser.write(CMD_DUMP)
        count = int.from_bytes(self._read(2, 1.0), "little")
        return decode_words(self._read(4 * count, self._tx_time(4 * count) + 1.0))


# ------------------------------------------------------------------ decodificacion
WB_SEL = {0: "alu", 1: "mem", 2: "pc+4", 3: "imm"}
ALU_OPS = {0: "add", 1: "sub", 2: "and", 3: "or", 4: "xor", 5: "slt", 6: "sltu", 7: "sll",
           8: "srl", 9: "sra", 10: "nor"}
FWD = {0: "reg", 1: "wb", 2: "mem", 3: "?"}


def decode_dump(w):
    """Palabras del bus de debug -> dict con el estado del pipeline."""
    if len(w) < DBG_REGS + 32:
        raise ProtocolError(f"dump de {len(w)} palabras: se esperaban al menos {DBG_REGS + 32}")
    c, f, fl = w[3], w[4], w[13]
    return {
        "pc": w[0],
        "if_id": {"pc": w[1], "inst": w[2]},
        "id_ex": {
            "reg_write": c & 1, "mem_read": c >> 1 & 1, "mem_write": c >> 2 & 1,
            "branch": c >> 3 & 1, "jump": c >> 4 & 1, "is_jalr": c >> 5 & 1,
            "is_auipc": c >> 6 & 1, "halt": c >> 7 & 1, "alu_src": c >> 8 & 1,
            "wb_sel": WB_SEL[c >> 9 & 3], "alu_op": ALU_OPS.get(c >> 11 & 15, "?"),
            "rs1": f & 31, "rs2": f >> 5 & 31, "rd": f >> 10 & 31, "funct3": f >> 15 & 7,
            "pc": w[5], "rdata1": w[6], "rdata2": w[7], "imm": w[8],
        },
        "ex": {
            "alu_a": w[9], "alu_b": w[10], "alu_out": w[11], "target": w[12],
            "stall": fl & 1, "flush_if_id": fl >> 1 & 1, "flush_id_ex": fl >> 2 & 1,
            "redirect": fl >> 3 & 1, "taken": fl >> 4 & 1, "zero": fl >> 5 & 1,
            "overflow": fl >> 6 & 1, "halting": fl >> 7 & 1,
            "fwd_a": FWD[fl >> 8 & 3], "fwd_b": FWD[fl >> 10 & 3],
        },
        "ex_mem": {
            "reg_write": w[14] & 1, "mem_read": w[14] >> 1 & 1, "mem_write": w[14] >> 2 & 1,
            "halt": w[14] >> 3 & 1, "wb_sel": WB_SEL[w[14] >> 4 & 3],
            "alu_out": w[15], "rdata2": w[16], "rd": w[17] & 31, "funct3": w[17] >> 5 & 7,
            "dmem_rdata": w[18],
        },
        "mem_wb": {"reg_write": w[19] & 1, "halt": w[19] >> 1 & 1, "result": w[20], "rd": w[21] & 31},
        "regs": list(w[DBG_REGS:DBG_REGS + 32]),
        "dmem": list(w[DBG_DMEM:]),
    }


def _s(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def disasm(w, pc=0):
    """Desensamblado simple de una instruccion RV32I (para mostrar IF/ID)."""
    op, rd, f3, rs1, rs2, f7 = w & 0x7F, w >> 7 & 31, w >> 12 & 7, w >> 15 & 31, w >> 20 & 31, w >> 25
    x = lambda r: f"x{r}"
    if w == 0x13:
        return "nop"
    if op == 0x33:
        names = {(0, 0): "add", (0, 32): "sub", (1, 0): "sll", (2, 0): "slt", (3, 0): "sltu",
                 (4, 0): "xor", (5, 0): "srl", (5, 32): "sra", (6, 0): "or", (7, 0): "and"}
        n = names.get((f3, f7))
        return f"{n} {x(rd)},{x(rs1)},{x(rs2)}" if n else "<ilegal>"
    if op == 0x13:
        imm = _s(w >> 20, 12)
        if f3 in (1, 5):
            n = {1: "slli", 5: "srai" if f7 == 32 else "srli"}[f3]
            return f"{n} {x(rd)},{x(rs1)},{rs2}"
        n = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}[f3]
        return f"{n} {x(rd)},{x(rs1)},{imm}"
    if op == 0x03:
        n = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}.get(f3)
        return f"{n} {x(rd)},{_s(w >> 20, 12)}({x(rs1)})" if n else "<ilegal>"
    if op == 0x23:
        n = {0: "sb", 1: "sh", 2: "sw"}.get(f3)
        imm = _s((w >> 25 << 5) | (w >> 7 & 31), 12)
        return f"{n} {x(rs2)},{imm}({x(rs1)})" if n else "<ilegal>"
    if op == 0x63:
        n = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}.get(f3)
        imm = _s((w >> 31 & 1) << 12 | (w >> 7 & 1) << 11 | (w >> 25 & 63) << 5 | (w >> 8 & 15) << 1, 13)
        return f"{n} {x(rs1)},{x(rs2)},0x{(pc + imm) & 0xFFFFFFFF:x}" if n else "<ilegal>"
    if op == 0x37:
        return f"lui {x(rd)},0x{w >> 12:x}"
    if op == 0x17:
        return f"auipc {x(rd)},0x{w >> 12:x}"
    if op == 0x6F:
        imm = _s((w >> 31 & 1) << 20 | (w >> 12 & 0xFF) << 12 | (w >> 20 & 1) << 11 | (w >> 21 & 0x3FF) << 1, 21)
        return f"jal {x(rd)},0x{(pc + imm) & 0xFFFFFFFF:x}"
    if op == 0x67:
        return f"jalr {x(rd)},{_s(w >> 20, 12)}({x(rs1)})"
    if op == 0x73:
        return "ebreak" if w >> 20 & 1 else "ecall"
    return "<ilegal>"


def format_stages(d):
    """Texto de las etapas del pipeline (d = decode_dump(...))."""
    i, e, m, wb = d["if_id"], d["ex"], d["ex_mem"], d["mem_wb"]
    x = d["id_ex"]
    out = [f"IF     pc=0x{d['pc']:08x}",
           f"IF/ID  pc=0x{i['pc']:08x}  instr=0x{i['inst']:08x}  {disasm(i['inst'], i['pc'])}",
           f"ID/EX  pc=0x{x['pc']:08x}  rs1=x{x['rs1']} rs2=x{x['rs2']} rd=x{x['rd']} imm=0x{x['imm']:08x} "
           f"alu={x['alu_op']} wb={x['wb_sel']} reg_write={x['reg_write']} mem_r={x['mem_read']} "
           f"mem_w={x['mem_write']} branch={x['branch']} jump={x['jump']} halt={x['halt']}",
           f"EX     a=0x{e['alu_a']:08x} b=0x{e['alu_b']:08x} -> 0x{e['alu_out']:08x}  "
           f"fwd_a={e['fwd_a']} fwd_b={e['fwd_b']} stall={e['stall']} redirect={e['redirect']} "
           f"taken={e['taken']} target=0x{e['target']:08x} halting={e['halting']}",
           f"EX/MEM alu_out=0x{m['alu_out']:08x} rdata2=0x{m['rdata2']:08x} rd=x{m['rd']} "
           f"reg_write={m['reg_write']} mem_r={m['mem_read']} mem_w={m['mem_write']} wb={m['wb_sel']}",
           f"MEM/WB result=0x{wb['result']:08x} rd=x{wb['rd']} reg_write={wb['reg_write']} halt={wb['halt']}"]
    return "\n".join(out)


def format_dump(words):
    """Texto legible del dump completo (para la CLI)."""
    d = decode_dump(words)
    out = [format_stages(d), "Registros"]
    for r in range(0, 32, 4):
        out.append("       " + "   ".join(f"x{r + k:<2}=0x{d['regs'][r + k]:08x}" for k in range(4)))
    if d["dmem"]:
        out.append("dmem (palabras)")
        for r in range(0, len(d["dmem"]), 4):
            out.append("       " + "   ".join(f"[{r + k:>2}]=0x{v:08x}" for k, v in enumerate(d["dmem"][r:r + 4])))
    return "\n".join(out)
