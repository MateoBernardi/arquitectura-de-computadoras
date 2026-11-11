`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// instruction_decode: etapa ID del pipeline RV32I (estructural)
//
// control_unit + imm_gen + register_file + sumador del destino de JAL.
// - Entradas: IF/ID (instruccion, PC, PC+4), escritura del banco de registros
//   desde WB, enable/reset globales y puerto de lectura de debug.
// - Hacia IF: JAL se resuelve aca (o_jal, o_jal_target = pc + imm).
// - Hacia ID/EX: datos, indices de registros, inmediato y senales de control.
//   o_rs1/o_rs2 salen en 0 si no se usan: la unidad de riesgos compara
//   directamente contra el rd de ID/EX.
// -----------------------------------------------------------------------------
module instruction_decode (
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire        i_enable,                       // enable global (debug unit)
    // IF/ID
    input  wire [31:0] i_instruction,
    input  wire [31:0] i_pc,
    input  wire [31:0] i_pc4,
    // WB: escritura del banco de registros
    input  wire        i_wb_reg_write,
    input  wire [4:0]  i_wb_rd,
    input  wire [31:0] i_wb_data,
    // debug: lectura del banco de registros
    input  wire [4:0]  i_dbg_reg_addr,
    output wire [31:0] o_dbg_reg_data,
    // hacia IF
    output wire        o_jal,
    output wire [31:0] o_jal_target,
    // hacia ID/EX
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
    output wire        o_reg_write,
    output wire [1:0]  o_result_src,
    output wire        o_mem_read,
    output wire        o_mem_write,
    output wire        o_branch,
    output wire        o_jalr,
    output wire        o_halt,
    output wire        o_illegal
);
    wire [2:0] imm_sel;

    control_unit u_control (
        .i_instruction(i_instruction),
        .o_imm_sel    (imm_sel),
        .o_rs1        (o_rs1),
        .o_rs2        (o_rs2),
        .o_rd         (o_rd),
        .o_funct3     (o_funct3),
        .o_alu_src_a  (o_alu_src_a),
        .o_alu_src_b  (o_alu_src_b),
        .o_alu_op     (o_alu_op),
        .o_reg_write  (o_reg_write),
        .o_result_src (o_result_src),
        .o_mem_read   (o_mem_read),
        .o_mem_write  (o_mem_write),
        .o_branch     (o_branch),
        .o_jal        (o_jal),
        .o_jalr       (o_jalr),
        .o_halt       (o_halt),
        .o_illegal    (o_illegal)
    );

    imm_gen u_imm_gen (
        .i_instruction(i_instruction),
        .i_imm_sel    (imm_sel),
        .o_imm        (o_imm)
    );

    register_file u_regs (
        .i_clock       (i_clock),
        .i_reset       (i_reset),
        .i_enable      (i_enable),
        .i_rs1         (o_rs1),
        .i_rs2         (o_rs2),
        .o_rs1_data    (o_rs1_data),
        .o_rs2_data    (o_rs2_data),
        .i_write_enable(i_wb_reg_write),
        .i_rd          (i_wb_rd),
        .i_write_data  (i_wb_data),
        .i_dbg_addr    (i_dbg_reg_addr),
        .o_dbg_data    (o_dbg_reg_data)
    );

    adder #(.WIDTH(32)) u_jal_adder (                  // destino de JAL
        .i_A     (i_pc),
        .i_B     (o_imm),
        .o_result(o_jal_target)
    );

    assign o_pc  = i_pc;
    assign o_pc4 = i_pc4;
endmodule
