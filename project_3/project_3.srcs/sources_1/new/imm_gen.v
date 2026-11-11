`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// imm_gen: generador de inmediatos RV32I (combinacional)
//
// Arma el inmediato de 32 bits segun el formato que indica la unidad de
// control. El signo sale siempre de instr[31]; en B y J el bit 0 es 0.
//   I: imm[11:0]              = instr[31:20]
//   S: imm[11:5] | imm[4:0]   = instr[31:25] | instr[11:7]
//   B: imm[12|10:5] | imm[4:1|11] = instr[31:25] | instr[11:7]
//   U: imm[31:12]             = instr[31:12]
//   J: imm[20|10:1|11|19:12]  = instr[31:12]
// Sin inmediato (tipo R, ilegal): 0.
// -----------------------------------------------------------------------------
module imm_gen (
    input  wire [31:0] i_instruction,
    input  wire [2:0]  i_imm_sel,
    output reg  [31:0] o_imm
);
    `include "riscv_defs.vh"

    wire [31:0] instr = i_instruction;

    always @(*) begin
        case (i_imm_sel)
            IMM_I:   o_imm = {{20{instr[31]}}, instr[31:20]};
            IMM_S:   o_imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            IMM_B:   o_imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            IMM_U:   o_imm = {instr[31:12], 12'd0};
            IMM_J:   o_imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default: o_imm = 32'd0;
        endcase
    end
endmodule
