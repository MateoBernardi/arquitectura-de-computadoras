#!/usr/bin/env python3
"""informe.py — resumen de los informes de Vivado para presentar el CPU (no es un chequeo).

    informe.py utilizacion <utilizacion.rpt> <utilizacion_jerarquica.rpt>
    informe.py implementacion <carpeta de reportes de impl.tcl> [potencia_saif.rpt]

`utilizacion` lo usa la capa sintesis al final (recursos del netlist sintetizado).
`implementacion` resume lo que deja impl.tcl: recursos después del place & route, el
camino crítico tramo por tramo, la distribución de niveles de lógica y la potencia
estimada (la de power.tcl, con actividad simulada, si se le pasa). Escribe markdown.
"""
import os
import re
import sys

RESOURCES = [("Slice LUTs", "LUT"), ("LUT as Logic", "  LUT de lógica"),
             ("LUT as Memory", "  LUT como memoria (LUTRAM)"), ("Slice Registers", "FF (registros)"),
             ("F7 Muxes", "MUXF7"), ("F8 Muxes", "MUXF8"), ("Block RAM Tile", "BRAM (36 Kb)"),
             ("DSPs", "DSP"), ("Bonded IOB", "pines de E/S"), ("BUFGCTRL", "buffers de reloj (BUFG)"),
             ("MMCME2_ADV", "MMCM")]


def table_rows(text):
    for line in text.splitlines():
        if line.startswith("|") and not line.startswith("+"):
            yield [c.strip() for c in line.strip().strip("|").split("|")]


def utilization(flat, hier):
    out = ["| Recurso | Usados | Disponibles | % |", "|---|---|---|---|"]
    seen = set()
    for row in table_rows(open(flat).read()):
        name = row[0].rstrip("*").strip()   # la síntesis marca algunos con *
        for key, label in RESOURCES:
            if name == key and key not in seen and len(row) >= 5:
                seen.add(key)
                out.append(f"| {label} | {row[1]} | {row[-2]} | {row[-1]} |")
    out += ["", "Por módulo (las sumas pueden no coincidir: Vivado combina LUTs entre módulos):", "",
            "| Instancia | Módulo | LUT | LUTRAM | FF | BRAM | DSP |", "|---|---|---|---|---|---|---|"]
    header = None
    for line in open(hier).read().splitlines():
        if not line.startswith("|"):
            continue
        row = [c.strip() for c in line.strip().strip("|").split("|")]
        depth = (len(line) - len(line[1:].lstrip()) - 2) // 2   # sangría = profundidad
        if row[0] == "Instance":
            header = row
            continue
        if not header or row[0].startswith("("):
            continue
        d = dict(zip(header, row))
        inst = row[0]
        bram = int(d.get("RAMB36", 0)) + int(d.get("RAMB18", 0))
        out.append(f"| {'· ' * depth}{inst} | {d['Module']} | {d['Total LUTs']} | {d['LUTRAMs']} | {d['FFs']} | "
                   f"{bram} | {d['DSP Blocks']} |")
    return "\n".join(out)


