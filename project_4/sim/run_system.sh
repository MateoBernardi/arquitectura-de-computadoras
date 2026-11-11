#!/usr/bin/env bash
# El sistema completo (top_riscv: UART + debug unit + CPU) con el testbench de Vivado
# sim_1/new/tb_top_riscv.v, simulado con Icarus Verilog. Lo maneja por la línea serie,
# como el host de Python: carga, step, run, dump, pausa, reset, traps, errores.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../verif/env.sh"
SRC="$HERE/../project_4.srcs"
OUT="$HERE/work/system"; mkdir -p "$OUT"
cp "$SRC"/sim_1/new/*.hex "$OUT/"
# riscv_core.v, if_stage.v y pc.v son del core single-cycle, que no forma parte del sistema
mapfile -t RTL < <(find "$SRC/sources_1/new" -name '*.v' ! -name riscv_core.v ! -name if_stage.v ! -name pc.v)
iverilog -g2012 -I"$SRC/sources_1/new/pipeline/3_execute" -o "$OUT/tb_top_riscv" \
    "$SRC/sim_1/new/tb_top_riscv.v" "${RTL[@]}" || exit 2
(cd "$OUT" && vvp -n tb_top_riscv > tb_top_riscv.log)
grep -E "^(OK|FAIL|--)" "$OUT/tb_top_riscv.log"
grep -q "^PASS:" "$OUT/tb_top_riscv.log" || { echo "FAIL (log: $OUT/tb_top_riscv.log)"; exit 1; }
grep "^PASS:" "$OUT/tb_top_riscv.log"
