#!/usr/bin/env python3
"""Chequeos de la síntesis: que el netlist sea lo que pide el RTL.

Uso: check_synth.py <log de la síntesis (runme.log)> <carpeta del RTL> <waivers.txt>

No compara contra números esperados (LUTs, FFs): compara contra el RTL.
  - la síntesis terminó, sin errores ni critical warnings
  - no hay latches (el RTL nunca los pide)
  - cada aviso de Vivado está justificado en waivers.txt; un aviso sin justificar falla,
    y una justificación que ya no corresponde a ningún aviso también
  - Vivado no eliminó lógica secuencial del RTL (aunque lo informe como INFO)
  - cada arreglo del RTL se implementó como RAM (o está justificado como MEM en
    waivers.txt), y no aparece ninguna RAM que el RTL no declare
Escribe un renglón [ok ] / [MAL] por chequeo.
"""
import glob
import os
import re
import sys

# INFO que igual indican que el netlist se aparta del RTL: lógica secuencial eliminada
REMOVAL_IDS = ("Synth 8-3332", "Synth 8-6014", "Synth 8-3333", "Synth 8-7137")
MSG = re.compile(r"^(INFO|WARNING|CRITICAL WARNING|ERROR): \[([^\]]+)\] (.*)$")
RTL_ARRAY = re.compile(r"^\s*reg\s*(?:\[[^\]]*\])?\s*(\w+)\s*\[[^\]]*\]\s*;", re.M)
RTL_MODULE = re.compile(r"^\s*module\s+(\w+)", re.M)

results = []


def check(ok, text):
    results.append(ok)
    print(f"[{'ok ' if ok else 'MAL'}] {text}")


def short(msg):
    """Saca las rutas absolutas del mensaje."""
    return re.sub(r"\[/[^\]]*/(rtl/[^\]]*)\]", r"[\1]", msg)


def load_waivers(path):
    waivers = []
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|", 2)]
        if len(parts) != 3 or not parts[2]:
            sys.exit(f"{path}:{n}: formato inválido (ID | expresión | por qué)")
        waivers.append({"id": parts[0], "re": re.compile(parts[1]), "why": parts[2], "hits": 0, "line": n})
    return waivers


def rtl_arrays(rtl):
    found = []
    for f in sorted(glob.glob(os.path.join(rtl, "**", "*.v"), recursive=True)):
        src = re.sub(r"//.*", "", open(f, encoding="utf-8").read())
        m = RTL_MODULE.search(src)
        for name in RTL_ARRAY.findall(src):
            found.append((m.group(1) if m else "?", name))
    return found


def inferred_rams(log):
    """Objetos de las tablas 'Final Mapping Report' (RAM distribuida y BRAM)."""
    rams, in_table = set(), False
    for line in log.splitlines():
        if re.match(r"^(Distributed RAM|Block RAM): Final Mapping Report", line):
            in_table = True
            continue
        if in_table:
            if not line.strip():
                in_table = False
                continue
            cols = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cols) >= 2 and cols[1].endswith("_reg"):
                rams.add(cols[1].split("/")[-1][: -len("_reg")])
    return rams


def main():
    log_path, rtl, waivers_path = sys.argv[1:4]
    log = open(log_path, encoding="utf-8", errors="replace").read()
    # solo las justificaciones de la síntesis (IDs "Synth ..." y MEM)
    waivers = [w for w in load_waivers(waivers_path) if w["id"].startswith("Synth ") or w["id"] == "MEM"]
    msgs = [m.groups() for m in map(MSG.match, log.splitlines()) if m]

    check(re.search(r"^synth_design completed successfully", log, re.M) is not None
          or "Synthesis finished with 0 errors" in log, "la síntesis terminó")
    for sev in ("ERROR", "CRITICAL WARNING"):
        bad = [f"[{i}] {short(t)}" for s, i, t in msgs if s == sev]
        check(not bad, f"{sev.lower()}s: {len(bad)}" + "".join(f"\n        {b}" for b in bad[:10]))

    latch_cells = re.findall(r"^\|\s*\d+\s*\|(LD\w+)\s*\|\s*(\d+)\|", log, re.M)
    latch_msgs = [t for s, i, t in msgs if i == "Synth 8-327"]
    check(not latch_cells and not latch_msgs, f"latches: {len(latch_msgs) + len(latch_cells)}")

    # avisos (y la lógica eliminada) contra las justificaciones
    unjustified = []
    for sev, mid, text in msgs:
        if sev != "WARNING" and mid not in REMOVAL_IDS:
            continue
        if sev == "INFO" or mid in REMOVAL_IDS:
            sev = "lógica eliminada"
        for w in waivers:
            if w["id"] == mid and w["re"].search(text):
                w["hits"] += 1
                break
        else:
            unjustified.append(f"{sev} [{mid}] {short(text)}")
    for u in unjustified:
        check(False, f"aviso sin justificar: {u}")
    for w in waivers:
        if w["id"] == "MEM":
            continue
        check(w["hits"] > 0, f"[{w['id']}] {w['re'].pattern}: "
              + (f"{w['hits']} avisos, justificados: {w['why']}" if w["hits"]
                 else f"ningún aviso corresponde a esta justificación (waivers.txt:{w['line']})"))

    # memorias: el RTL contra lo que infirió Vivado
    rams = inferred_rams(log)
    arrays = rtl_arrays(rtl)
    check(bool(arrays), f"arreglos declarados en el RTL: {len(arrays)}")
    mem_waivers = {w["re"].pattern: w for w in waivers if w["id"] == "MEM"}
    for module, name in arrays:
        key = f"{module}.{name}"
        if name in rams:
            check(True, f"{key}: implementado como RAM")
        elif key in mem_waivers:
            mem_waivers[key]["hits"] += 1
            check(True, f"{key}: no es RAM, justificado: {mem_waivers[key]['why']}")
        else:
            check(False, f"{key}: el RTL declara un arreglo y Vivado no infirió una RAM")
    rtl_names = {name for _, name in arrays}
    for r in sorted(rams - rtl_names):
        check(False, f"RAM inferida que no corresponde a ningún arreglo del RTL: {r}")
    for key, w in mem_waivers.items():
        if not w["hits"]:
            check(False, f"MEM {key}: el RTL ya no declara ese arreglo (waivers.txt:{w['line']})")
        elif key.split(".")[1] in rams:
            check(False, f"MEM {key}: está justificado como no-RAM pero Vivado lo infirió como RAM")

    sys.exit(0 if results and all(results) else 1)


if __name__ == "__main__":
    main()
