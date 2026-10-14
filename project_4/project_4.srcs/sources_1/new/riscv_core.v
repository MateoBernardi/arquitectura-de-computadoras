`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/12/2026 04:26:03 PM
// Design Name: 
// Module Name: riscv_core
// Project Name: 
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


// riscv_core.v - Complete single-cycle RV32I CPU
// Supports: R-type, I-type ALU, LW/LH/LB/LHU/LBU, SW/SH/SB,
//           BEQ/BNE/BLT/BGE/BLTU/BGEU, JAL, JALR, LUI, AUIPC
module riscv_core (
    input clk,
    input rst
);
    // ── 1. Program Counter ────────────────────────────────────────
    reg  [31:0] pc;
    wire [31:0] pc4 = pc + 4;

    // ── 2. Instruction Fetch ──────────────────────────────────────
    wire [31:0] inst;
    imem imem0 (.clk(clk), .addr(pc), .instr(inst),
                .wr_en(1'b0), .wr_addr(10'd0), .wr_data(8'd0));

    // ── 3. Instruction Decode ─────────────────────────────────────
    wire [6:0] opcode = inst[6:0];
    wire [4:0] rd     = inst[11:7];
    wire [2:0] funct3 = inst[14:12];
    wire [4:0] rs1    = inst[19:15];
    wire [4:0] rs2    = inst[24:20];
    wire [6:0] funct7 = inst[31:25];

    // ── 4. Control Unit ───────────────────────────────────────────
    wire       reg_write, alu_src, mem_read, mem_write, branch, jump;
    wire [1:0] wb_sel;
    wire [3:0] alu_op;
    wire [2:0] imm_sel;
    control ctrl (
        .opcode(opcode), .funct3(funct3), .funct7(funct7),
        .reg_write(reg_write), .alu_src(alu_src),
        .mem_read(mem_read), .mem_write(mem_write),
        .branch(branch), .jump(jump), .halt(),
        .wb_sel(wb_sel), .alu_op(alu_op), .imm_sel(imm_sel)
    );

    localparam OPC_JALR  = 7'b1100111;
    localparam OPC_AUIPC = 7'b0010111;
    wire is_jalr  = (opcode == OPC_JALR);
    wire is_auipc = (opcode == OPC_AUIPC);

    // ── 5. Register File ──────────────────────────────────────────
    wire [31:0] rdata1, rdata2;
    reg  [31:0] wr_data;
    regfile rf (
        .clk(clk), .rst(rst), .we(reg_write), .dbg_addr(5'd0), .dbg_data(),
        .waddr(rd), .wdata(wr_data),
        .raddr1(rs1), .rdata1(rdata1),
        .raddr2(rs2), .rdata2(rdata2)
    );

    // ── 6. Immediate Generator ────────────────────────────────────
    wire [31:0] imm;
    immgen ig (.instr(inst), .imm_sel(imm_sel), .imm(imm));

    // ── 7. ALU ────────────────────────────────────────────────────
    wire [31:0] alu_a = is_auipc ? pc : rdata1;
    wire [31:0] alu_b = alu_src  ? imm : rdata2;
    wire [31:0] alu_out;
    wire        alu_zero, alu_ovf, alu_lt, alu_ltu;
    alu_tp1 alu0 (
        .i_data_a(alu_a), .i_data_b(alu_b), .i_data_op(alu_op),
        .o_data(alu_out), .o_z(alu_zero), .o_o(alu_ovf),
        .o_lt(alu_lt), .o_ltu(alu_ltu)
    );

    // ── 8. Data Memory ────────────────────────────────────────────
    wire [31:0] dmem_rdata;
    dmem dmem0 (
        .clk(clk), .we(mem_write),
        .addr(alu_out), .wdata(rdata2),
        .funct3(funct3), .rdata(dmem_rdata),
        .dbg_addr(8'd0), .dbg_data()
    );

    // ── 9. Branch Unit ────────────────────────────────────────────
    wire        branch_taken;
    wire [31:0] branch_target;
    branch_unit bu (
        .funct3(funct3), .zero(alu_zero),
        .alu_lt(alu_lt), .alu_ltu(alu_ltu),
        .pc(pc), .b_imm(imm),
        .branch_taken(branch_taken),
        .branch_target(branch_target)
    );

    // ── 10. PC Mux ────────────────────────────────────────────────
    wire [31:0] jal_target  = pc + imm;
    wire [31:0] jalr_target = alu_out & ~32'h1;   // ALU computes rs1 + imm

    wire [31:0] pc_next =
        (branch & branch_taken) ? branch_target :
        (jump & is_jalr)        ? jalr_target   :
        jump                    ? jal_target    : pc4;

    always @(posedge clk or posedge rst)
        if (rst) pc <= 0; else pc <= pc_next;

    // ── 11. Write-Back Mux ────────────────────────────────────────
    always @(*) begin
        case (wb_sel)
            2'b00:   wr_data = alu_out;
            2'b01:   wr_data = dmem_rdata;
            2'b10:   wr_data = pc4;
            default: wr_data = imm;   // LUI
        endcase
    end

endmodule
