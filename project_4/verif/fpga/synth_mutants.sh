#!/usr/bin/env bash
# Mutantes de la síntesis: una copia del RTL con errores inyectados, que check_synth.py
# tiene que detectar. Comprueba que el chequeo realmente mira los avisos de Vivado y la
# lógica que elimina (si una versión de Vivado cambia los IDs de los mensajes, falla acá).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../env.sh"
WORK="$PROJ/build/vivado_mutantes"
rm -rf "$WORK"; mkdir -p "$WORK"; cp -r "$RTL_DIR" "$WORK/rtl"

mutate() {   # mutate <archivo de rtl/> <texto original> <reemplazo>
    python3 - "$WORK/rtl/$1" "$2" "$3" <<'PY' || exit 1
import sys
p, a, b = sys.argv[1:]
s = open(p).read()
if s.count(a) != 1:
    sys.exit(f"ERROR: el mutante no encontró el texto en {p} (¿cambió el RTL?)")
open(p, "w").write(s.replace(a, b))
PY
}
# 1. latch: tval no se asigna en todos los caminos del always combinacional
mutate pipeline/flow/trap_unit.v "            tval  = addr;" "            if (mem) tval  = addr;"
# 2. lógica secuencial que Vivado elimina (un registro que nadie lee)
mutate top/top_riscv.v "    // Bus de debug: las palabras del CPU y, al final, BUILD_ID" \
"    reg [7:0] dead_reg;
    always @(posedge clk) dead_reg <= rx_data;
    // Bus de debug: las palabras del CPU y, al final, BUILD_ID"

export TP4_RTL_DIR="$WORK/rtl" TP4_PROJECT_DIR="$WORK/vivado"
vivado -mode batch -nojournal -log "$WORK/vivado.log" -source "$HERE/create_project.tcl" > /dev/null || exit 1
vivado -mode batch -nojournal -log "$WORK/vivado.log" -source "$HERE/synth.tcl" > /dev/null || exit 1
python3 "$HERE/check_synth.py" "$WORK/vivado/tp4.runs/synth_1/runme.log" "$WORK/rtl" "$HERE/waivers.txt" \
    > "$WORK/check.log"

expect() {   # expect <nombre> <expresión que tiene que aparecer como [MAL]>
    if grep -q "^\[MAL\].*$2" "$WORK/check.log"; then echo "[ok ] mutante $1: detectado"
    else echo "[MAL] mutante $1: check_synth.py no lo detectó (ver $WORK/check.log)"; fi
}
expect latch          "Synth 8-327"
expect registro_libre "lógica eliminada.*dead_reg"
