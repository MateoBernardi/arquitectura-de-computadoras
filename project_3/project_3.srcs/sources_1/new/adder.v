`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// adder: sumador generico sin carry de salida
//
// - Uso: PC + 4 en IF, PC + imm en ID/EX.
// -----------------------------------------------------------------------------
module adder #(
    parameter WIDTH = 32
) (
    input  wire [WIDTH-1:0] i_A,
    input  wire [WIDTH-1:0] i_B,
    output wire [WIDTH-1:0] o_result
);
    assign o_result = i_A + i_B;
endmodule
