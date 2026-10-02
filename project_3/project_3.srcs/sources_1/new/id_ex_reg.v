`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// id_ex_reg: registro de pipeline ID/EX
//
// - Congela datos y control en un flanco. Los campos van agrupados en cuatro
//   latches (datos, campos de registros, control booleano, control de la ALU),
//   con el mismo empaquetado que las palabras del mapa de debug de cpu.v.
// - i_stall (unidad de riesgos): 1 congela el registro, igual que en if_id_reg.
//   PROVISORIO: todavia no hay unidad de riesgos, cpu.v deja i_stall en 0.
// - i_flush (branch tomado o JALR en EX): la instruccion que esta en ID en ese
//   flanco va por el camino equivocado; en el ciclo siguiente sale una burbuja.
//   La burbuja es exactamente "todo en 0": con reg_write / mem_write / jalr /
//   branch en 0 la ALU no escribe ningun registro ni redirige, y rd = rs1 =
//   rs2 = 0 no genera dependencias falsas para la unidad de riesgos.
// - El flush se aplica sobre las entradas, sin registrar: las salidas de ID ya
//   son combinacionales sobre IF/ID, que si esta registrado, asi que la
//   decision de EX de este ciclo corresponde a la instruccion de este flanco.
//   Un flush le gana al stall.
// - Reset: todo en 0, o sea burbuja.
// - JAL no viaja a EX: el salto se resuelve en ID.
// -----------------------------------------------------------------------------
module id_ex_reg (
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire        i_pipeline_enable,
    input  wire        i_stall,
    input  wire        i_flush,
    // ID
    input  wire [31:0] i_pc,
    input  wire [31:0] i_pc4,
    input  wire [31:0] i_rs1_data,
    input  wire [31:0] i_rs2_data,
    input  wire [31:0] i_imm,
    input  wire [4:0]  i_rs1,
    input  wire [4:0]  i_rs2,
    input  wire [4:0]  i_rd,
    input  wire [2:0]  i_funct3,
    input  wire [1:0]  i_alu_src_a,
    input  wire        i_alu_src_b,
    input  wire [3:0]  i_alu_op,
    input  wire [1:0]  i_result_src,
    input  wire        i_reg_write,
    input  wire        i_mem_read,
    input  wire        i_mem_write,
    input  wire        i_branch,
    input  wire        i_jalr,
    input  wire        i_halt,
    input  wire        i_illegal,
    // EX
    output wire [31:0] o_pc,
    output wire [31:0] o_pc4,
    output wire [31:0] o_rs1_data,
    output wire [31:0] o_rs2_data,
    output wire [31:0] o_imm,
    output wire [4:0]  o_rs1,
    output wire [4:0]  o_rs2,
    output wire [4:0]  o_rd,
    output wire [2:0]  o_funct3,
    output wire [1:0]  o_alu_src_a,
    output wire        o_alu_src_b,
    output wire [3:0]  o_alu_op,
    output wire [1:0]  o_result_src,
    output wire        o_reg_write,
    output wire        o_mem_read,
    output wire        o_mem_write,
    output wire        o_branch,
    output wire        o_jalr,
    output wire        o_halt,
    output wire        o_illegal
);
    localparam DATA_W = 160;  // pc, pc4, rs1_data, rs2_data, imm
    localparam FLD_W  = 17;   // rd, rs2, rs1, funct3 (5+5+5+3)
    localparam CTL_W  = 8;    // alu_src_b, illegal, halt, jalr, branch, mem_write, mem_read, reg_write
    localparam ALU_W  = 8;    // alu_op, alu_src_a, result_src

    wire enable = i_pipeline_enable & (~i_stall | i_flush);

    latch #(.WIDTH(DATA_W)) u_data (
        .i_clock (i_clock),
        .i_reset (i_reset),
        .i_enable(enable),
        .i_data (i_flush ? {DATA_W{1'b0}}
                          : {i_pc, i_pc4, i_rs1_data, i_rs2_data, i_imm}),
        .o_data ({o_pc, o_pc4, o_rs1_data, o_rs2_data, o_imm})
    );

    latch #(.WIDTH(FLD_W)) u_fields (
        .i_clock (i_clock),
        .i_reset (i_reset),
        .i_enable(enable),
        .i_data (i_flush ? {FLD_W{1'b0}}
                          : {i_rd, i_rs2, i_rs1, i_funct3}),
        .o_data ({o_rd, o_rs2, o_rs1, o_funct3})
    );

    latch #(.WIDTH(CTL_W)) u_ctrl (
        .i_clock (i_clock),
        .i_reset (i_reset),
        .i_enable(enable),
        .i_data (i_flush ? {CTL_W{1'b0}}
                          : {i_alu_src_b, i_illegal, i_halt, i_jalr, i_branch,
                             i_mem_write, i_mem_read, i_reg_write}),
        .o_data ({o_alu_src_b, o_illegal, o_halt, o_jalr, o_branch,
                  o_mem_write, o_mem_read, o_reg_write})
    );

    latch #(.WIDTH(ALU_W)) u_alu_ctrl (
        .i_clock (i_clock),
        .i_reset (i_reset),
        .i_enable(enable),
        .i_data (i_flush ? {ALU_W{1'b0}}
                          : {i_alu_op, i_alu_src_a, i_result_src}),
        .o_data ({o_alu_op, o_alu_src_a, o_result_src})
    );
endmodule