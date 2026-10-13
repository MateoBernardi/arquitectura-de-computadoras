`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 04:04:24 PM
// Design Name: 
// Module Name: pipe_reg
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

// pipe_reg.v - The four inter-stage pipeline registers
// for a 5-stage RISC-V pipeline

// ── IF/ID Pipeline Register ───────────────────────────────────────
module if_id_reg (
    input         clk, rst,
    input         stall,   // hold current value if stall=1
    input  [31:0] if_pc, if_inst,
    output reg [31:0] id_pc, id_inst
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            id_pc   <= 0;
            id_inst <= 32'h00000013; // NOP
        end else if (!stall) begin
            id_pc   <= if_pc;
            id_inst <= if_inst;
        end
    end
endmodule

// ── ID/EX Pipeline Register ───────────────────────────────────────
module id_ex_reg (
    input        clk, rst, flush,
    // Control signals (names match control.v / riscv_core.v)
    input        id_reg_write, id_alu_src, id_mem_read, id_mem_write,
    input        id_branch, id_jump, id_is_jalr, id_is_auipc,
    input [1:0]  id_wb_sel,
    input [3:0]  id_alu_op,
    // Data
    input [31:0] id_pc, id_pc4, id_rdata1, id_rdata2, id_imm,
    input [4:0]  id_rs1, id_rs2, id_rd,
    input [2:0]  id_funct3,
    // Outputs
    output reg        ex_reg_write, ex_alu_src, ex_mem_read, ex_mem_write,
    output reg        ex_branch, ex_jump, ex_is_jalr, ex_is_auipc,
    output reg [1:0]  ex_wb_sel,
    output reg [3:0]  ex_alu_op,
    output reg [31:0] ex_pc, ex_pc4, ex_rdata1, ex_rdata2, ex_imm,
    output reg [4:0]  ex_rs1, ex_rs2, ex_rd,
    output reg [2:0]  ex_funct3
);
    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            // Insert NOP bubble
            ex_reg_write <= 0; ex_alu_src <= 0; ex_mem_read <= 0;
            ex_mem_write <= 0; ex_branch <= 0; ex_jump <= 0;
            ex_is_jalr <= 0; ex_is_auipc <= 0;
            ex_wb_sel <= 0; ex_alu_op <= 0;
            ex_pc <= 0; ex_pc4 <= 0; ex_rdata1 <= 0; ex_rdata2 <= 0; ex_imm <= 0;
            ex_rs1 <= 0; ex_rs2 <= 0; ex_rd <= 0; ex_funct3 <= 0;
        end else begin
            ex_reg_write <= id_reg_write; ex_alu_src   <= id_alu_src;
            ex_mem_read  <= id_mem_read;  ex_mem_write <= id_mem_write;
            ex_branch    <= id_branch;    ex_jump      <= id_jump;
            ex_is_jalr   <= id_is_jalr;   ex_is_auipc  <= id_is_auipc;
            ex_wb_sel    <= id_wb_sel;    ex_alu_op    <= id_alu_op;
            ex_pc       <= id_pc;     ex_pc4    <= id_pc4;
            ex_rdata1   <= id_rdata1; ex_rdata2 <= id_rdata2; ex_imm <= id_imm;
            ex_rs1      <= id_rs1;    ex_rs2    <= id_rs2;
            ex_rd       <= id_rd;     ex_funct3 <= id_funct3;
        end
    end
endmodule

// ── EX/MEM Pipeline Register ──────────────────────────────────────
module ex_mem_reg (
    input        clk, rst,
    input        ex_reg_write, ex_mem_read, ex_mem_write,
    input        ex_branch, ex_branch_taken,
    input [1:0]  ex_wb_sel,
    input [31:0] ex_alu_out, ex_rdata2, ex_branch_target, ex_pc4, ex_imm,
    input [4:0]  ex_rd,
    input [2:0]  ex_funct3,
    output reg        mem_reg_write, mem_mem_read, mem_mem_write,
    output reg        mem_branch, mem_branch_taken,
    output reg [1:0]  mem_wb_sel,
    output reg [31:0] mem_alu_out, mem_rdata2, mem_branch_target, mem_pc4, mem_imm,
    output reg [4:0]  mem_rd,
    output reg [2:0]  mem_funct3
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_reg_write <= 0; mem_mem_read <= 0; mem_mem_write <= 0;
            mem_wb_sel <= 0; mem_branch <= 0; mem_branch_taken <= 0;
            mem_alu_out <= 0; mem_rdata2 <= 0; mem_branch_target <= 0;
            mem_pc4 <= 0; mem_imm <= 0;
            mem_rd <= 0; mem_funct3 <= 0;
        end else begin
            mem_reg_write     <= ex_reg_write;
            mem_mem_read      <= ex_mem_read;
            mem_mem_write     <= ex_mem_write;
            mem_wb_sel        <= ex_wb_sel;
            mem_branch        <= ex_branch;
            mem_branch_taken  <= ex_branch_taken;
            mem_alu_out       <= ex_alu_out;
            mem_rdata2        <= ex_rdata2;
            mem_branch_target <= ex_branch_target;
            mem_pc4           <= ex_pc4;
            mem_imm           <= ex_imm;
            mem_rd            <= ex_rd;
            mem_funct3        <= ex_funct3;
        end
    end
endmodule

// ── MEM/WB Pipeline Register ──────────────────────────────────────
module mem_wb_reg (
    input        clk, rst,
    input        mem_reg_write,
    input [1:0]  mem_wb_sel,
    input [31:0] mem_alu_out, mem_dmem_rdata, mem_pc4, mem_imm,
    input [4:0]  mem_rd,
    output reg        wb_reg_write,
    output reg [1:0]  wb_wb_sel,
    output reg [31:0] wb_alu_out, wb_dmem_rdata, wb_pc4, wb_imm,
    output reg [4:0]  wb_rd
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_reg_write <= 0; wb_wb_sel <= 0;
            wb_alu_out <= 0; wb_dmem_rdata <= 0;
            wb_pc4 <= 0; wb_imm <= 0; wb_rd <= 0;
        end else begin
            wb_reg_write  <= mem_reg_write;
            wb_wb_sel     <= mem_wb_sel;
            wb_alu_out    <= mem_alu_out;
            wb_dmem_rdata <= mem_dmem_rdata;
            wb_pc4        <= mem_pc4;
            wb_imm        <= mem_imm;
            wb_rd         <= mem_rd;
        end
    end
endmodule
