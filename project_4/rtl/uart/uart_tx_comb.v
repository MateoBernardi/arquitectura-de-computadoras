`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
//
// Create Date: 28.09.2026
// Design Name:
// Module Name: uart_tx_comb
// Project Name: TP2
// Target Devices:
// Tool Versions:
// Description: uart_tx combinational datapath: next values of the tick counter
//              (s), the bit counter (n), the send byte and the tx line, driven
//              by the control signals of uart_tx_fsm, plus the status flags
//              the FSM reads back.
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created (split out of uart_tx)
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module uart_tx_comb
#(
    parameter NB_DATA = 8,
    parameter N_TICKS = 16
)
(
    input  wire [NB_DATA-1:0]         i_din,
    input  wire [$clog2(N_TICKS)-1:0] i_s,
    input  wire [$clog2(NB_DATA)-1:0] i_n,
    input  wire [NB_DATA-1:0]         i_byte,
    input  wire                       i_s_clear,
    input  wire                       i_s_inc,
    input  wire                       i_n_clear,
    input  wire                       i_n_inc,
    input  wire                       i_load,
    input  wire                       i_shift,
    input  wire                       i_tx_data,
    input  wire                       i_tx_level,
    output wire [$clog2(N_TICKS)-1:0] o_s_next,
    output wire [$clog2(NB_DATA)-1:0] o_n_next,
    output wire [NB_DATA-1:0]         o_byte_next,
    output wire                       o_tx_next,
    output wire                       o_s_last,
    output wire                       o_n_last
);

    localparam NB_TICKCNT = $clog2(N_TICKS);
    localparam NB_BITCNT  = $clog2(NB_DATA);

    assign o_s_next    = i_s_clear ? {NB_TICKCNT{1'b0}} :
                         i_s_inc   ? i_s + 1'b1         : i_s;
    assign o_n_next    = i_n_clear ? {NB_BITCNT{1'b0}}  :
                         i_n_inc   ? i_n + 1'b1         : i_n;
    assign o_byte_next = i_load    ? i_din              :
                         i_shift   ? i_byte >> 1        : i_byte;
    assign o_tx_next   = i_tx_data ? i_byte[0]          : i_tx_level;

    assign o_s_last = (i_s == (N_TICKS-1));
    assign o_n_last = (i_n == (NB_DATA-1));

endmodule
