`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// control_unit: unidad de control RV32I (combinacional)
//
// Decodifica la instruccion completa en las senales de control de EX, MEM y WB,
// el formato del inmediato y los registros que realmente usa.
// - Instruccion ilegal (opcode, funct3 o funct7 invalidos, o ancho comprimido):
//   o_illegal = 1 y ninguna senal con efecto (se comporta como NOP).
// - rs1/rs2 salen en 0 si la instruccion no los lee y rd en 0 si no escribe;
//   escribir x0 no es escribir (o_reg_write = 0). Asi una burbuja (todo en 0)
//   no tiene efectos y los riesgos/forwarding no ven dependencias falsas.
// - funct3 solo viaja en branches (condicion) y loads/stores (tamano); 0 en el
//   resto.
// - FENCE se ejecuta como NOP; ECALL y EBREAK activan o_halt.
// -----------------------------------------------------------------------------
module control_unit (
    input  wire [31:0] i_instruction,
    output reg  [2:0]  o_imm_sel,
    output reg  [4:0]  o_rs1,
    output reg  [4:0]  o_rs2,
    output reg  [4:0]  o_rd,
    output reg  [2:0]  o_funct3,
    output reg  [1:0]  o_alu_src_a,
    output reg         o_alu_src_b,
    output reg  [3:0]  o_alu_op,
    output reg         o_reg_write,
    output reg  [1:0]  o_result_src,
    output reg         o_mem_read,
    output reg         o_mem_write,
    output reg         o_branch,
    output reg         o_jal,
    output reg         o_jalr,
    output reg         o_halt,
    output reg         o_illegal
);
    `include "riscv_defs.vh"

    wire [6:0] opcode = i_instruction[6:0];
    wire [4:0] rd     = i_instruction[11:7];
    wire [2:0] funct3 = i_instruction[14:12];
    wire [4:0] rs1    = i_instruction[19:15];
    wire [4:0] rs2    = i_instruction[24:20];
    wire [6:0] funct7 = i_instruction[31:25];

    reg writes_rd;
    reg reads_rs1;
    reg reads_rs2;

    always @(*) begin
        // Por defecto: nada con efecto
        o_imm_sel    = IMM_NONE;
        o_funct3     = 3'd0;
        o_alu_src_a  = ALU_A_RS1;
        o_alu_src_b  = ALU_B_RS2;
        o_alu_op     = ALU_ADD;
        o_result_src = RES_ALU;
        o_mem_read   = 1'b0;
        o_mem_write  = 1'b0;
        o_branch     = 1'b0;
        o_jal        = 1'b0;
        o_jalr       = 1'b0;
        o_halt       = 1'b0;
        o_illegal    = 1'b0;
        writes_rd    = 1'b0;
        reads_rs1    = 1'b0;
        reads_rs2    = 1'b0;

        case (opcode)
            OPC_LUI: begin                             // rd = imm
                o_imm_sel   = IMM_U;
                o_alu_src_a = ALU_A_ZERO;
                o_alu_src_b = ALU_B_IMM;
                writes_rd   = 1'b1;
            end

            OPC_AUIPC: begin                           // rd = pc + imm
                o_imm_sel   = IMM_U;
                o_alu_src_a = ALU_A_PC;
                o_alu_src_b = ALU_B_IMM;
                writes_rd   = 1'b1;
            end

            OPC_JAL: begin                             // rd = pc + 4; salto resuelto en ID
                o_imm_sel    = IMM_J;
                o_alu_src_a  = ALU_A_PC;
                o_alu_src_b  = ALU_B_IMM;
                o_result_src = RES_PC4;
                o_jal        = 1'b1;
                writes_rd    = 1'b1;
            end

            OPC_JALR: begin                            // rd = pc + 4; destino (rs1 + imm) & ~1 en EX
                if (funct3 == 3'b000) begin
                    o_imm_sel    = IMM_I;
                    o_alu_src_b  = ALU_B_IMM;
                    o_result_src = RES_PC4;
                    o_jalr       = 1'b1;
                    writes_rd    = 1'b1;
                    reads_rs1    = 1'b1;
                end
                else begin
                    o_illegal = 1'b1;
                end
            end

            OPC_BRANCH: begin                          // ALU: destino pc + imm; comparacion en EX con funct3
                if (funct3 != 3'b010 && funct3 != 3'b011) begin
                    o_imm_sel   = IMM_B;
                    o_funct3    = funct3;
                    o_alu_src_a = ALU_A_PC;
                    o_alu_src_b = ALU_B_IMM;
                    o_branch    = 1'b1;
                    reads_rs1   = 1'b1;
                    reads_rs2   = 1'b1;
                end
                else begin
                    o_illegal = 1'b1;
                end
            end

            OPC_LOAD: begin                            // rd = mem[rs1 + imm]
                if (funct3 == F3_B || funct3 == F3_H || funct3 == F3_W ||
                    funct3 == F3_BU || funct3 == F3_HU) begin
                    o_imm_sel    = IMM_I;
                    o_funct3     = funct3;
                    o_alu_src_b  = ALU_B_IMM;
                    o_result_src = RES_MEM;
                    o_mem_read   = 1'b1;
                    writes_rd    = 1'b1;
                    reads_rs1    = 1'b1;
                end
                else begin
                    o_illegal = 1'b1;
                end
            end

            OPC_STORE: begin                           // mem[rs1 + imm] = rs2
                if (funct3 == F3_B || funct3 == F3_H || funct3 == F3_W) begin
                    o_imm_sel   = IMM_S;
                    o_funct3    = funct3;
                    o_alu_src_b = ALU_B_IMM;
                    o_mem_write = 1'b1;
                    reads_rs1   = 1'b1;
                    reads_rs2   = 1'b1;
                end
                else begin
                    o_illegal = 1'b1;
                end
            end

            OPC_OP_IMM: begin                          // rd = rs1 op imm
                // SLLI: funct7 = 0000000. SRLI / SRAI: funct7 = 0000000 / 0100000
                if ((funct3 == 3'b001 && funct7 != 7'b0000000) ||
                    (funct3 == 3'b101 && funct7 != 7'b0000000 && funct7 != 7'b0100000)) begin
                    o_illegal = 1'b1;
                end
                else begin
                    o_imm_sel   = IMM_I;
                    o_alu_src_b = ALU_B_IMM;
                    o_alu_op    = {(funct3 == 3'b101) & i_instruction[30], funct3};
                    writes_rd   = 1'b1;
                    reads_rs1   = 1'b1;
                end
            end

            OPC_OP: begin                              // rd = rs1 op rs2
                // funct7 = 0000000, o 0100000 solo en SUB (000) y SRA (101)
                if (funct7 == 7'b0000000 ||
                    (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101))) begin
                    o_alu_op  = {i_instruction[30], funct3};
                    writes_rd = 1'b1;
                    reads_rs1 = 1'b1;
                    reads_rs2 = 1'b1;
                end
                else begin
                    o_illegal = 1'b1;
                end
            end

            OPC_FENCE: begin                           // un solo nucleo, sin caches: NOP
                if (funct3 == 3'b000)
                    o_alu_src_b = ALU_B_IMM;           // mismas salidas que addi x0, x0, 0
                else
                    o_illegal = 1'b1;
            end

            OPC_SYSTEM: begin                          // ECALL / EBREAK: fin del programa
                if (i_instruction == INSTR_ECALL || i_instruction == INSTR_EBREAK) begin
                    o_imm_sel = IMM_I;                 // imm = 0 (ecall) / 1 (ebreak)
                    o_halt    = 1'b1;
                end
                else begin
                    o_illegal = 1'b1;
                end
            end

            default: begin
                o_illegal = 1'b1;
            end
        endcase

        o_rd        = writes_rd ? rd  : 5'd0;
        o_reg_write = writes_rd & (rd != 5'd0);
        o_rs1       = reads_rs1 ? rs1 : 5'd0;
        o_rs2       = reads_rs2 ? rs2 : 5'd0;
    end
endmodule
