#!/usr/bin/env python3
"""Capa placa: el sistema en la FPGA real, manejado por la UART como lo hace el host.

Uso: run.py --puerto /dev/ttyUSB1 --build-id <8 hex> --sim <Vtb de la placa>

No compara contra valores escritos a mano sino contra la simulación del RTL con las
memorias de la placa (verif/sim, `build.sh placa`): cada programa tiene que terminar en
la placa con los mismos registros, la misma dmem, la misma causa de halt y la misma
cantidad de ciclos que en la simulación.

  1. versión: la palabra BUILD_ID del dump es la versión del hardware que se está probando
     (el último commit que cambió rtl/, constraints/ o los tcl de verif/fpga/)
  2. programas de programs/ (ensamblados con el ensamblador del host)
  3. tests de traps de verif/sim/tests/traps/ (causa, PC y dirección del trap)
  4. comandos de la debug unit: step, run, pausa, reset, programa demasiado grande,
     comando desconocido (los escenarios de verif/system, ahora en hardware)
Escribe un renglón [ok ] / [MAL] por chequeo.
"""
import argparse
import glob
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(PROJ, "host"))
from lib.assemble import assemble_file, assemble_text  # noqa: E402
from lib.debug_protocol import DebugLink, ProtocolError, decode_dump  # noqa: E402

IMEM_WORDS = 256
MAX_CYCLES = 20000
# Pone la dmem (1 KB) en cero: la placa conserva la dmem entre programas y el reset del
# CPU no la borra; la simulación arranca con la dmem en cero (+dmem-en-cero).
CLEAR_DMEM = """
        addi x1, x0, 0
        addi x2, x0, 1024
loop:   sw   x0, 0(x1)
        addi x1, x1, 4
        bne  x1, x2, loop
        ebreak
"""

results = []


def check(ok, text):
    results.append(ok)
    print(f"[{'ok ' if ok else 'MAL'}] {text}", flush=True)


# ------------------------------------------------------------------ simulación de referencia
def simulate(sim, words):
    """Corre el programa en la simulación del RTL (memorias de la placa)."""
    with tempfile.NamedTemporaryFile("w", suffix=".hex", delete=False) as f:
        f.write("".join(f"{w:08x}\n" for w in words))
        hexf = f.name
    try:
        r = subprocess.run([sim, f"+hex={hexf}", "+estado", "+dmem-en-cero", f"+max-cycles={MAX_CYCLES}"],
                           capture_output=True, text=True, timeout=60)
    finally:
        os.unlink(hexf)
    out = r.stdout
    m = re.search(r"ciclos=(\d+).*causa=(\d+)\s+pc=([0-9a-f]+)\s+tval=([0-9a-f]+)", out)
    if not m:
        return None
    return {"cycles": int(m[1]), "cause": int(m[2]), "pc": int(m[3], 16), "tval": int(m[4], 16),
            "regs": [0] + [int(v, 16) for v in re.findall(r"tb: x\d+ = ([0-9a-f]+)", out)],
            "dmem": [int(v, 16) for v in re.findall(r"tb: dmem \d+ = ([0-9a-f]+)", out)]}


# ------------------------------------------------------------------ placa
def run_on_board(link, words):
    """Pone la dmem en cero, carga el programa y lo ejecuta ciclo a ciclo hasta el halt."""
    link.load(assemble_text(CLEAR_DMEM).words)
    link.reset()
    if not (link.run() and link.poll_halt(2.0)):        # no hace falta contar sus ciclos
        raise ProtocolError("el programa que borra la dmem no terminó")
    link.load(words)
    link.reset()
    cycles = 0
    while link.step():
        cycles += 1
        if cycles > MAX_CYCLES:
            return None
    d = decode_dump(link.dump())
    return {"cycles": cycles, "cause": d["trap"]["cause"], "pc": d["trap"]["pc"],
            "tval": d["trap"]["tval"], "regs": d["regs"], "dmem": d["dmem"]}


def compare(name, link, sim, words):
    if len(words) > IMEM_WORDS:
        check(False, f"{name}: {len(words)} palabras, no entra en la imem de la placa")
        return
    ref = simulate(sim, words)
    if ref is None:
        check(False, f"{name}: la simulación de referencia no terminó")
        return
    try:
        hw = run_on_board(link, words)
    except ProtocolError as e:
        check(False, f"{name}: {e}")
        return
    if hw is None:
        check(False, f"{name}: sin halt en la placa después de {MAX_CYCLES} ciclos")
        return
    diffs = []
    if hw["cycles"] != ref["cycles"]:
        diffs.append(f"ciclos: placa {hw['cycles']}, simulación {ref['cycles']}")
    for k, label in (("cause", "causa"), ("pc", "pc del trap"), ("tval", "dirección del trap")):
        if hw[k] != ref[k]:
            diffs.append(f"{label}: placa {hw[k]:#x}, simulación {ref[k]:#x}")
    for i in range(1, 32):
        if hw["regs"][i] != ref["regs"][i]:
            diffs.append(f"x{i}: placa {hw['regs'][i]:#010x}, simulación {ref['regs'][i]:#010x}")
    for i, (a, b) in enumerate(zip(hw["dmem"], ref["dmem"])):
        if a != b:
            diffs.append(f"dmem[{i}]: placa {a:#010x}, simulación {b:#010x}")
    check(not diffs, f"{name}: {hw['cycles']} ciclos, causa {hw['cause']} en pc={hw['pc']:#x}"
          + ("" if not diffs else " — distinto de la simulación:\n        " + "\n        ".join(diffs[:8])))


