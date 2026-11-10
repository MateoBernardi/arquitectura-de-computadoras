#!/usr/bin/env bash
# forward_unit: prueba, cobertura y mutantes.
NAME=forward_unit
source ../tools/suite.sh
RTL=../../project_4.srcs/sources_1/new/pipeline/flow/forward_unit.v

# Mutantes: copias del RTL con UN error típico cada una
mutate $RTL prio 's/if (wb_rd == ex_rs1 \&\& !(mem_reg_write \&\& mem_rd == ex_rs1))/if (wb_rd == ex_rs1)/'   # WB le gana a MEM
mutate $RTL x0   's/if (mem_reg_write \&\& (mem_rd != 5'"'"'b0))/if (mem_reg_write)/'                         # se reenvía x0
mutate $RTL rs2  's/if (mem_rd == ex_rs2) forward_b/if (mem_rd == ex_rs1) forward_b/'                       # copy-paste rs1/rs2

expect prove    PASS
expect cover    PASS brief
expect mut_prio FAIL
expect mut_x0   FAIL
expect mut_rs2  FAIL
exit $STATUS
