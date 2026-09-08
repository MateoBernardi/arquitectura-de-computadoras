`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
// 
// Create Date: 07.09.2026
// Design Name: 
// Module Name: baud_rate_gen
// Project Name: TP2
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Moved MODULUS/NB_COUNTER out of the parameter port list
//                 (localparam there requires SystemVerilog, fails under
//                 plain Verilog-2001/2005). Added N_TICKS so the oversampling
//                 factor is a real parameter instead of a hardcoded 16.
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module baud_rate_gen
#(
    parameter CLK_FREQ  = 100_000_000, // Board clock: 100 MHz
    parameter BAUD_RATE = 19_200,      // UART baud rate
    parameter N_TICKS   = 16           // Oversampling ticks per bit
)
(
    input  wire i_clk,
    input  wire i_reset,
    output wire o_tick
);

    // Required ticks per second: N_TICKS * BAUD_RATE
    // Counter modulus = CLK_FREQ / (BAUD_RATE * N_TICKS)
    localparam MODULUS    = CLK_FREQ / (BAUD_RATE * N_TICKS);
    localparam NB_COUNTER = $clog2(MODULUS);

    reg [NB_COUNTER-1:0] counter_reg;

    always @(posedge i_clk) begin
        if (i_reset) begin
            counter_reg <= {NB_COUNTER{1'b0}};
        end else begin
            if (counter_reg == MODULUS - 1) begin
                counter_reg <= {NB_COUNTER{1'b0}};
            end else begin
                counter_reg <= counter_reg + 1'b1;
            end
        end
    end

    // Assert a single clock cycle pulse when reaching terminal count
    assign o_tick = (counter_reg == MODULUS - 1);

endmodule