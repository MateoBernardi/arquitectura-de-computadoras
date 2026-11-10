#!/usr/bin/env bash
# Compila el simulador (build/Vtb) con Verilator.
set -euo pipefail
cd "$(dirname "$0")"
source ../verif/env.sh
RTL=../project_4.srcs/sources_1/new/pipeline
verilator --binary --timing -O3 -Wno-fatal -Wno-WIDTH -Wno-lint \
    -I"$RTL/3_execute" --top-module tb -Mdir build -o Vtb \
    tb.sv \
    "$RTL/riscv_pipeline.v" "$RTL/1_fetch/imem.v" \
    "$RTL/2_decode/control.v" "$RTL/2_decode/immgen.v" "$RTL/2_decode/regfile.v" \
    "$RTL/2_decode/illegal_check.v" "$RTL/flow/trap_unit.v" \
    "$RTL/3_execute/alu.v" "$RTL/3_execute/branch_unit.v" \
    "$RTL/4_memory/dmem.v" \
    "$RTL/flow/flush_unit.v" "$RTL/flow/forward_unit.v" "$RTL/flow/hazard_unit.v" \
    "$RTL/regs/pipe_reg.v" \
    -j 0 "$@"
