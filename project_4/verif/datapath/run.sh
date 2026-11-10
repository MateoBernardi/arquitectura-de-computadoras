#!/usr/bin/env bash
# Datapath: decodificación + ALU + branch_unit, y dmem, contra el manual RV32I.
NAME=datapath
source ../tools/suite.sh
R=../../project_4.srcs/sources_1/new/pipeline

mutate $R/3_execute/alu.v   sra 's/OP_SRA: alu_result = i_data_a >>> shamt;/OP_SRA: alu_result = i_data_a >> shamt;/'   # SRA sin extender el signo
mutate $R/4_memory/dmem.v   sb  's/(sb ? wdata\[7:0\] : wdata\[15:8\])/wdata[15:8]/'                                      # sb al byte 3 escribe el byte equivocado

expect exec       PASS
expect exec_cover PASS brief
expect mut_sra    FAIL
expect dmem       PASS
expect dmem_cover PASS brief
expect mut_sb     FAIL
exit $STATUS
