`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// mux2: multiplexor generico 2 a 1
//
// - i_SEL = 0 -> i_A ; i_SEL = 1 -> i_B
// -----------------------------------------------------------------------------
module mux2 #(
    parameter WIDTH = 32
) (
    input  wire [WIDTH-1:0] i_A,
    input  wire [WIDTH-1:0] i_B,
    input  wire             i_SEL,
    output wire [WIDTH-1:0] o_data
);
    assign o_data = i_SEL ? i_B : i_A;
endmodule
