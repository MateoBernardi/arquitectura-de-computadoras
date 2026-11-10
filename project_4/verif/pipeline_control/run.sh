#!/usr/bin/env bash
# pipeline_control: propiedades temporales (BMC e inducción con invariantes).
NAME=pipeline
source ../tools/suite.sh
FLOW=../../project_4.srcs/sources_1/new/pipeline/flow
REGS=../../project_4.srcs/sources_1/new/pipeline/regs

# Mutantes del RTL real
mutate $FLOW/flush_unit.v flush 's/assign flush_id_ex = redirect;/assign flush_id_ex = 1'"'"'b0;/'  # 1 sola burbuja tras un salto
mutate $REGS/pipe_reg.v   stall 's/end else if (!stall) begin/end else begin/'                   # IF/ID no se congela en un stall

expect bmc       PASS
expect prove     PASS
expect cover     PASS brief
expect mut_flush FAIL
expect mut_stall FAIL
exit $STATUS
