#!/usr/bin/env bash
# El sistema completo (top_riscv: UART + debug unit + CPU) con el testbench tb_top_riscv.v,
# simulado con Icarus Verilog. Lo maneja por la línea serie, como el host de Python:
# carga, step, run, dump, pausa, reset, traps, errores.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../env.sh"
OUT="$HERE/build"; mkdir -p "$OUT"
cp "$HERE"/*.hex "$OUT/"
mapfile -t RTL < <(find "$RTL_DIR" -name '*.v')
iverilog -g2012 -I"$RTL_DIR/pipeline/3_execute" -o "$OUT/tb_top_riscv" \
    "$HERE/tb_top_riscv.v" "${RTL[@]}" || exit 2
(cd "$OUT" && vvp -n tb_top_riscv > tb_top_riscv.log)
grep -E "^(OK|FAIL|--)" "$OUT/tb_top_riscv.log"
grep -q "^PASS:" "$OUT/tb_top_riscv.log" || { echo "FAIL (log: $OUT/tb_top_riscv.log)"; exit 1; }
grep "^PASS:" "$OUT/tb_top_riscv.log"
