`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// instruction_fetch: etapa IF del pipeline RV32I
//
// - Proximo PC, de menor a mayor prioridad: PC+4 -> JAL (ID) -> redirect de EX.
//   EX le gana a ID porque es la instruccion mas vieja: con un branch tomado o
//   un JALR en EX, lo que esta en ID es camino equivocado.
// - instru_mem lee en forma sincronica: o_imem_data es la instruccion de o_pc
//   un ciclo despues, y ya esta registrada (es el campo instruccion de IF/ID).
//   o_pc y o_pc4 son los valores actuales, sin registrar: if_id_reg los guarda
//   en el mismo flanco en que la memoria lee.
// - i_pc_stall (unidad de riesgos) congela el PC y la lectura de la memoria.
//   Un redirect de EX anula el stall para el PC: la instruccion stalleada es
//   camino equivocado.
// - i_pc_enable (debug unit) congela toda la etapa sin excepciones.
// -----------------------------------------------------------------------------
module instruction_fetch #(
    parameter        IMEM_ADDR_W    = 8,               // bits de direccion en bytes de instru_mem
    parameter        IMEM_INIT_FILE = "",              // hex opcional, una palabra por linea
    parameter [31:0] RESET_VECTOR   = 32'h0000_0000
) (
    input  wire                   i_clock,
    input  wire                   i_pc_reset,
    input  wire                   i_pc_enable,         // debug unit
    input  wire                   i_pc_stall,          // unidad de riesgos
    input  wire                   i_j_jal,             // JAL detectado en ID
    input  wire [31:0]            i_jump_addr,         // destino de JAL (PC + imm), desde ID
    input  wire                   i_ex_redirect,       // branch tomado o JALR en EX
    input  wire [31:0]            i_ex_target,         // destino desde EX
    input  wire                   i_instru_mem_enable, // en 1 mientras corre: en 0 congela la memoria pero no el PC
    input  wire                   i_write_enable,      // puerto de escritura de la debug unit
    input  wire [IMEM_ADDR_W-1:0] i_write_addr,
    input  wire [7:0]             i_write_data,
    output wire [31:0]            o_imem_data,         // instruccion leida (registrada en la BRAM)
    output wire [31:0]            o_pc,                // PC actual (direccion que se esta leyendo)
    output wire [31:0]            o_pc4                // PC actual + 4
);
    wire [31:0] mux_jal_out;
    wire [31:0] next_pc;

    wire stall_ef = i_pc_stall & ~i_ex_redirect;       // stall efectivo del PC
    wire read_en  = i_pc_enable & ~i_pc_stall;         // lectura de memoria (igual que el load de if_id_reg)

    // Proximo PC
    adder #(.WIDTH(32)) u_adder (
        .i_A     (o_pc),
        .i_B     (32'd4),
        .o_result(o_pc4)
    );

    mux2 #(.WIDTH(32)) u_mux_jal (
        .i_A   (o_pc4),
        .i_B   (i_jump_addr),
        .i_SEL (i_j_jal),
        .o_data(mux_jal_out)
    );

    mux2 #(.WIDTH(32)) u_mux_ex (
        .i_A   (mux_jal_out),
        .i_B   (i_ex_target),
        .i_SEL (i_ex_redirect),
        .o_data(next_pc)
    );

    program_counter #(.RESET_VECTOR(RESET_VECTOR)) u_pc (
        .i_clock   (i_clock),
        .i_reset   (i_pc_reset),
        .i_enable  (i_pc_enable),
        .i_pc_stall(stall_ef),
        .i_mux_pc  (next_pc),
        .o_pc      (o_pc)
    );

    // Memoria de instrucciones
    instru_mem #(
        .ADDR_W   (IMEM_ADDR_W),
        .INIT_FILE(IMEM_INIT_FILE)
    ) u_instru_mem (
        .i_clock       (i_clock),
        .i_enable      (i_instru_mem_enable),
        .i_read_enable (read_en),
        .i_read_addr   (o_pc),
        .o_read_data   (o_imem_data),
        .i_write_enable(i_write_enable),
        .i_write_addr  (i_write_addr),
        .i_write_data  (i_write_data)
    );
endmodule
