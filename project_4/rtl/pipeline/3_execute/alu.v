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
// Revision 0.03 - Elimina tmp (latch potencial; el bit extra no se usaba):
//                 ADD y SUB escriben directo en alu_result.
// Revision 0.04 - Codigos de operacion definidos en alu_ops.vh segun el
//                 modulo de control (ADD 0000, SUB 0001, AND 0010, OR 0011,
//                 XOR 0100, SLT 0101, SLTU 0110, SLL 0111, SRL 1000,
//                 SRA 1001, NOR 1010); ya no son {instr[30], funct3}.
// Revision 0.05 - Agrega o_lt (a < b con signo) y o_ltu (a < b sin signo),
//                 calculadas siempre, sin depender de i_data_op, para
//                 branch_unit (BLT/BGE/BLTU/BGEU). SLT y SLTU las reutilizan.
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
    output reg o_o,
    output wire o_lt,                                  // a < b con signo
    output wire o_ltu                                  // a < b sin signo
);

`include "alu_ops.vh"


localparam NB_SH = $clog2(NB_DATA);

reg [NB_DATA-1 : 0] alu_result;

// RV32I: en los shifts solo cuentan los 5 bits bajos de b. Sin esto, SRAI
// (imm[11:5] = 0100000) y los shifts por registro con rs2 > 31 dan mal.
wire [NB_SH-1:0] shamt = i_data_b[NB_SH-1:0];

// Comparaciones para branch_unit: no dependen de i_data_op.
assign o_lt  = (i_data_a < i_data_b);                          // puertos signed
assign o_ltu = ($unsigned(i_data_a) < $unsigned(i_data_b));

always@(*) begin
    o_o        = 1'b0;
    o_z        = 1'b0;
    alu_result = {NB_DATA{1'b0}};
    case (i_data_op)
        OP_ADD: begin //ADD
                alu_result = i_data_a + i_data_b;
                o_o        = (i_data_a[NB_DATA-1] == i_data_b[NB_DATA-1]) &&
                             (alu_result[NB_DATA-1] != i_data_a[NB_DATA-1]);
            end

        OP_SUB: begin // SUB
                alu_result = i_data_a - i_data_b;
                o_o        = (i_data_a[NB_DATA-1] != i_data_b[NB_DATA-1]) &&
                             (alu_result[NB_DATA-1] != i_data_a[NB_DATA-1]);
            end
        OP_AND: alu_result = i_data_a & i_data_b; //AND
        OP_OR: alu_result = i_data_a | i_data_b; //OR
        OP_XOR: alu_result = i_data_a ^ i_data_b; //XOR
        OP_SRA: alu_result = i_data_a >>> shamt; //SRA
        OP_SRL: alu_result = i_data_a >> shamt; //SRL
        OP_NOR: alu_result = ~(i_data_a | i_data_b);//A NOR B
        OP_SLL: alu_result = i_data_a << shamt; //SLL
        OP_SLT: alu_result = {{(NB_DATA-1){1'b0}}, o_lt}; //SLT (con signo)
        OP_SLTU: alu_result = {{(NB_DATA-1){1'b0}}, o_ltu}; //SLTU
        
        default: alu_result =  {NB_DATA{1'b0}};
    endcase
    
    o_z = (alu_result == {NB_DATA{1'b0}});
end

assign o_data = alu_result;

endmodule