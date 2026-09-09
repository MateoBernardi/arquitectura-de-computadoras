`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineers: Mateo Bernardi, Pablo Castilla
// 
// Create Date: 08/29/2026 10:23:43 AM
// Design Name: 
// Module Name: top
// Project Name: TP1
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Added reset input; input/output registers moved to the
//                 new "registers" module; the LEDs and flags now only
//                 update one cycle after BTN_DATA_OP is pressed.
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module top
#(
    parameter NB_DATA = 8,
    parameter NB_BITS = 8,
    parameter NB_OP = 6,
    parameter NB_BUTTON = 3
)
(
    input wire [NB_BITS-1:0] switch,
    input wire [NB_BUTTON-1:0] button,
    input wire i_clk,
    input wire i_reset,
    output signed [NB_DATA-1: 0] led,
    output f_o,
    output f_z
);

// Operandos/opcode registrados (salida del banco de registros, entrada de la ALU)
wire [NB_DATA-1:0] alu_data_a;
wire [NB_DATA-1:0] alu_data_b;
wire [NB_OP-1:0]   alu_data_op;

// Salida combinacional de la ALU (entrada del banco de registros)
wire signed [NB_DATA-1:0] alu_result;
wire alu_z;
wire alu_o;

registers
#(
    .NB_DATA(NB_DATA),
    .NB_OP(NB_OP),
    .NB_BUTTON(NB_BUTTON)
)
u_registers
(
    .i_clk(i_clk),
    .i_reset(i_reset),
    .i_button(button),
    .i_switch(switch),
    .i_alu_result(alu_result),
    .i_alu_z(alu_z),
    .i_alu_o(alu_o),
    .o_data_a(alu_data_a),
    .o_data_b(alu_data_b),
    .o_data_op(alu_data_op),
    .o_led(led),
    .o_f_z(f_z),
    .o_f_o(f_o)
);

alu_tp1 
#(
    .NB_DATA(NB_DATA),
    .NB_OP(NB_OP)
)
u_alu
(
    .i_data_a(alu_data_a),
    .i_data_b(alu_data_b),
    .i_data_op(alu_data_op),
    .o_data(alu_result),
    .o_z(alu_z),
    .o_o(alu_o)
);

endmodule