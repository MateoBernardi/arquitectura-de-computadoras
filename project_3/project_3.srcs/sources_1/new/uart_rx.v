`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
//
// Create Date: 07.09.2026
// Design Name:
// Module Name: uart_rx
// Project Name: TP2
// Target Devices:
// Tool Versions:
// Description: UART receiver, N_TICKS-oversampling, NB_DATA-bit frame (1 start
//              bit + 1 stop bit). Structural: wires uart_rx_fsm (state
//              machine), uart_rx_comb (combinational datapath) and
//              uart_rx_regs (registers).
//
// Dependencies: uart_rx_fsm, uart_rx_comb, uart_rx_regs
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - s/n widths and the mid-bit/full-bit thresholds now derive
//                 from N_TICKS/NB_DATA instead of being fixed at 16/8.
// Revision 0.03 - State machine, combinational logic and registers split into
//                 their own modules. Same ports and cycle-by-cycle behavior.
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module uart_rx
#(
    parameter NB_DATA = 8,
    parameter N_TICKS = 16
)
(
    input  wire i_clk,
    input  wire i_reset,
    input  wire i_rx,
    input  wire i_tick,
    output wire o_rx_done,
    output wire [NB_DATA-1:0] o_dout
);

    localparam NB_TICKCNT = $clog2(N_TICKS);
    localparam NB_BITCNT  = $clog2(NB_DATA);

    wire [1:0]            state, state_next;
    wire [NB_TICKCNT-1:0] s, s_next;
    wire [NB_BITCNT-1:0]  n, n_next;
    wire [NB_DATA-1:0]    received_byte, received_byte_next;
    wire                  s_clear, s_inc, n_clear, n_inc, shift;
    wire                  s_half, s_last, n_last;

    uart_rx_fsm FSM (
        .i_state     (state),
        .i_rx        (i_rx),
        .i_tick      (i_tick),
        .i_s_half    (s_half),
        .i_s_last    (s_last),
        .i_n_last    (n_last),
        .o_state_next(state_next),
        .o_s_clear   (s_clear),
        .o_s_inc     (s_inc),
        .o_n_clear   (n_clear),
        .o_n_inc     (n_inc),
        .o_shift     (shift),
        .o_rx_done   (o_rx_done)
    );

    uart_rx_comb #(
        .NB_DATA(NB_DATA),
        .N_TICKS(N_TICKS)
    ) COMB (
        .i_rx       (i_rx),
        .i_s        (s),
        .i_n        (n),
        .i_byte     (received_byte),
        .i_s_clear  (s_clear),
        .i_s_inc    (s_inc),
        .i_n_clear  (n_clear),
        .i_n_inc    (n_inc),
        .i_shift    (shift),
        .o_s_next   (s_next),
        .o_n_next   (n_next),
        .o_byte_next(received_byte_next),
        .o_s_half   (s_half),
        .o_s_last   (s_last),
        .o_n_last   (n_last)
    );

    uart_rx_regs #(
        .NB_DATA(NB_DATA),
        .N_TICKS(N_TICKS)
    ) REGS (
        .i_clk       (i_clk),
        .i_reset     (i_reset),
        .i_state_next(state_next),
        .i_s_next    (s_next),
        .i_n_next    (n_next),
        .i_byte_next (received_byte_next),
        .o_state     (state),
        .o_s         (s),
        .o_n         (n),
        .o_byte      (received_byte)
    );

    assign o_dout = received_byte;

endmodule
