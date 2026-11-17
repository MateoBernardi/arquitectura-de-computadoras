"""
medir.py - rendimiento de un programa en la placa y en el modelo (la simulacion del RTL).

Placa: los contadores de top_riscv (palabras 90 y 91 del dump) cuentan los ciclos que
avanzo el CPU y las instrucciones que retiro desde el ultimo reset del CPU. Se corre el
programa con 'R' (a la velocidad del reloj de la placa) y se leen al llegar el halt.

Modelo: el RTL simulado con Verilator con las memorias de la placa (build/sim/placa/Vtb,
`verif/sim/build.sh placa`). Informa ciclos e instrucciones retiradas (RVFI); verif/sim/tb.sv
comprueba en cada ciclo que la senal que cuenta la placa (o_retire) coincide con RVFI.

En los dos lados la dmem arranca en cero: la placa conserva la dmem entre programas (el
reset del CPU no la borra), asi que antes se corre un programa que la pone en cero.
"""
import os
import re
import subprocess
import tempfile
import time

from .assemble import assemble_text
from .debug_protocol import TRAP_CAUSES, ProtocolError, decode_dump

HOST = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = os.path.dirname(HOST)
DEFAULT_SIM = os.path.join(PROJ, "build", "sim", "placa", "Vtb")
BUILD_SIM_HINT = "verif/sim/build.sh placa"
MAX_CYCLES = 1_000_000

# Pone la dmem (1 KB) en cero
CLEAR_DMEM = """
        addi x1, x0, 0
        addi x2, x0, 1024
loop:   sw   x0, 0(x1)
        addi x1, x1, 4
        bne  x1, x2, loop
        ebreak
"""
_clear_words = None


def clear_dmem_words():
    global _clear_words
    if _clear_words is None:
        _clear_words = assemble_text(CLEAR_DMEM).words
    return _clear_words


# ------------------------------------------------------------------ placa
def prepare(link, words):
    """Pone la dmem en cero, carga el programa y resetea el CPU (contadores en cero)."""
    link.load(clear_dmem_words())
    link.reset()
    if not (link.run() and link.poll_halt(2.0)):
        raise ProtocolError("el programa que borra la dmem no termino")
    link.load(words)
    link.reset()


def result(dump_words):
    """Dump de la placa (con el CPU en halt) -> el mismo dict que simulate()."""
    d = decode_dump(dump_words)
    if d["perf"] is None:
        raise ProtocolError("el bitstream de la placa no tiene contadores de rendimiento: "
                            "programar la placa con el hardware actual (verif/run.sh programar)")
    return {"cycles": d["perf"]["cycles"], "instret": d["perf"]["instret"],
            "cause": d["trap"]["cause"], "pc": d["trap"]["pc"], "tval": d["trap"]["tval"],
            "regs": d["regs"], "dmem": d["dmem"]}


def board(link, words, timeout=10.0):
    """Corre el programa en la placa con 'R' hasta el halt. None si no termina."""
    prepare(link, words)
    if not link.run():
        raise ProtocolError("el CPU quedo en halt despues del reset")
    deadline = time.monotonic() + timeout
    while not link.poll_halt(0.1):
        if time.monotonic() > deadline:
            link.pause()
            return None
    return result(link.dump())


# ------------------------------------------------------------------ modelo
_HALT = re.compile(r"ciclos=(\d+)\s+instrucciones=(\d+)\s+causa=(\d+)\s+pc=([0-9a-f]+)\s+tval=([0-9a-f]+)")


def find_sim():
    """Ruta del simulador de la placa, o None si no esta compilado."""
    sim = os.environ.get("TP4_SIM", DEFAULT_SIM)
    return sim if os.access(sim, os.X_OK) else None


def simulate(sim, words, max_cycles=MAX_CYCLES):
    """Corre el programa en la simulacion del RTL (memorias de la placa). None si no termina."""
    with tempfile.NamedTemporaryFile("w", suffix=".hex", delete=False) as f:
        f.write("".join(f"{w:08x}\n" for w in words))
        hexf = f.name
    try:
        r = subprocess.run([sim, f"+hex={hexf}", "+estado", "+dmem-en-cero", f"+max-cycles={max_cycles}"],
                           capture_output=True, text=True, timeout=60)
    finally:
        os.unlink(hexf)
    out = r.stdout
    m = _HALT.search(out)
    if not m:
        return None
    return {"cycles": int(m[1]), "instret": int(m[2]), "cause": int(m[3]), "pc": int(m[4], 16),
            "tval": int(m[5], 16),
            "regs": [0] + [int(v, 16) for v in re.findall(r"tb: x\d+ = ([0-9a-f]+)", out)],
            "dmem": [int(v, 16) for v in re.findall(r"tb: dmem \d+ = ([0-9a-f]+)", out)]}


# ------------------------------------------------------------------ comparacion
def cpi(r):
    return r["cycles"] / r["instret"] if r and r["instret"] else None


def differences(hw, ref):
    """Lo que difiere entre la placa y el modelo (lista vacia = iguales)."""
    diffs = []
    for k, label in (("cycles", "ciclos"), ("instret", "instrucciones")):
        if hw[k] != ref[k]:
            diffs.append(f"{label}: placa {hw[k]}, modelo {ref[k]}")
    if hw["cause"] != ref["cause"]:
        diffs.append(f"causa: placa {hw['cause']} ({TRAP_CAUSES.get(hw['cause'], '?')}), "
                     f"modelo {ref['cause']} ({TRAP_CAUSES.get(ref['cause'], '?')})")
    for k, label in (("pc", "pc del trap"), ("tval", "dirección del trap")):
        if hw[k] != ref[k]:
            diffs.append(f"{label}: placa {hw[k]:#x}, modelo {ref[k]:#x}")
    for i in range(1, 32):
        if hw["regs"][i] != ref["regs"][i]:
            diffs.append(f"x{i}: placa {hw['regs'][i]:#010x}, modelo {ref['regs'][i]:#010x}")
    for i, (a, b) in enumerate(zip(hw["dmem"], ref["dmem"])):
        if a != b:
            diffs.append(f"dmem[{i}]: placa {a:#010x}, modelo {b:#010x}")
    return diffs
