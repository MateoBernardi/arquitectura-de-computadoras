`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
//
// Create Date: 28.09.2026
// Design Name:
// Module Name: uart_rx_regs
// Project Name: TP2
// Target Devices:
// Tool Versions:
// Description: uart_rx registers: FSM state, tick counter (s), bit counter (n)
//              and received byte. Synchronous active-high reset; the state
//              resets to 0 (IDLE in uart_rx_fsm).
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created (split out of uart_rx)
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module uart_rx_regs
#(
    parameter NB_DATA = 8,
    parameter N_TICKS = 16
)
(
    input  wire                       i_clk,
    input  wire                       i_reset,
    input  wire [1:0]                 i_state_next,
    input  wire [$clog2(N_TICKS)-1:0] i_s_next,
    input  wire [$clog2(NB_DATA)-1:0] i_n_next,
    input  wire [NB_DATA-1:0]         i_byte_next,
    output reg  [1:0]                 o_state,
    output reg  [$clog2(N_TICKS)-1:0] o_s,
    output reg  [$clog2(NB_DATA)-1:0] o_n,
    output reg  [NB_DATA-1:0]         o_byte
);

    always @(posedge i_clk) begin
        if (i_reset) begin
            o_state <= 2'b00;
            o_s     <= 0;
            o_n     <= 0;
            o_byte  <= 0;
        end
        else begin
            o_state <= i_state_next;
            o_s     <= i_s_next;
            o_n     <= i_n_next;
            o_byte  <= i_byte_next;
        end
    end

endmodule
