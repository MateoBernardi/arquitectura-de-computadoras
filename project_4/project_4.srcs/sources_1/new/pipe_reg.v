`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Pipeline registers. All of them share the same conventions:
//  - rst : synchronous reset, empties the stage (NOP / bubble).
//  - en  : 0 = the CPU is paused by the debug unit; the register holds its value
//          (flush and stall are ignored while paused).
//  - halt travels with the instruction down to WB, where it stops the CPU.
//////////////////////////////////////////////////////////////////////////////////

module if_id_reg (
    input         clk, rst, en,
    input         stall,   // hold current value if stall=1
    input         flush,   // replace with NOP (wrong-path instruction)
    input  [31:0] if_pc, if_inst,
    output reg [31:0] id_pc, id_inst
);
    always @(posedge clk) begin
        if (rst) begin
            id_pc   <= 0;
            id_inst <= 32'h00000013; // NOP
        end else if (en) begin
            if (flush) begin
                id_pc   <= 0;
                id_inst <= 32'h00000013;
            end else if (!stall) begin
                id_pc   <= if_pc;
                id_inst <= if_inst;
            end
        end
    end
endmodule

module id_ex_reg (
    input        clk, rst, en, flush,
    // Control signals (names match control.v)
    input        id_reg_write, id_alu_src, id_mem_read, id_mem_write,
    input        id_branch, id_jump, id_is_jalr, id_is_auipc, id_halt,
    input [1:0]  id_wb_sel,
    input [3:0]  id_alu_op,
    // Data
    input [31:0] id_pc, id_pc4, id_rdata1, id_rdata2, id_imm,
    input [4:0]  id_rs1, id_rs2, id_rd,
    input [2:0]  id_funct3,
    // Outputs
    output reg        ex_reg_write, ex_alu_src, ex_mem_read, ex_mem_write,
    output reg        ex_branch, ex_jump, ex_is_jalr, ex_is_auipc, ex_halt,
    output reg [1:0]  ex_wb_sel,
    output reg [3:0]  ex_alu_op,
    output reg [31:0] ex_pc, ex_pc4, ex_rdata1, ex_rdata2, ex_imm,
    output reg [4:0]  ex_rs1, ex_rs2, ex_rd,
    output reg [2:0]  ex_funct3
);
    always @(posedge clk) begin
        if (rst || (en && flush)) begin
            // Insert NOP bubble
            ex_reg_write <= 0; ex_alu_src <= 0; ex_mem_read <= 0;
            ex_mem_write <= 0; ex_branch <= 0; ex_jump <= 0;
            ex_is_jalr <= 0; ex_is_auipc <= 0; ex_halt <= 0;
            ex_wb_sel <= 0; ex_alu_op <= 0;
            ex_pc <= 0; ex_pc4 <= 0; ex_rdata1 <= 0; ex_rdata2 <= 0; ex_imm <= 0;
            ex_rs1 <= 0; ex_rs2 <= 0; ex_rd <= 0; ex_funct3 <= 0;
        end else if (en) begin
            ex_reg_write <= id_reg_write; ex_alu_src   <= id_alu_src;
            ex_mem_read  <= id_mem_read;  ex_mem_write <= id_mem_write;
            ex_branch    <= id_branch;    ex_jump      <= id_jump;
            ex_is_jalr   <= id_is_jalr;   ex_is_auipc  <= id_is_auipc;
            ex_halt      <= id_halt;
            ex_wb_sel    <= id_wb_sel;    ex_alu_op    <= id_alu_op;
            ex_pc       <= id_pc;     ex_pc4    <= id_pc4;
            ex_rdata1   <= id_rdata1; ex_rdata2 <= id_rdata2; ex_imm <= id_imm;
            ex_rs1      <= id_rs1;    ex_rs2    <= id_rs2;
            ex_rd       <= id_rd;     ex_funct3 <= id_funct3;
        end
    end
endmodule

module ex_mem_reg (
    input        clk, rst, en,
    input        ex_reg_write, ex_mem_read, ex_mem_write, ex_halt,
    input [1:0]  ex_wb_sel,
    input [31:0] ex_alu_out, ex_rdata2, ex_pc4, ex_imm,
    input [4:0]  ex_rd,
    input [2:0]  ex_funct3,
    output reg        mem_reg_write, mem_mem_read, mem_mem_write, mem_halt,
    output reg [1:0]  mem_wb_sel,
    output reg [31:0] mem_alu_out, mem_rdata2, mem_pc4, mem_imm,
    output reg [4:0]  mem_rd,
    output reg [2:0]  mem_funct3
);
    always @(posedge clk) begin
        if (rst) begin
            mem_reg_write <= 0; mem_mem_read <= 0; mem_mem_write <= 0; mem_halt <= 0;
            mem_wb_sel <= 0;
            mem_alu_out <= 0; mem_rdata2 <= 0;
            mem_pc4 <= 0; mem_imm <= 0;
            mem_rd <= 0; mem_funct3 <= 0;
        end else if (en) begin
            mem_reg_write     <= ex_reg_write;
            mem_mem_read      <= ex_mem_read;
            mem_mem_write     <= ex_mem_write;
            mem_halt          <= ex_halt;
            mem_wb_sel        <= ex_wb_sel;
            mem_alu_out       <= ex_alu_out;
            mem_rdata2        <= ex_rdata2;
            mem_pc4           <= ex_pc4;
            mem_imm           <= ex_imm;
            mem_rd            <= ex_rd;
            mem_funct3        <= ex_funct3;
        end
    end
endmodule

module mem_wb_reg (
    input        clk, rst, en,
    input        mem_reg_write, mem_halt,
    input [31:0] mem_result,    // value to write back (already selected by wb_sel)
    input [4:0]  mem_rd,
    output reg        wb_reg_write, wb_halt,
    output reg [31:0] wb_result,
    output reg [4:0]  wb_rd
);
    always @(posedge clk) begin
        if (rst) begin
            wb_reg_write <= 0; wb_halt <= 0;
            wb_result <= 0; wb_rd <= 0;
        end else if (en) begin
            wb_reg_write <= mem_reg_write;
            wb_halt      <= mem_halt;
            wb_result    <= mem_result;
            wb_rd        <= mem_rd;
        end
    end
endmodule
