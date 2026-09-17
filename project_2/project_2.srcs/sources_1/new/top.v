`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
// 
// Create Date: 08.09.2026
// Design Name: 
// Module Name: top
// Project Name: TP2
// Target Devices: Nexys4 DDR (Artix-7, XC7A100T-1CSG324C)
// Tool Versions: 
// Description: uart_core <-> uart_interface <-> alu_tp1. A 3-byte frame in on
//              i_rx (opcode, op_A, op_B) produces one result byte out on
//              o_tx. ALU flags (o_z/o_o) are computed but not relayed over
//              uart -- left unconnected here, see note in chat.
// 
// Dependencies: uart_core, uart_interface, alu_tp1
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module top
#(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 19_200,
    parameter NB_DATA   = 8,
    parameter NB_OPCODE = 6,
    parameter N_TICKS   = 16,
    parameter PTR_LEN   = 2
)
(
    input  wire i_clk,
    input  wire i_reset,
    input  wire i_rx,
    output wire o_tx
);

    wire fifo_rx_read, fifo_tx_write;
    wire fifo_rx_empty, fifo_tx_full, fifo_rx_full;
    wire [NB_DATA-1:0] data_to_read, data_to_write;
    wire [NB_DATA-1:0] alu_op_a, alu_op_b, alu_result;
    wire [NB_OPCODE-1:0] alu_opcode;
    wire alu_z, alu_o;

    uart_core #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .NB_DATA  (NB_DATA),
        .N_TICKS  (N_TICKS),
        .PTR_LEN  (PTR_LEN)
    ) UART (
        .i_clk          (i_clk),
        .i_reset        (i_reset),
        .i_rx           (i_rx),
        .o_tx           (o_tx),
        .i_read_uart    (fifo_rx_read),
        .i_write_uart   (fifo_tx_write),
        .i_data_to_write(data_to_write),
        .o_tx_full      (fifo_tx_full),
        .o_rx_empty     (fifo_rx_empty),
        .o_rx_full      (fifo_rx_full),
        .o_data_to_read (data_to_read)
    );

    uart_interface #(
        .NB_DATA  (NB_DATA),
        .NB_OPCODE(NB_OPCODE)
    ) IF (
        .i_clk          (i_clk),
        .i_reset        (i_reset),
        .i_alu_result   (alu_result),
        .i_data_to_read (data_to_read),
        .i_fifo_rx_empty(fifo_rx_empty),
        .i_fifo_tx_full (fifo_tx_full),
        .o_fifo_rx_read (fifo_rx_read),
        .o_fifo_tx_write(fifo_tx_write),
        .o_data_to_write(data_to_write),
        .o_alu_opcode   (alu_opcode),
        .o_alu_op_A     (alu_op_a),
        .o_alu_op_B     (alu_op_b)
    );

    alu_tp1 #(
        .NB_DATA(NB_DATA),
        .NB_OP  (NB_OPCODE)
    ) ALU (
        .i_data_a (alu_op_a),
        .i_data_b (alu_op_b),
        .i_data_op(alu_opcode),
        .o_data   (alu_result),
        .o_z      (alu_z),
        .o_o      (alu_o)
    );

endmodule