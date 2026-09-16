`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineers: Mateo Bernardi, Pablo Castilla
//
// Module Name: registers
// Project Name: TP1
// Description:
//   Banco de registros extraido de top.v para poder testear por separado
//   la parte secuencial de la parte combinacional (alu_tp1).
//
//   - Registra i_data_a / i_data_b / i_data_op cuando se presiona el boton
//     correspondiente.
//   - Genera "op_loaded": un pulso registrado que se activa un ciclo
//     despues de presionar BTN_DATA_OP. En ese ciclo el resultado
//     combinacional de la ALU ya esta actualizado con el nuevo opcode,
//     asi que es el momento correcto para capturarlo.
//   - o_led / o_f_z / o_f_o son registros de salida: solo cambian cuando
//     op_loaded esta en alto, por lo que el display queda "congelado"
//     entre operaciones sin necesidad de una maquina de estados.
//   - i_reset es sincrono y activo en alto: limpia todos los registros
//     (operandos, opcode y salida) a 0.
//
// Revision:
// Revision 0.01 - File Created
//////////////////////////////////////////////////////////////////////////////////

module registers
#(
    parameter NB_DATA   = 8,
    parameter NB_OP     = 6,
    parameter NB_BUTTON = 3
)
(
    input wire i_clk,
    input wire i_reset,

    // botones/switches 
    input wire [NB_BUTTON-1:0] i_button,
    input wire [NB_DATA-1:0]   i_switch,

    // Salidas combinacionales de la ALU, para ser muestreadas aca
    input wire signed [NB_DATA-1:0] i_alu_result,
    input wire                      i_alu_z,
    input wire                      i_alu_o,

    // opcode registrados, van hacia la ALU
    output reg [NB_DATA-1:0] o_data_a,
    output reg [NB_DATA-1:0] o_data_b,
    output reg [NB_OP-1:0]   o_data_op,

    // Resultado/flags registrados, van hacia los LEDs
    output reg signed [NB_DATA-1:0] o_led,
    output reg                      o_f_z,
    output reg                      o_f_o
);

localparam BTN_DATA_A  = 3'b001;
localparam BTN_DATA_B  = 3'b010;
localparam BTN_DATA_OP = 3'b100;

// presionado BTN_DATA_OP (guarda la operac).
reg op_loaded;

// --- Carga de operandos / opcode ---
always @(posedge i_clk) begin
    if (i_reset) begin
        o_data_a  <= {NB_DATA{1'b0}};
        o_data_b  <= {NB_DATA{1'b0}};
        o_data_op <= {NB_OP{1'b0}};
        op_loaded <= 1'b0;
    end else begin
        case (i_button)
            BTN_DATA_A:  o_data_a  <= i_switch;
            BTN_DATA_B:  o_data_b  <= i_switch;
            BTN_DATA_OP: o_data_op <= i_switch[NB_OP-1:0];
            default: ; // mantiene el valor anterior
        endcase
        op_loaded <= (i_button == BTN_DATA_OP);
    end
end

// --- Captura del resultado, un ciclo despues de cargar el opcode ---
always @(posedge i_clk) begin
    if (i_reset) begin
        o_led <= {NB_DATA{1'b0}};
        o_f_z <= 1'b0;
        o_f_o <= 1'b0;
    end else if (op_loaded) begin
        o_led <= i_alu_result;
        o_f_z <= i_alu_z;
        o_f_o <= i_alu_o;
    end
end

endmodule