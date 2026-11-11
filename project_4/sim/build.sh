#!/usr/bin/env bash
# Compila el simulador con Verilator.
#   ./build.sh                       diseño base        → build/base/Vtb
#   ./build.sh hazard_unit_nostall   con una variante   → build/hazard_unit_nostall/Vtb
# Una variante (verif/variants/<nombre>.v) reemplaza al archivo del RTL que declara su
# módulo (ver verif/tools/variant.sh).
set -euo pipefail
cd "$(dirname "$0")"
source ../verif/env.sh
source ../verif/tools/variant.sh
NAME=${1:-base}
RTL=$PIPELINE_RTL
RF_CHECKS=$(cd ../../.tools/riscv-formal/checks && pwd)

FILES=(riscv_pipeline.v 1_fetch/imem.v
       2_decode/control.v 2_decode/immgen.v 2_decode/regfile.v 2_decode/illegal_check.v
       3_execute/alu.v 3_execute/branch_unit.v 4_memory/dmem.v
       flow/flush_unit.v flow/forward_unit.v flow/hazard_unit.v flow/trap_unit.v
       regs/pipe_reg.v)
SRC=()
if [ "$NAME" != base ]; then
    target=$(variant_target "$NAME")
    echo "variante $NAME: reemplaza $target"
fi
for f in "${FILES[@]}"; do
    if [ "$NAME" != base ] && [ "$f" = "$target" ]; then SRC+=("$(variant_file "$NAME")")
    else SRC+=("$RTL/$f"); fi
done

verilator --binary --timing -O3 -Wno-fatal -Wno-WIDTH -Wno-lint \
    -I"$RTL/3_execute" -I"$RF_CHECKS" --top-module tb -Mdir "build/$NAME" -o Vtb \
    rvfi_sim.vh tb.sv "${SRC[@]}" -j 0 > "build/$NAME.log" 2>&1 \
    || { tail -30 "build/$NAME.log"; exit 1; }
echo "build/$NAME/Vtb"
