`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
//
// Create Date: 28.09.2026
// Design Name:
// Module Name: uart_rx_comb
// Project Name: TP2
// Target Devices:
// Tool Versions:
// Description: uart_rx combinational datapath: next values of the tick counter
//              (s), the bit counter (n) and the received byte, driven by the
//              control signals of uart_rx_fsm, plus the status flags the FSM
//              reads back.
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created (split out of uart_rx)
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module uart_rx_comb
#(
    parameter NB_DATA = 8,
    parameter N_TICKS = 16
)
(
    input  wire                       i_rx,
    input  wire [$clog2(N_TICKS)-1:0] i_s,
    input  wire [$clog2(NB_DATA)-1:0] i_n,
    input  wire [NB_DATA-1:0]         i_byte,
    input  wire                       i_s_clear,
    input  wire                       i_s_inc,
    input  wire                       i_n_clear,
    input  wire                       i_n_inc,
    input  wire                       i_shift,
    output wire [$clog2(N_TICKS)-1:0] o_s_next,
    output wire [$clog2(NB_DATA)-1:0] o_n_next,
    output wire [NB_DATA-1:0]         o_byte_next,
    output wire                       o_s_half,
    output wire                       o_s_last,
    output wire                       o_n_last
);

    localparam NB_TICKCNT = $clog2(N_TICKS);
    localparam NB_BITCNT  = $clog2(NB_DATA);
    localparam HALF_TICK  = (N_TICKS / 2) - 1; // mid-bit sample point for the start bit

    assign o_s_next    = i_s_clear ? {NB_TICKCNT{1'b0}} :
                         i_s_inc   ? i_s + 1'b1         : i_s;
    assign o_n_next    = i_n_clear ? {NB_BITCNT{1'b0}}  :
                         i_n_inc   ? i_n + 1'b1         : i_n;
    assign o_byte_next = i_shift   ? {i_rx, i_byte[NB_DATA-1:1]} : i_byte;

    assign o_s_half = (i_s == HALF_TICK);
    assign o_s_last = (i_s == (N_TICKS-1));
    assign o_n_last = (i_n == (NB_DATA-1));

endmodule
