`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// execute: etapa EX del pipeline RV32I (combinacional)
//
// Recibe lo que quedo registrado en ID/EX y produce:
//   - el resultado de la ALU, con sus dos banderas (z, o),
//   - la redireccion del PC: branch tomado o JALR.
//
// Seleccion de operandos (la hace control_unit en ID):
//   A = rs1_data | pc | 0        (ALU_A_RS1 / ALU_A_PC / ALU_A_ZERO)
//   B = rs2_data | imm            (ALU_B_RS2 / ALU_B_IMM)
// El operando A se arma con un mux2 (rs1_data vs pc) mas el caso ALU_A_ZERO, que
// no tiene mux propio: los tres valores no entran en un solo mux2 y agregar uno
// de tres entradas aca no vale la pena.
//
// Destinos de salto:
//   branch = pc + imm
//   jalr   = (rs1_data + imm) & ~1
// Los dosadders son combinacionales y corren en paralelo con la ALU: los dos
// caminos criticos son el de la ALU y el del adder de destino, no la suma de
// los dos. El comparador de branches tambien corre en paralelo, asi que la
// decision de redirect sale en el mismo ciclo que la ALU.
//
// JAL no se resuelve aca: se resuelve en ID (control_unit levanta o_jal).
// -----------------------------------------------------------------------------
module execute (
    input  wire [31:0] i_pc,
    input  wire [31:0] i_rs1_data,
    input  wire [31:0] i_rs2_data,
    input  wire [31:0] i_imm,
    input  wire [2:0]  i_funct3,
    input  wire [1:0]  i_alu_src_a,
    input  wire        i_alu_src_b,
    input  wire [3:0]  i_alu_op,
    input  wire        i_branch,
    input  wire        i_jalr,
    // hacia IF (redireccion del PC)
    output wire        o_redirect,
    output wire [31:0] o_target,
    // hacia EX/MEM
    output wire [31:0] o_alu_result,
    output wire        o_alu_zero,
    output wire        o_alu_overflow,
    output wire        o_branch_taken,
    // debug
    output wire [31:0] o_alu_a,                            // operando A efectivo
    output wire [31:0] o_alu_b                             // operando B efectivo
);
    `include "riscv_defs.vh"

    // Operando A: ALU_A_RS1 -> rs1_data, ALU_A_PC -> pc, ALU_A_ZERO -> 0
    wire [31:0] alu_a_sel;
    mux2 #(.WIDTH(32)) u_mux_a (
        .i_A   (i_rs1_data),
        .i_B   (i_pc),
        .i_SEL (i_alu_src_a[0]),
        .o_data(alu_a_sel)
    );
    assign o_alu_a = (i_alu_src_a == ALU_A_ZERO) ? 32'd0 : alu_a_sel;

    // Operando B
    mux2 #(.WIDTH(32)) u_mux_b (
        .i_A   (i_rs2_data),
        .i_B   (i_imm),
        .i_SEL (i_alu_src_b),
        .o_data(o_alu_b)
    );

    alu_tp1 #(
        .NB_DATA(32),
        .NB_OP  (4)
    ) u_alu (
        .i_data_a (o_alu_a),
        .i_data_b (o_alu_b),
        .i_data_op(i_alu_op),
        .o_data   (o_alu_result),
        .o_z      (o_alu_zero),
        .o_o      (o_alu_overflow)
    );

    // Destino de los branches: pc + imm
    wire [31:0] branch_target;
    adder #(.WIDTH(32)) u_branch_target (
        .i_A     (i_pc),
        .i_B     (i_imm),
        .o_result(branch_target)
    );

    // Destino de JALR: (rs1_data + imm) con el bit 0 en 0
    wire [31:0] jalr_sum;
    adder #(.WIDTH(32)) u_jalr_target (
        .i_A     (i_rs1_data),
        .i_B     (i_imm),
        .o_result(jalr_sum)
    );
    wire [31:0] jalr_target = {jalr_sum[31:1], 1'b0};

    branch_cmp u_cmp (
        .i_a     (i_rs1_data),
        .i_b     (i_rs2_data),
        .i_funct3(i_funct3),
        .i_branch(i_branch),
        .o_taken (o_branch_taken)
    );

    assign o_redirect = o_branch_taken | i_jalr;

    mux2 #(.WIDTH(32)) u_mux_target (
        .i_A   (branch_target),
        .i_B   (jalr_target),
        .i_SEL (i_jalr),
        .o_data(o_target)
    );
endmodule