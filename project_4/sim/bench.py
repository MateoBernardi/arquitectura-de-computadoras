#!/usr/bin/env python3
"""bench.py — tabla de rendimiento del CPU base y de cada variante (verif/variants/).

    ./bench.py                          todas las variantes
    ./bench.py hazard_unit_nostall      solo esa (y el diseño base)

Para cada programa informa instrucciones retiradas, ciclos y CPI, y compara el estado
final (firma de registros y dmem) contra el diseño base: si una variante termina con
otro estado, la marca como INCORRECTA. Los ELFs de ACT deben estar compilados
(./run_act.sh); cada uno se autoverifica.
Escribe la tabla también en work/bench.md.
"""
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VARIANTS_DIR = os.path.join(ROOT, "verif", "variants")
XPACK = glob.glob(os.path.join(ROOT, "..", ".tools", "xpack-riscv-none-elf-gcc-*", "bin"))
ENV = dict(os.environ, PATH=os.pathsep.join(XPACK + [os.environ["PATH"]]))
WORK = os.path.join(HERE, "work", "bench")

PROGRAMS = [  # (nombre, fuente) — todos terminan en ebreak
    ("criba", "host/criba.s"),
    ("criba_opt", "host/criba_opt.s"),
    ("criba_unroll", "host/criba_unroll.s"),
    ("suma_arreglo", "sim/bench/suma_arreglo.s"),
    ("pipeline_test", "host/tests/pipeline_test.s"),
    ("test_bypass", "host/test_bypass.s"),
]
ACT_ELFS = sorted(glob.glob(os.path.join(HERE, "work", "tp4-rv32i", "elfs", "**", "*.elf"), recursive=True))
HALT = re.compile(r"ciclos=(\d+)\s+instrucciones=(\d+)\s+causa=(\d+).*firma=([0-9a-f]+)")


def sh(cmd, **kw):
    return subprocess.run(cmd, env=ENV, capture_output=True, text=True, **kw)


def assemble(src):
    name = os.path.splitext(os.path.basename(src))[0]
    obj, elf = os.path.join(WORK, name + ".o"), os.path.join(WORK, name + ".elf")
    for cmd in (["riscv-none-elf-as", "-march=rv32i", "-mabi=ilp32", "-o", obj, os.path.join(ROOT, src)],
                ["riscv-none-elf-ld", "-m", "elf32lriscv", "-Ttext=0", "-o", elf, obj]):
        r = sh(cmd)
        if r.returncode:
            sys.exit(f"{src}: {r.stderr}")
    return elf


def run(variant, elf, *args):
    r = sh([os.path.join(HERE, "run_elf.sh"), elf, *args], cwd=HERE) if variant == "base" else \
        subprocess.run([os.path.join(HERE, "run_elf.sh"), elf, *args], capture_output=True, text=True,
                       env=dict(ENV, VARIANT=variant))
    m = HALT.search(r.stdout)
    if not m:
        return None
    return {"cycles": int(m[1]), "insns": int(m[2]), "cause": int(m[3]), "sig": m[4],
            "ok": r.returncode == 0, "passed": "TEST PASSED" in r.stdout}


def main():
    os.makedirs(WORK, exist_ok=True)
    all_variants = sorted(os.path.splitext(f)[0] for f in os.listdir(VARIANTS_DIR) if f.endswith(".v"))
    variants = ["base"] + (sys.argv[1:] or all_variants)
    for v in variants:
        r = subprocess.run([os.path.join(HERE, "build.sh")] + ([] if v == "base" else [v]),
                           capture_output=True, text=True)
        if r.returncode:
            sys.exit(f"build {v}:\n{r.stdout}{r.stderr}")

    elfs = [(n, assemble(s)) for n, s in PROGRAMS]
    res = {}  # (programa, variante) -> resultado
    for v in variants:
        for n, elf in elfs:
            res[n, v] = run(v, elf, "+expect-cause=3")
        if ACT_ELFS:
            runs = [run(v, e) for e in ACT_ELFS]
            ok = all(x and x["passed"] and x["ok"] for x in runs)
            res["ACT (%d tests)" % len(ACT_ELFS), v] = {
                "cycles": sum(x["cycles"] for x in runs if x), "insns": sum(x["insns"] for x in runs if x),
                "ok": ok, "sig": None, "act": True}

    rows = [n for n, _ in PROGRAMS] + ([f"ACT ({len(ACT_ELFS)} tests)"] if ACT_ELFS else [])
    head = "| Programa | Instrucciones | " + " | ".join(f"`{v}` ciclos (CPI)" for v in variants) + " |"
    out = [head, "|" + "---|" * (2 + len(variants))]
    bad = []
    for n in rows:
        b = res[n, "base"]
        cells = []
        for v in variants:
            x = res[n, v]
            if x is None or not x["ok"]:
                cells.append("**FALLA**"); bad.append((n, v)); continue
            wrong = x["sig"] != b["sig"] or x["insns"] != b["insns"]
            cell = f"{x['cycles']} ({x['cycles'] / x['insns']:.3f})"
            if v != "base":
                cell += f" {100 * (x['cycles'] - b['cycles']) / b['cycles']:+.1f}%"
            if wrong:
                cell += " **INCORRECTA**"; bad.append((n, v))
            cells.append(cell)
        out.append(f"| {n} | {b['insns'] if b else '?'} | " + " | ".join(cells) + " |")
    table = "\n".join(out)
    print(table)
    with open(os.path.join(HERE, "work", "bench.md"), "w") as f:
        f.write(table + "\n")
    if bad:
        print("\nFALLAS:", ", ".join(f"{n} con {v}" for n, v in bad))
        sys.exit(1)


if __name__ == "__main__":
    main()