def critical_path(rpt):
    text = open(rpt).read()
    first = text.split("Slack", 2)
    path = "Slack" + first[1]
    get = lambda k: re.search(rf"{k}:\s+(.*)", path).group(1).strip()
    slack = re.search(r"Slack \((\w+)\)\s*:\s*(-?[\d.]+)ns", path)
    req = float(re.search(r"Requirement:\s+([\d.]+)ns", path).group(1))
    dp = re.search(r"Data Path Delay:\s+([\d.]+)ns\s+\(logic ([\d.]+)ns \(([\d.]+)%\)\s+route ([\d.]+)ns", path)
    out = [f"- desde `{get('Source')}`", f"- hasta `{get('Destination')}`",
           f"- período {req:.3f} ns, margen (slack) {float(slack.group(2)):+.3f} ns ({slack.group(1)})",
           f"- retardo del dato {dp.group(1)} ns: lógica {dp.group(2)} ns ({dp.group(3)} %), "
           f"ruteo {dp.group(4)} ns ({100 - float(dp.group(3)):.1f} %)",
           f"- niveles de lógica: {get('Logic Levels')}", "",
           "Tramo por tramo (celda → la red que sale de ella):", "",
           "| Celda | Tipo | Retardo celda (ns) | Red | Fanout | Retardo red (ns) | Acumulado (ns) |",
           "|---|---|---|---|---|---|---|"]
    lines = path.split("Netlist Resource(s)")[1].splitlines()
    rows, pending = [], None
    for i, l in enumerate(lines):
        m = re.match(r"\s+SLICE\S*\s+(\w+) \(Prop_[^)]*\)\s*([\d.]+)?\s*(-?[\d.]+)?\s*[rf]?\s*(\S+)?", l)
        if m:
            if m.group(2) is None:
                n = re.match(r"\s+([\d.]+)\s+(-?[\d.]+)\s+[rf]\s+(\S+)", lines[i + 1])
                pending = [m.group(1), n.group(1), n.group(3)]
            else:
                pending = [m.group(1), m.group(2), m.group(4)]
            continue
        n = re.match(r"\s+net \(fo=(\d+), routed\)\s+([\d.]+)\s+(-?[\d.]+)\s+(\S+)", l)
        if n and pending:
            rows.append(f"| `{pending[2]}` | {pending[0]} | {pending[1]} | `{n.group(4)}` | {n.group(1)} | "
                        f"{n.group(2)} | {n.group(3)} |")
            pending = None
        if l.strip().startswith("---") and rows:
            break
    return "\n".join(out + rows)


def logic_levels(rpt):
    rows = list(table_rows(open(rpt).read()))
    for i, r in enumerate(rows):
        if r[0] == "End Point Clock":
            data = rows[i + 1]
            return ("Niveles de lógica de los 1000 peores caminos: " +
                    ", ".join(f"{lv} niveles: {n}" for lv, n in zip(r[2:], data[2:])))
    return ""


def power(rpt, title):
    text = open(rpt).read()
    val = lambda k: re.search(rf"\| {re.escape(k)}\s+\|\s+([<\d.]+)", text).group(1)
    conf = re.search(r"Confidence Level\s+\|\s+(\w+)", text).group(1)
    out = [f"**{title}** (confianza de Vivado: {conf})", "",
           "| | W |", "|---|---|",
           f"| total en el chip | {val('Total On-Chip Power (W)')} |",
           f"| estática (fugas del chip, con o sin diseño) | {val('Device Static (W)')} |",
           f"| dinámica | {val('Dynamic (W)')} |"]
    for k, label in [("Clocks", "  relojes"), ("Slice Logic", "  lógica (LUT, FF, LUTRAM)"),
                     ("Signals", "  señales (ruteo)"), ("MMCM", "  MMCM"), ("I/O", "  E/S")]:
        m = re.search(rf"^\| {re.escape(k)}\s+\|\s+([<\d.]+)", text, re.M)
        if m:
            out.append(f"| {label} | {m.group(1)} |")
    act = re.search(r"Simulation Activity File\s+\|\s+(.*?)\s+\|", text)
    matched = re.search(r"Design Nets Matched\s+\|\s+(.*?)\s+\|", text)
    if act and act.group(1) != "---":
        out.append(f"\nActividad: `{os.path.basename(act.group(1))}`, redes con actividad: {matched.group(1)}")
    return "\n".join(out)


def main():
    if len(sys.argv) >= 4 and sys.argv[1] == "utilizacion":
        print(utilization(sys.argv[2], sys.argv[3]))
    elif len(sys.argv) >= 3 and sys.argv[1] == "implementacion":
        d = sys.argv[2]
        parts = ["## Recursos (después del place & route)", "",
                 utilization(f"{d}/utilizacion.rpt", f"{d}/utilizacion_jerarquica.rpt"), "",
                 "## Camino crítico", "", critical_path(f"{d}/caminos_criticos.rpt"), "",
                 logic_levels(f"{d}/niveles_logica.rpt"), "",
                 "## Potencia estimada", "", power(f"{d}/potencia_vectorless.rpt",
                                                  "Sin actividad simulada (tasas por defecto)")]
        if len(sys.argv) >= 4 and os.path.exists(sys.argv[3]):
            parts += ["", power(sys.argv[3], "Con la actividad de una simulación")]
        print("\n".join(parts))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
