`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// branch_cmp: condicion de los branches (combinacional)
//
// - Compara rs1 y rs2 (ya con forwarding) segun funct3 (F3_BEQ ... F3_BGEU).
// - o_taken = 1 solo si i_branch = 1 y la condicion se cumple. funct3 invalido
//   no llega aca (control_unit lo marca ilegal y no activa o_branch).
// -----------------------------------------------------------------------------
module branch_cmp (
    input  wire [31:0] i_a,
    input  wire [31:0] i_b,
    input  wire [2:0]  i_funct3,
    input  wire        i_branch,
    output wire        o_taken
);
    `include "riscv_defs.vh"

    wire eq  = (i_a == i_b);
    wire lt  = ($signed(i_a) < $signed(i_b));
    wire ltu = (i_a < i_b);

    reg cond;

    always @(*) begin
        case (i_funct3)
            F3_BEQ:  cond = eq;
            F3_BNE:  cond = ~eq;
            F3_BLT:  cond = lt;
            F3_BGE:  cond = ~lt;
            F3_BLTU: cond = ltu;
            F3_BGEU: cond = ~ltu;
            default: cond = 1'b0;
        endcase
    end

    assign o_taken = i_branch & cond;
endmodule
