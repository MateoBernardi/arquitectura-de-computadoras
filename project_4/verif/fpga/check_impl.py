#!/usr/bin/env python3
"""Chequeos de la implementación: STA completo, ruteo, DRC, metodología y cruces de reloj.

Uso: check_impl.py <log de impl_1 (runme.log)> <carpeta de reportes de impl.tcl> <waivers.txt>

  - STA: check_timing sin nada sin restringir (si un camino no está restringido, STA no
    lo analiza y diría "0 violaciones" sin haberlo mirado); setup, hold y ancho de pulso
    con margen >= 0 en todos los caminos
  - cruces entre dominios de reloj: todos seguros
  - ruteo: todas las redes ruteadas, sin errores
  - DRC y metodología: cada violación justificada en waivers.txt (o falla)
Escribe un renglón [ok ] / [MAL] por chequeo.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_synth import check, load_waivers, results  # noqa: E402


def read(rep, name):
    path = os.path.join(rep, name)
    if not os.path.exists(path):
        check(False, f"no se generó {name}")
        return ""
    return open(path, encoding="utf-8", errors="replace").read()


def sta(rep):
    ct = read(rep, "check_timing.rpt")
    items = re.findall(r"^\s*\d+\. checking (\w+) \((\d+)\)", ct, re.M)
    seen = {}
    for name, n in items:
        seen.setdefault(name, int(n))           # el reporte repite la lista: la primera vez
    check(len(seen) >= 10, f"check_timing: {len(seen)} categorías revisadas")
    # En no_input_delay / no_output_delay, check_timing cuenta también los puertos excluidos a
    # propósito con set_false_path (el motivo está en el XDC): esos se informan, no fallan.
    # Lo que falla es un puerto sin ninguna restricción.
    io = {"no_input_delay": r"There are (\d+) input ports with no input delay specified",
          "no_output_delay": r"There are (\d+) ports with no output delay specified"}
    for name, n in seen.items():
        if name in io:
            m = re.search(io[name], sec.group(1)) if (sec := re.search(rf"checking {name} \({n}\)\n-+\n(.*?)(?=\n\d+\. checking|\Z)", ct, re.S)) else None
            free = int(m.group(1)) if m else n
            sec = re.search(rf"checking {name} \({n}\)\n-+\n(.*?)(?=\n\d+\. checking|\Z)", ct, re.S)
            fp = re.search(r"There are (\d+) (?:input )?ports with no (?:input|output) delay but user has a false path"
                           r"[^\n]*\n+((?:\S+\n)+)", sec.group(1) + "\n" if sec else "")
            excluded = fp.group(2).split() if fp else []
            check(free == 0, f"check_timing {name}: {free} puertos sin restricción"
                  + (f"; excluidos con set_false_path (ver XDC): {' '.join(excluded)}" if excluded else ""))
        else:
            check(n == 0, f"check_timing {name}: {n}")

    ts = read(rep, "timing_summary.rpt")
    m = re.search(r"Design Timing Summary.*?\n\s*WNS\(ns\).*?\n\s*-+.*?\n\s*(.+?)\n", ts, re.S)
    if not m:
        check(False, "no se encontró la tabla Design Timing Summary")
        return
    v = m.group(1).split()
    wns, tns, whs, ths, wpws, tpws = (float(v[i]) for i in (0, 1, 4, 5, 8, 9))
    check(wns >= 0 and tns == 0, f"setup: WNS = {wns:+.3f} ns, TNS = {tns}")
    check(whs >= 0 and ths == 0, f"hold: WHS = {whs:+.3f} ns, THS = {ths}")
    check(wpws >= 0 and tpws == 0, f"ancho de pulso: WPWS = {wpws:+.3f} ns, TPWS = {tpws}")
    check("All user specified timing constraints are met." in ts, "todas las restricciones de timing se cumplen")

    clocks = read(rep, "clocks.rpt")
    sysclk = re.search(r"^\S*clk_out\S*\s+([\d.]+)\s", clocks, re.M)
    if sysclk:
        period = float(sysclk.group(1))
        print(f"      reloj del sistema: {period:.3f} ns ({1000 / period:.2f} MHz); "
              f"Fmax estimada por el margen de setup: {1000 / (period - wns):.2f} MHz")


def cdc(rep):
    text = read(rep, "cdc.rpt")
    unsafe = re.findall(r"^\|?\s*(Critical|Warning)\s.*(Unsafe|Unknown)", text, re.M)
    check("All paths are Safely Timed." in text or not unsafe,
          "cruces entre dominios de reloj: todos seguros" if not unsafe
          else f"cruces entre dominios de reloj inseguros: {len(unsafe)}")


def route(rep):
    text = read(rep, "route_status.rpt")
    num = lambda label: int(re.search(re.escape(label) + r"\.*\s*:\s*(\d+)", text).group(1))
    try:
        routable, routed, errors = num("# of routable nets"), num("# of fully routed nets"), num("# of nets with routing errors")
    except AttributeError:
        check(False, "no se pudo leer route_status.rpt")
        return
    check(routable == routed and errors == 0,
          f"ruteo: {routed}/{routable} redes ruteadas, {errors} con errores")


def violations(rep, name, waivers):
    """report_drc / report_methodology: cada violación tiene que estar justificada."""
    text = read(rep, name)
    found = re.findall(r"^([A-Z]+-\d+)#\d+\s+(\S+.*)\n(.*)\n(.*)", text, re.M)
    groups = {}
    for rule, sev, title, msg in found:
        for w in waivers:
            if w["id"] == rule and (w["re"].search(title) or w["re"].search(msg)):
                w["hits"] += 1
                groups.setdefault(("ok", rule, w["why"]), 0)
                groups[("ok", rule, w["why"])] += 1
                break
        else:
            groups.setdefault(("mal", rule, f"{sev}: {title.strip()}"), 0)
            groups[("mal", rule, f"{sev}: {title.strip()}")] += 1
    label = name.replace(".rpt", "")
    if not groups:
        check(True, f"{label}: sin violaciones")
    for (kind, rule, why), n in sorted(groups.items()):
        check(kind == "ok", f"{label} {rule} ({n}): " + (f"justificado: {why}" if kind == "ok" else f"sin justificar — {why}"))


def main():
    log_path, rep, waivers_path = sys.argv[1:4]
    log = open(log_path, encoding="utf-8", errors="replace").read() if os.path.exists(log_path) else ""
    check("route_design completed successfully" in log, "la implementación terminó (place & route)")
    waivers = [w for w in load_waivers(waivers_path) if re.match(r"^[A-Z]+-\d+$", w["id"])]
    sta(rep)
    cdc(rep)
    route(rep)
    violations(rep, "drc.rpt", waivers)
    violations(rep, "methodology.rpt", waivers)
    for w in waivers:
        if not w["hits"]:
            check(False, f"[{w['id']}] ninguna violación corresponde a esta justificación (waivers.txt:{w['line']})")
    sys.exit(0 if results and all(results) else 1)


if __name__ == "__main__":
    main()
