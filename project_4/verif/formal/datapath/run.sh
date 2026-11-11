#!/usr/bin/env bash
# Datapath: decodificación + ALU + branch_unit, y dmem, contra el manual RV32I.
NAME=datapath
source "$(dirname "$0")/../../tools/suite.sh"
R=../../../rtl/pipeline

mutate $R/3_execute/alu.v   sra 's/OP_SRA: alu_result = i_data_a >>> shamt;/OP_SRA: alu_result = i_data_a >> shamt;/'   # SRA sin extender el signo
mutate $R/4_memory/dmem.v   sb  's/(sb ? wdata\[7:0\] : wdata\[15:8\])/wdata[15:8]/'                                      # sb al byte 3 escribe el byte equivocado
mutate $R/2_decode/illegal_check.v ill 's/7'"'"'b0110011: illegal = !((funct7 == 7'"'"'b0000000) ||/7'"'"'b0110011: illegal = !((funct7 == 7'"'"'b0000000) || (funct7 == 7'"'"'b0000001) ||/'  # acepta mul/div (extensión M)

expect exec       PASS
expect exec_cover PASS brief
expect mut_sra    FAIL
expect dmem       PASS
expect dmem_cover PASS brief
expect mut_sb     FAIL
expect illegal    PASS
expect mut_ill    FAIL
exit $STATUS
