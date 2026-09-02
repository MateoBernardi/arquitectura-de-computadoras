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
    output reg signed [NB_DATA-1: 0] led,
    output reg f_o,
    output reg f_z
);

localparam BTN_DATA_A = 3'b001;
localparam BTN_DATA_B = 3'b010;
localparam BTN_DATA_OP = 3'b100;

reg [NB_DATA-1:0] alu_data_a;
reg [NB_DATA-1:0] alu_data_b;
reg [NB_OP-1:0] alu_data_op;

wire signed [NB_DATA-1:0] alu_out_data;
wire                      alu_out_z;
wire                      alu_out_o;

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
    .o_data(alu_out_data),
    .o_z(alu_out_z),
    .o_o(alu_out_o)
);

reg op_loaded;

always@(posedge i_clk) begin:inputs
    case(button)
    BTN_DATA_A: alu_data_a <= switch;
    BTN_DATA_B: alu_data_b <= switch;
    BTN_DATA_OP: alu_data_op <= switch [NB_OP-1:0];
    endcase
    op_loaded <= (button == BTN_DATA_OP);   // <-- esto falta
end

always@(posedge i_clk) begin: outputs
    if (op_loaded) begin
        led <= alu_out_data;
        f_z <= alu_out_z;
        f_o <= alu_out_o;
    end
end

endmodule
