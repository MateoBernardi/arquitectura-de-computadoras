`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
// 
// Create Date: 08.09.2026
// Design Name: 
// Module Name: uart_core
// Project Name: TP2
// Target Devices: 
// Tool Versions: 
// Description: baud_rate_gen + uart_rx + uart_tx + one rx fifo + one tx fifo.
//              The boundary (i_read_uart/i_write_uart/o_rx_empty/o_tx_full/
//              o_data_to_read/i_data_to_write) matches uart_interface's ports
//              directly, so no glue logic is needed between the two at the
//              top level. The tx fifo drains itself: o_tx_done pops it and
//              ~tx_empty feeds i_tx_ready, so queued bytes go out back to
//              back with no gap.
// 
// Dependencies: baud_rate_gen, uart_rx, uart_tx, fifo
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: o_rx_full added (rx fifo's full flag) -- not present
//              in the reference this was modeled on, see note in chat.
// 
//////////////////////////////////////////////////////////////////////////////////


module uart_core
#(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 19_200,
    parameter NB_DATA   = 8,
    parameter N_TICKS   = 16,
    parameter PTR_LEN   = 2
)
(
    input  wire i_clk,
    input  wire i_reset,

    // physical uart lines
    input  wire i_rx,
    output wire o_tx,

    // control/data side -- matches uart_interface's ports directly
    input  wire i_read_uart,
    input  wire i_write_uart,
    input  wire [NB_DATA-1:0] i_data_to_write,
    output wire o_tx_full,
    output wire o_rx_empty,
    output wire o_rx_full,
    output wire [NB_DATA-1:0] o_data_to_read
);

    wire tick;
    wire rx_done, tx_done;
    wire tx_empty, tx_not_empty;
    wire [NB_DATA-1:0] rx_data_out, tx_fifo_out;

    baud_rate_gen #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .N_TICKS  (N_TICKS)
    ) BAUD_GEN (
        .i_clk  (i_clk),
        .i_reset(i_reset),
        .o_tick (tick)
    );

    uart_rx #(
        .NB_DATA(NB_DATA),
        .N_TICKS(N_TICKS)
    ) RX (
        .i_clk    (i_clk),
        .i_reset  (i_reset),
        .i_rx     (i_rx),
        .i_tick   (tick),
        .o_rx_done(rx_done),
        .o_dout   (rx_data_out)
    );

    fifo #(
        .NB_DATA(NB_DATA),
        .PTR_LEN(PTR_LEN)
    ) RX_FIFO (
        .i_clk          (i_clk),
        .i_reset        (i_reset),
        .i_read_fifo    (i_read_uart),
        .i_write_fifo   (rx_done),
        .i_data_to_write(rx_data_out),
        .o_fifo_is_empty(o_rx_empty),
        .o_fifo_is_full (o_rx_full),
        .o_data_to_read (o_data_to_read)
    );

    fifo #(
        .NB_DATA(NB_DATA),
        .PTR_LEN(PTR_LEN)
    ) TX_FIFO (
        .i_clk          (i_clk),
        .i_reset        (i_reset),
        .i_read_fifo    (tx_done),
        .i_write_fifo   (i_write_uart),
        .i_data_to_write(i_data_to_write),
        .o_fifo_is_empty(tx_empty),
        .o_fifo_is_full (o_tx_full),
        .o_data_to_read (tx_fifo_out)
    );

    assign tx_not_empty = ~tx_empty;

    uart_tx #(
        .NB_DATA(NB_DATA),
        .N_TICKS(N_TICKS)
    ) TX (
        .i_clk     (i_clk),
        .i_reset   (i_reset),
        .i_tx_ready(tx_not_empty),
        .i_tick    (tick),
        .i_din     (tx_fifo_out),
        .o_tx_done (tx_done),
        .o_tx      (o_tx)
    );

endmodule