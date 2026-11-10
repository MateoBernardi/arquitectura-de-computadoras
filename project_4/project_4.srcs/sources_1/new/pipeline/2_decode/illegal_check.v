`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: illegal_check
// Description: Decides whether an instruction is legal in RV32I (without Zicsr,
//              Zifencei or any other extension). Combinational.
//              legal = exactly the 40 RV32I encodings:
//                LUI, AUIPC, JAL, JALR (funct3=0), BRANCH (funct3 != 010/011),
//                LOAD (LB LH LW LBU LHU), STORE (SB SH SW),
//                OP-IMM (SLLI/SRLI/SRAI with the funct7 the spec requires),
//                OP (funct7 = 0000000, or 0100000 for SUB/SRA),
//                FENCE (MISC-MEM funct3=0; the other fields are ignored, as the
//                spec requires), ECALL and EBREAK (exact encodings).
//              Everything else, including CSR instructions, FENCE.I, MRET, WFI
//              and every encoding with instr[1:0] != 11, is illegal.
//              ecall/ebreak tell the two legal SYSTEM instructions apart.
//////////////////////////////////////////////////////////////////////////////////
module illegal_check (
    input  wire [31:0] instr,
    output reg         illegal,
    output wire        ecall,
    output wire        ebreak
);
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    assign ecall  = (instr == 32'h0000_0073);
    assign ebreak = (instr == 32'h0010_0073);

    always @(*) begin
        case (opcode)
            7'b0110111,                                         // LUI
            7'b0010111,                                         // AUIPC
            7'b1101111: illegal = 1'b0;                         // JAL
            7'b1100111: illegal = (funct3 != 3'b000);           // JALR
            7'b1100011: illegal = (funct3 == 3'b010) || (funct3 == 3'b011);   // BRANCH
            7'b0000011: illegal = (funct3 == 3'b011) || (funct3 == 3'b110) ||
                                  (funct3 == 3'b111);           // LOAD
            7'b0100011: illegal = (funct3[2] == 1'b1) || (funct3 == 3'b011);  // STORE
            7'b0010011: case (funct3)                           // OP-IMM
                            3'b001:  illegal = (funct7 != 7'b0000000);               // SLLI
                            3'b101:  illegal = (funct7 != 7'b0000000) &&
                                               (funct7 != 7'b0100000);               // SRLI/SRAI
                            default: illegal = 1'b0;
                        endcase
            7'b0110011: illegal = !((funct7 == 7'b0000000) ||   // OP
                                    (funct7 == 7'b0100000 &&
                                     (funct3 == 3'b000 || funct3 == 3'b101)));      // SUB/SRA
            7'b0001111: illegal = (funct3 != 3'b000);           // FENCE (FENCE.I: no Zifencei)
            7'b1110011: illegal = !(ecall || ebreak);           // SYSTEM (no Zicsr)
            default:    illegal = 1'b1;
        endcase
    end
endmodule
