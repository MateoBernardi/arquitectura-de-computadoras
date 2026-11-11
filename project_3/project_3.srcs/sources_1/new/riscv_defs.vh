// -----------------------------------------------------------------------------
// riscv_defs.vh: constantes del ISA RV32I y codificaciones internas del pipeline
//
// Se incluye DENTRO de cada modulo que lo usa:
//     `include "riscv_defs.vh"
// Sin include guard: cada modulo necesita su propia copia de los localparam.
// -----------------------------------------------------------------------------

// Opcodes (instr[6:0])
localparam [6:0] OPC_LUI    = 7'b0110111;
localparam [6:0] OPC_AUIPC  = 7'b0010111;
localparam [6:0] OPC_JAL    = 7'b1101111;
localparam [6:0] OPC_JALR   = 7'b1100111;
localparam [6:0] OPC_BRANCH = 7'b1100011;
localparam [6:0] OPC_LOAD   = 7'b0000011;
localparam [6:0] OPC_STORE  = 7'b0100011;
localparam [6:0] OPC_OP_IMM = 7'b0010011;
localparam [6:0] OPC_OP     = 7'b0110011;
localparam [6:0] OPC_FENCE  = 7'b0001111;
localparam [6:0] OPC_SYSTEM = 7'b1110011;

// Instrucciones fijas
localparam [31:0] INSTR_NOP    = 32'h0000_0013;       // addi x0, x0, 0
localparam [31:0] INSTR_ECALL  = 32'h0000_0073;
localparam [31:0] INSTR_EBREAK = 32'h0010_0073;

// Formato del inmediato (control_unit -> imm_gen)
localparam [2:0] IMM_NONE = 3'd0;                     // sin inmediato: 0
localparam [2:0] IMM_I    = 3'd1;
localparam [2:0] IMM_S    = 3'd2;
localparam [2:0] IMM_B    = 3'd3;
localparam [2:0] IMM_U    = 3'd4;
localparam [2:0] IMM_J    = 3'd5;

// Operando A de la ALU (EX)
localparam [1:0] ALU_A_RS1  = 2'd0;
localparam [1:0] ALU_A_PC   = 2'd1;                   // AUIPC, branches y JAL (destino)
localparam [1:0] ALU_A_ZERO = 2'd2;                   // LUI

// Operando B de la ALU (EX)
localparam ALU_B_RS2 = 1'b0;
localparam ALU_B_IMM = 1'b1;

// Operacion de la ALU (EX) = {instr[30], funct3} de OP / OP-IMM
localparam [3:0] ALU_ADD  = 4'b0000;
localparam [3:0] ALU_SUB  = 4'b1000;
localparam [3:0] ALU_SLL  = 4'b0001;
localparam [3:0] ALU_SLT  = 4'b0010;
localparam [3:0] ALU_SLTU = 4'b0011;
localparam [3:0] ALU_XOR  = 4'b0100;
localparam [3:0] ALU_SRL  = 4'b0101;
localparam [3:0] ALU_SRA  = 4'b1101;
localparam [3:0] ALU_OR   = 4'b0110;
localparam [3:0] ALU_AND  = 4'b0111;

// Valor que se escribe en rd (WB)
localparam [1:0] RES_ALU = 2'd0;
localparam [1:0] RES_MEM = 2'd1;
localparam [1:0] RES_PC4 = 2'd2;                      // JAL / JALR

// funct3 de branches (condicion, EX)
localparam [2:0] F3_BEQ  = 3'b000;
localparam [2:0] F3_BNE  = 3'b001;
localparam [2:0] F3_BLT  = 3'b100;
localparam [2:0] F3_BGE  = 3'b101;
localparam [2:0] F3_BLTU = 3'b110;
localparam [2:0] F3_BGEU = 3'b111;

// funct3 de loads / stores (tamano y signo, MEM)
localparam [2:0] F3_B  = 3'b000;
localparam [2:0] F3_H  = 3'b001;
localparam [2:0] F3_W  = 3'b010;
localparam [2:0] F3_BU = 3'b100;
localparam [2:0] F3_HU = 3'b101;