def elf_words(src):
    """Compila un test .S (con el preprocesador) y devuelve la imagen desde la dirección 0."""
    with tempfile.TemporaryDirectory() as tmp:
        elf, binf = os.path.join(tmp, "t.elf"), os.path.join(tmp, "t.bin")
        subprocess.run(["riscv-none-elf-gcc", "-march=rv32i", "-mabi=ilp32", "-nostdlib", "-Ttext=0",
                        "-o", elf, src], check=True, capture_output=True)
        subprocess.run(["riscv-none-elf-objcopy", "-O", "binary", elf, binf], check=True)
        data = open(binf, "rb").read()
    data += bytes(-len(data) % 4)
    return [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]


# ------------------------------------------------------------------ comandos de la debug unit
def commands(link, ser):
    prog = assemble_file(os.path.join(PROJ, "programs", "pipeline_test.s")).words
    exp = [int(x, 16) for x in open(os.path.join(PROJ, "verif", "system", "pipeline_exp.hex")).read().split()]

    link.load(prog)
    link.reset()
    check(decode_dump(link.dump())["pc"] == 0, "carga: el CPU queda en pc=0")
    link.step()
    pc1 = decode_dump(link.dump())["pc"]
    link.step(); link.step()
    pc3 = decode_dump(link.dump())["pc"]
    check((pc1, pc3) == (4, 12), f"step: un ciclo por comando (pc {pc1:#x} → {pc3:#x}, esperado 0x4 → 0xc)")

    check(link.run() and link.poll_halt(5.0), "run: ejecución continua hasta el aviso de halt ('H')")
    d = decode_dump(link.dump())
    ok = d["regs"] == exp[:32] and d["dmem"][:16] == exp[32:48]
    check(ok, "run: registros y dmem iguales al modelo de referencia (pipeline_exp.hex)")
    check(d["trap"]["cause"] == 3, f"run: se detuvo por ebreak (causa {d['trap']['cause']})")

    link.reset()
    d = decode_dump(link.dump())
    check(d["pc"] == 0 and not any(d["regs"]), "reset: pc=0 y registros en cero")
    check(link.run() and link.poll_halt(5.0) and decode_dump(link.dump())["regs"] == exp[:32],
          "reset: el programa se conserva y vuelve a dar el mismo resultado")

    link.load([0x0000006f])                     # j . (lazo infinito)
    link.reset()
    check(link.run() and not link.poll_halt(0.5), "pausa: un lazo infinito corre sin halt")
    halted = link.pause()
    pc_a = decode_dump(link.dump())["pc"]
    pc_b = decode_dump(link.dump())["pc"]
    check(not halted and pc_a == pc_b and pc_a in (0, 4, 8),
          f"pausa: el CPU se detiene en el lazo y no avanza (pc={pc_a:#x} en dos dumps seguidos)")

    link.load([0x00100093, 0x00000000, 0x00200113])   # addi x1,x0,1 / ilegal / addi x2,x0,2
    link.reset()
    link.run()
    check(link.poll_halt(5.0), "trap: una instrucción ilegal detiene el CPU")
    d = decode_dump(link.dump())
    check((d["trap"]["cause"], d["trap"]["pc"], d["regs"][1], d["regs"][2]) == (2, 4, 1, 0),
          f"trap: causa {d['trap']['cause']} en pc={d['trap']['pc']:#x}, x1={d['regs'][1]} (anterior retirada), "
          f"x2={d['regs'][2]} (posterior descartada)")

    try:
        link.load([0x13] * (IMEM_WORDS + 1))
        check(False, "programa demasiado grande: se aceptó")
    except ProtocolError as e:
        check("no entra" in str(e), "programa demasiado grande: la debug unit responde 'E'")
    ser.write(b"Z")
    ser.timeout = 1.0
    check(ser.read(1) == b"?", "comando desconocido: la debug unit responde '?'")
    check(decode_dump(link.dump())["pc"] is not None, "después de los errores, el protocolo sigue sincronizado")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--puerto", required=True)
    ap.add_argument("--build-id", required=True)
    ap.add_argument("--sim", required=True)
    ap.add_argument("--baud", type=int, default=19200)
    a = ap.parse_args()
    import serial
    ser = serial.Serial(a.puerto, a.baud, bytesize=8, parity="N", stopbits=1, timeout=1)
    ser.reset_input_buffer()
    link = DebugLink(ser)

    print("== versión")
    try:
        d = decode_dump(link.dump())
    except ProtocolError as e:
        check(False, f"la placa no responde en {a.puerto} ({e}): ¿está programada la FPGA?")
        sys.exit(1)
    want = int(a.build_id, 16)
    got = d["build"]
    if want == 0:
        check(False, "el hardware tiene cambios sin commitear: no hay una versión con qué comparar la placa")
    else:
        check(got == want, f"la placa tiene la versión {got:08x} del hardware" if got is not None else
              "la placa no tiene palabra de versión (bitstream anterior)")
        if got != want:
            print(f"        el hardware actual es {want:08x}: correr verif/run.sh programar placa (o fpga)")
            sys.exit(1)

    print("== programas")
    for src in sorted(glob.glob(os.path.join(PROJ, "programs", "*.s"))):
        name = os.path.basename(src)
        if name == "overflow_test.s":
            continue                             # no entra en la imem a propósito: ver comandos
        compare(name, link, a.sim, assemble_file(src).words)

    print("== traps")
    for src in sorted(glob.glob(os.path.join(PROJ, "verif", "sim", "tests", "traps", "*.S"))):
        compare(os.path.basename(src), link, a.sim, elf_words(src))

    print("== comandos de la debug unit")
    commands(link, ser)
    ser.close()
    sys.exit(0 if results and all(results) else 1)


if __name__ == "__main__":
    main()
