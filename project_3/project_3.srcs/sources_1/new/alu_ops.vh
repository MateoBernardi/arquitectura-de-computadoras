// Codigos = {instr[30], funct3}: tienen que coincidir con ALU_* de riscv_defs.vh
// (es lo que genera control_unit).
localparam OP_ADD  = 4'b0000;
localparam OP_SUB  = 4'b1000;
localparam OP_SLL  = 4'b0001;
localparam OP_SLT  = 4'b0010;
localparam OP_SLTU = 4'b0011;
localparam OP_XOR  = 4'b0100;
localparam OP_SRL  = 4'b0101;
localparam OP_SRA  = 4'b1101;
localparam OP_OR   = 4'b0110;
localparam OP_AND  = 4'b0111;
localparam OP_NOR  = 4'b1011;   // no es RV32I, control_unit no la genera
