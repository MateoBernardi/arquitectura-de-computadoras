`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
//
// Create Date: 07.09.2026
// Design Name:
// Module Name: uart_tx
// Project Name: TP2
// Target Devices:
// Tool Versions:
// Description: UART transmitter, N_TICKS-oversampling, NB_DATA-bit frame (1
//              start bit + 1 stop bit). Structural: wires uart_tx_fsm (state
//              machine), uart_tx_comb (combinational datapath) and
//              uart_tx_regs (registers).
//
// Dependencies: uart_tx_fsm, uart_tx_comb, uart_tx_regs
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - s/n widths and the full-bit threshold now derive from
//                 N_TICKS/NB_DATA instead of being fixed at 16/8.
// Revision 0.03 - State machine, combinational logic and registers split into
//                 their own modules. Same ports and cycle-by-cycle behavior.
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module uart_tx
#(
    parameter NB_DATA = 8,
    parameter N_TICKS = 16
)
(
    input  wire i_clk,
    input  wire i_reset,
    input  wire i_tx_ready,
    input  wire i_tick,
    input  wire [NB_DATA-1:0] i_din,
    output wire o_tx_done,
    output wire o_tx
);

    localparam NB_TICKCNT = $clog2(N_TICKS);
    localparam NB_BITCNT  = $clog2(NB_DATA);

    wire [1:0]            state, state_next;
    wire [NB_TICKCNT-1:0] s, s_next;
    wire [NB_BITCNT-1:0]  n, n_next;
    wire [NB_DATA-1:0]    send_byte, send_byte_next;
    wire                  tx, tx_next;
    wire                  s_clear, s_inc, n_clear, n_inc, load, shift;
    wire                  tx_data, tx_level;
    wire                  s_last, n_last;

    uart_tx_fsm FSM (
        .i_state     (state),
        .i_tx_ready  (i_tx_ready),
        .i_tick      (i_tick),
        .i_s_last    (s_last),
        .i_n_last    (n_last),
        .o_state_next(state_next),
        .o_s_clear   (s_clear),
        .o_s_inc     (s_inc),
        .o_n_clear   (n_clear),
        .o_n_inc     (n_inc),
        .o_load      (load),
        .o_shift     (shift),
        .o_tx_data   (tx_data),
        .o_tx_level  (tx_level),
        .o_tx_done   (o_tx_done)
    );

    uart_tx_comb #(
        .NB_DATA(NB_DATA),
        .N_TICKS(N_TICKS)
    ) COMB (
        .i_din      (i_din),
        .i_s        (s),
        .i_n        (n),
        .i_byte     (send_byte),
        .i_s_clear  (s_clear),
        .i_s_inc    (s_inc),
        .i_n_clear  (n_clear),
        .i_n_inc    (n_inc),
        .i_load     (load),
        .i_shift    (shift),
        .i_tx_data  (tx_data),
        .i_tx_level (tx_level),
        .o_s_next   (s_next),
        .o_n_next   (n_next),
        .o_byte_next(send_byte_next),
        .o_tx_next  (tx_next),
        .o_s_last   (s_last),
        .o_n_last   (n_last)
    );

    uart_tx_regs #(
        .NB_DATA(NB_DATA),
        .N_TICKS(N_TICKS)
    ) REGS (
        .i_clk       (i_clk),
        .i_reset     (i_reset),
        .i_state_next(state_next),
        .i_s_next    (s_next),
        .i_n_next    (n_next),
        .i_byte_next (send_byte_next),
        .i_tx_next   (tx_next),
        .o_state     (state),
        .o_s         (s),
        .o_n         (n),
        .o_byte      (send_byte),
        .o_tx        (tx)
    );

    assign o_tx = tx;

endmodule
