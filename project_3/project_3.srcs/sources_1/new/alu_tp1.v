`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
// 
// Create Date: 08/29/2026 10:50:54 AM
// Design Name: 
// Module Name: alu_tp1
// Project Name: TP1
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Adaptada a RV32I (TP final): 32 bits, codigos de 4 bits
//                 {instr[30], funct3}, agrega SLL / SLT / SLTU y usa solo los
//                 bits bajos de i_data_b como cantidad de shift.
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module alu_tp1
#(
    parameter NB_DATA = 32,
    parameter NB_OP = 4
)
(
    input signed [NB_DATA-1:0] i_data_a,
    input signed [NB_DATA-1:0] i_data_b,
    input [NB_OP-1:0] i_data_op,
    output signed [NB_DATA-1:0] o_data,
    output reg o_z,
    output reg o_o   
);

`include "alu_ops.vh"


localparam NB_SH = $clog2(NB_DATA);

reg [NB_DATA-1 : 0] alu_result;
reg [NB_DATA:0] tmp;

// RV32I: en los shifts solo cuentan los 5 bits bajos de b. Sin esto, SRAI
// (imm[11:5] = 0100000) y los shifts por registro con rs2 > 31 dan mal.
wire [NB_SH-1:0] shamt = i_data_b[NB_SH-1:0];

always@(*) begin
    o_o   = 1'b0;
    o_z       = 1'b0;
    alu_result = {NB_DATA{1'b0}};
    case (i_data_op)
        OP_ADD: begin //ADD
                tmp          = i_data_a + i_data_b;
                alu_result = tmp[NB_DATA-1:0];
                o_o   = (i_data_a[NB_DATA-1] == i_data_b[NB_DATA-1]) &&
                               (alu_result[NB_DATA-1] != i_data_a[NB_DATA-1]);
            end

        OP_SUB: 
            begin // SUB
                tmp          = i_data_a - i_data_b;
                alu_result = tmp[NB_DATA-1:0];
                o_o   = (i_data_a[NB_DATA-1] != i_data_b[NB_DATA-1]) &&
                               (alu_result[NB_DATA-1] != i_data_a[NB_DATA-1]);
            end
        OP_AND: alu_result = i_data_a & i_data_b; //AND
        OP_OR: alu_result = i_data_a | i_data_b; //OR
        OP_XOR: alu_result = i_data_a ^ i_data_b; //XOR
        OP_SRA: alu_result = i_data_a >>> shamt; //SRA
        OP_SRL: alu_result = i_data_a >> shamt; //SRL
        OP_NOR: alu_result = ~(i_data_a | i_data_b);//A NOR B
        OP_SLL: alu_result = i_data_a << shamt; //SLL
        OP_SLT: alu_result = {{(NB_DATA-1){1'b0}}, (i_data_a < i_data_b)}; //SLT (con signo)
        OP_SLTU: alu_result = {{(NB_DATA-1){1'b0}}, ($unsigned(i_data_a) < $unsigned(i_data_b))}; //SLTU
        
        default: alu_result =  {NB_DATA{1'b0}};
    endcase
    
    o_z = (alu_result == {NB_DATA{1'b0}});
end

assign o_data = alu_result;

endmodule
