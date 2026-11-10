#!/usr/bin/env bash
# hazard_unit: seguridad, precisión y la variante precisa.
NAME=hazard_unit
source ../tools/suite.sh
RTL=../../project_4.srcs/sources_1/new/pipeline/flow/hazard_unit.v

# Mutantes del RTL real
mutate $RTL rs2  's/ || (ex_rd == id_rs2)//'           # se olvida comparar rs2
mutate $RTL load 's/if (ex_mem_read \&\& /if (/'         # frena por cualquier instrucción, no solo loads

expect prove    PASS
expect cover    PASS brief
expect exact    FAIL
expect precise  PASS
expect mut_rs2  FAIL
expect mut_load FAIL
exit $STATUS
