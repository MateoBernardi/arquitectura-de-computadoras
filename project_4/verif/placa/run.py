#!/usr/bin/env python3
"""Capa placa: el sistema en la FPGA real, manejado por la UART como lo hace el host.

Uso: run.py --puerto /dev/ttyUSB1 --build-id <8 hex> --sim <Vtb de la placa>

No compara contra valores escritos a mano sino contra la simulación del RTL con las
memorias de la placa (verif/sim, `build.sh placa`): cada programa tiene que terminar en
la placa con los mismos registros, la misma dmem, la misma causa de halt y la misma
cantidad de ciclos e instrucciones retiradas que en la simulación (los cuentan los
contadores de rendimiento de top_riscv, palabras 90 y 91 del dump).

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
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(PROJ, "host"))
from lib.assemble import assemble_file  # noqa: E402
from lib import medir  # noqa: E402
from lib.debug_protocol import DebugLink, ProtocolError, decode_dump  # noqa: E402

IMEM_WORDS = 256
MAX_CYCLES = 20000

results = []


def check(ok, text):
    results.append(ok)
    print(f"[{'ok ' if ok else 'MAL'}] {text}", flush=True)


def compare(name, link, sim, words):
    """El programa en la placa (con 'R', medido por los contadores de top_riscv) contra la
    simulación: mismos ciclos, instrucciones, causa del halt, registros y dmem."""
    if len(words) > IMEM_WORDS:
        check(False, f"{name}: {len(words)} palabras, no entra en la imem de la placa")
        return
    ref = medir.simulate(sim, words, MAX_CYCLES)
    if ref is None:
        check(False, f"{name}: la simulación de referencia no terminó")
        return
    try:
        hw = medir.board(link, words, timeout=5.0)
    except ProtocolError as e:
        check(False, f"{name}: {e}")
        return
    if hw is None:
        check(False, f"{name}: sin halt en la placa")
        return
    diffs = medir.differences(hw, ref)
    check(not diffs, f"{name}: {hw['cycles']} ciclos, {hw['instret']} instrucciones, "
          f"causa {hw['cause']} en pc={hw['pc']:#x}"
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

    run_perf = d["perf"]
    link.reset()
    steps = 0
    while link.step() and steps <= MAX_CYCLES:
        steps += 1
    step_perf = decode_dump(link.dump())["perf"]
    check(step_perf is not None and step_perf["cycles"] == steps == run_perf["cycles"]
          and step_perf["instret"] == run_perf["instret"],
          f"contadores: {steps} steps = {step_perf and step_perf['cycles']} ciclos contados "
          f"(con run: {run_perf and run_perf['cycles']}), instrucciones iguales con step y con run")

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
