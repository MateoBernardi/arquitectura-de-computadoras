`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// id_monitor: monitor de simulacion de las salidas de ID (no sintetizable)
//
// Recibe todo lo que ID entrega hacia EX y:
// - o_rebuilt: reconstruye la instruccion de 32 bits solo a partir de esas
//   salidas (control + indices + inmediato). Si coincide con la instruccion
//   que entro a ID, la decodificacion no perdio ni cambio nada.
//   FENCE sale como addi x0,x0,0 (se ejecuta como NOP); ilegal: 0.
// - En cada flanco de subida con i_sample = 1 imprime la instruccion armada
//   desde las salidas (mismo formato que objdump -M no-aliases,numeric) y, con
//   DETAIL = 1, cada salida.
// Uso: instanciarlo en un testbench conectado a las salidas de
// instruction_decode (o a ID/EX, cuando exista).
// -----------------------------------------------------------------------------
module id_monitor #(
    parameter DETAIL = 1
) (
    input  wire        i_clock,
    input  wire        i_sample,
    input  wire [31:0] i_instruction,                  // instruccion que entro a ID
    input  wire [31:0] i_pc,
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
    input  wire        i_reg_write,
    input  wire [1:0]  i_result_src,
    input  wire        i_mem_read,
    input  wire        i_mem_write,
    input  wire        i_branch,
    input  wire        i_jal,
    input  wire        i_jalr,
    input  wire        i_halt,
    input  wire        i_illegal,
    output reg  [31:0] o_rebuilt
);
    `include "riscv_defs.vh"

    wire is_shift = (i_alu_op[2:0] == 3'b001) || (i_alu_op[2:0] == 3'b101);

    // ------------------------------------------------ reconstruccion
    always @(*) begin
        if (i_illegal)
            o_rebuilt = 32'd0;
        else if (i_halt)
            o_rebuilt = {i_imm[11:0], 5'd0, 3'b000, 5'd0, OPC_SYSTEM};
        else if (i_jal)
            o_rebuilt = {i_imm[20], i_imm[10:1], i_imm[11], i_imm[19:12], i_rd, OPC_JAL};
        else if (i_jalr)
            o_rebuilt = {i_imm[11:0], i_rs1, 3'b000, i_rd, OPC_JALR};
        else if (i_branch)
            o_rebuilt = {i_imm[12], i_imm[10:5], i_rs2, i_rs1, i_funct3, i_imm[4:1], i_imm[11], OPC_BRANCH};
        else if (i_mem_read)
            o_rebuilt = {i_imm[11:0], i_rs1, i_funct3, i_rd, OPC_LOAD};
        else if (i_mem_write)
            o_rebuilt = {i_imm[11:5], i_rs2, i_rs1, i_funct3, i_imm[4:0], OPC_STORE};
        else if (i_alu_src_a == ALU_A_ZERO)
            o_rebuilt = {i_imm[31:12], i_rd, OPC_LUI};
        else if (i_alu_src_a == ALU_A_PC)
            o_rebuilt = {i_imm[31:12], i_rd, OPC_AUIPC};
        else if (i_alu_src_b == ALU_B_RS2)
            o_rebuilt = {1'b0, i_alu_op[3], 5'd0, i_rs2, i_rs1, i_alu_op[2:0], i_rd, OPC_OP};
        else if (is_shift)
            o_rebuilt = {1'b0, i_alu_op[3], 5'd0, i_imm[4:0], i_rs1, i_alu_op[2:0], i_rd, OPC_OP_IMM};
        else
            o_rebuilt = {i_imm[11:0], i_rs1, i_alu_op[2:0], i_rd, OPC_OP_IMM};
    end

    // ------------------------------------------------ impresion
    task put_alu_name(input imm_form);
        begin
            case (i_alu_op)
                ALU_ADD:  if (imm_form) $write("addi");  else $write("add");
                ALU_SUB:  $write("sub");
                ALU_SLL:  if (imm_form) $write("slli");  else $write("sll");
                ALU_SLT:  if (imm_form) $write("slti");  else $write("slt");
                ALU_SLTU: if (imm_form) $write("sltiu"); else $write("sltu");
                ALU_XOR:  if (imm_form) $write("xori");  else $write("xor");
                ALU_SRL:  if (imm_form) $write("srli");  else $write("srl");
                ALU_SRA:  if (imm_form) $write("srai");  else $write("sra");
                ALU_OR:   if (imm_form) $write("ori");   else $write("or");
                ALU_AND:  if (imm_form) $write("andi");  else $write("and");
                default:  $write("alu?");
            endcase
        end
    endtask

    task put_asm;
        begin
            if (i_illegal)
                $write("<ilegal>");
            else if (i_halt) begin
                if (i_imm[0]) $write("ebreak");
                else          $write("ecall");
            end
            else if (i_jal)
                $write("jal x%0d,0x%0h", i_rd, i_pc + i_imm);
            else if (i_jalr)
                $write("jalr x%0d,%0d(x%0d)", i_rd, $signed(i_imm), i_rs1);
            else if (i_branch) begin
                case (i_funct3)
                    F3_BEQ:  $write("beq");
                    F3_BNE:  $write("bne");
                    F3_BLT:  $write("blt");
                    F3_BGE:  $write("bge");
                    F3_BLTU: $write("bltu");
                    F3_BGEU: $write("bgeu");
                    default: $write("b?");
                endcase
                $write(" x%0d,x%0d,0x%0h", i_rs1, i_rs2, i_pc + i_imm);
            end
            else if (i_mem_read) begin
                case (i_funct3)
                    F3_B:    $write("lb");
                    F3_H:    $write("lh");
                    F3_W:    $write("lw");
                    F3_BU:   $write("lbu");
                    F3_HU:   $write("lhu");
                    default: $write("l?");
                endcase
                $write(" x%0d,%0d(x%0d)", i_rd, $signed(i_imm), i_rs1);
            end
            else if (i_mem_write) begin
                case (i_funct3)
                    F3_B:    $write("sb");
                    F3_H:    $write("sh");
                    F3_W:    $write("sw");
                    default: $write("s?");
                endcase
                $write(" x%0d,%0d(x%0d)", i_rs2, $signed(i_imm), i_rs1);
            end
            else if (i_alu_src_a == ALU_A_ZERO)
                $write("lui x%0d,0x%0h", i_rd, i_imm[31:12]);
            else if (i_alu_src_a == ALU_A_PC)
                $write("auipc x%0d,0x%0h", i_rd, i_imm[31:12]);
            else if (i_alu_src_b == ALU_B_RS2) begin
                put_alu_name(1'b0);
                $write(" x%0d,x%0d,x%0d", i_rd, i_rs1, i_rs2);
            end
            else if (is_shift) begin
                put_alu_name(1'b1);
                $write(" x%0d,x%0d,0x%0h", i_rd, i_rs1, i_imm[4:0]);
            end
            else begin
                put_alu_name(1'b1);
                $write(" x%0d,x%0d,%0d", i_rd, i_rs1, $signed(i_imm));
            end
        end
    endtask

    always @(posedge i_clock) begin
        if (i_sample) begin
            $write("[ID] pc=%h instr=%h | ", i_pc, i_instruction);
            put_asm;
            $display("");
            if (DETAIL) begin
                $display("     rd=x%0d rs1=x%0d (%h) rs2=x%0d (%h) imm=%h funct3=%b",
                         i_rd, i_rs1, i_rs1_data, i_rs2, i_rs2_data, i_imm, i_funct3);
                $write("     alu: a=");
                case (i_alu_src_a)
                    ALU_A_RS1:  $write("rs1");
                    ALU_A_PC:   $write("pc");
                    ALU_A_ZERO: $write("0");
                    default:    $write("?");
                endcase
                $write(" b=%s op=", (i_alu_src_b == ALU_B_IMM) ? "imm" : "rs2");
                put_alu_name(1'b0);
                $write(" | wb: reg_write=%b res=", i_reg_write);
                case (i_result_src)
                    RES_ALU: $write("alu");
                    RES_MEM: $write("mem");
                    RES_PC4: $write("pc+4");
                    default: $write("?");
                endcase
                $display(" | mem: read=%b write=%b | branch=%b jal=%b jalr=%b halt=%b illegal=%b",
                         i_mem_read, i_mem_write, i_branch, i_jal, i_jalr, i_halt, i_illegal);
                if (!i_illegal) begin
                    if (o_rebuilt == i_instruction)
                        $display("     reconstruida=%h (igual a la original)", o_rebuilt);
                    else if (i_instruction[6:0] == OPC_FENCE)
                        $display("     reconstruida=%h (FENCE se ejecuta como NOP)", o_rebuilt);
                    else
                        $display("     reconstruida=%h (DISTINTA de la original)", o_rebuilt);
                end
            end
        end
    end
endmodule
