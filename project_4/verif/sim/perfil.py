#!/usr/bin/env python3
"""perfil.py — desglose del CPI por categoría de instrucción y por causa de penalización.

    ./perfil.py                      diseño base: los programas de programs/ y la suite ACT
    ./perfil.py --variante <nombre>  con una variante (ver verif/variants/)
    ./perfil.py --elf a.elf b.elf    solo esos ELFs

Usa el simulador de Verilator con +perfil (tb.sv): cada instrucción retirada cuenta en su
categoría y cada ciclo perdido se carga a la instrucción que lo causa (el load en un stall
de load-use; el branch tomado, jal o jalr en un redirect). CPI ideal = 1: el pipeline
retira una instrucción por ciclo si no pierde ninguno. Las memorias responden en el mismo
ciclo, así que no hay ciclos de espera por memoria (la única penalización ligada a la
memoria es el stall de load-use).

Escribe el desglose en la salida y en build/reports/perfil.md (o --salida).
"""
import argparse
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bench  # noqa: E402  (mismos programas, ensamblado y entorno)

CATS = [("alu_r", "ALU registro-registro"), ("alu_i", "ALU con inmediato"),
        ("lui_auipc", "lui / auipc"), ("load", "load"), ("store", "store"),
        ("branch_tomado", "branch tomado"), ("branch_no_tomado", "branch no tomado"),
        ("jal", "jal"), ("jalr", "jalr"), ("system", "ecall / ebreak / trap (fin)")]
PERF = re.compile(r"tb: perfil (\w+) n=(\d+) penal=(\d+)")


def perfil(variant, elf):
    env = dict(bench.ENV, VARIANT=variant)
    r = subprocess.run([os.path.join(HERE, "run_elf.sh"), elf, "+perfil"], capture_output=True,
                       text=True, env=env)
    m = bench.HALT.search(r.stdout)
    if not m:
        sys.exit(f"{elf}: el simulador no llegó al halt\n{r.stdout[-2000:]}")
    cats = {k: (int(n), int(p)) for k, n, p in PERF.findall(r.stdout)}
    return int(m.group(1)), int(m.group(2)), cats


def table(title, cycles, instret, cats):
    pen = {k: p for k, (n, p) in cats.items()}
    total_pen = sum(pen.values())
    fill = cycles - instret - total_pen
    out = [f"### {title}", "",
           f"{instret} instrucciones, {cycles} ciclos: **CPI = {cycles / instret:.3f}** (ideal 1.000)", "",
           "| Categoría | Instrucciones | % de la mezcla | Ciclos perdidos | CPI de la categoría | Aporte al CPI |",
           "|---|---|---|---|---|---|"]
    for k, label in CATS:
        n, p = cats.get(k, (0, 0))
        if n == 0 and p == 0:
            continue
        cpi_cat = f"{(n + p) / n:.2f}" if n else "—"
        out.append(f"| {label} | {n} | {100 * n / instret:.1f} % | {p} | {cpi_cat} | +{p / instret:.3f} |")
    out += ["", "| Causa | Ciclos | Aporte al CPI |", "|---|---|---|",
            "| ideal (1 instrucción por ciclo) | %d | 1.000 |" % instret]
    causes = [("stall de load-use", pen.get("load", 0)),
              ("flush por branch tomado", pen.get("branch_tomado", 0)),
              ("flush por jal", pen.get("jal", 0)),
              ("flush por jalr", pen.get("jalr", 0)),
              ("espera por memoria", 0),
              ("llenado y vaciado del pipeline", fill)]
    for label, c in causes:
        out.append(f"| {label} | {c} | +{c / instret:.3f} |")
    out.append(f"| **total** | **{cycles}** | **{cycles / instret:.3f}** |")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variante", default="base")
    ap.add_argument("--elf", nargs="+")
    ap.add_argument("--salida", default=os.path.join(bench.ROOT, "build", "reports", "perfil.md"))
    a = ap.parse_args()
    os.makedirs(bench.WORK, exist_ok=True)
    groups = []
    if a.elf:
        groups = [(os.path.basename(e), [e]) for e in a.elf]
    else:
        for name, src in bench.PROGRAMS:
            groups.append((name, [bench.assemble(src)]))
        if bench.ACT_ELFS:
            groups.append((f"ACT ({len(bench.ACT_ELFS)} tests)", bench.ACT_ELFS))
    doc = [f"# Desglose del CPI — `{a.variante}`", ""]
    for title, elfs in groups:
        cycles = instret = 0
        cats = {}
        for e in elfs:
            c, i, cs = perfil(a.variante, e)
            cycles += c; instret += i
            for k, (n, p) in cs.items():
                n0, p0 = cats.get(k, (0, 0)); cats[k] = (n0 + n, p0 + p)
        doc.append(table(title, cycles, instret, cats))
    text = "\n".join(doc)
    print(text)
    os.makedirs(os.path.dirname(a.salida), exist_ok=True)
    open(a.salida, "w").write(text)


if __name__ == "__main__":
    main()
