// RISC-V Control Unit - decodes opcode, drives datapath
module control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg        reg_write,
    output reg        alu_src,
    output reg        mem_read,
    output reg        mem_write,
    output reg        branch,
    output reg        jump,
    output reg  [1:0] wb_sel,   // 00=ALU,01=MEM,10=PC+4,11=Uimm
    output reg  [3:0] alu_op,
    output reg  [2:0] imm_sel
);
`include "alu_ops.vh"

    localparam R   = 7'b0110011;  // R-type
    localparam I   = 7'b0010011;  // I-type ALU
    localparam LOAD= 7'b0000011;  // loads
    localparam STOR= 7'b0100011;  // stores
    localparam BR  = 7'b1100011;  // branches
    localparam JAL = 7'b1101111;  // jal
    localparam JALR= 7'b1100111;  // jalr
    localparam LUI = 7'b0110111;  // lui
    localparam AUIP= 7'b0010111;  // auipc

    always @(*) begin
        // defaults - safe values
        {reg_write,alu_src,mem_read,mem_write,branch,jump}=6'b0;
        wb_sel=2'b00; alu_op=OP_ADD; imm_sel=3'b000;
        case (opcode)
            R:    begin reg_write=1; alu_src=0; wb_sel=2'b00;
                    case({funct7[5],funct3})
                        4'b0000: alu_op=OP_ADD;
                        4'b1000: alu_op=OP_SUB;
                        4'b0111: alu_op=OP_AND;
                        4'b0110: alu_op=OP_OR;
                        4'b0100: alu_op=OP_XOR;
                        4'b0010: alu_op=OP_SLT;
                        4'b0011: alu_op=OP_SLTU;
                        4'b0001: alu_op=OP_SLL;
                        4'b0101: alu_op=OP_SRL;
                        4'b1101: alu_op=OP_SRA;
                        default: alu_op=OP_ADD;
                    endcase end
            I:    begin reg_write=1; alu_src=1; wb_sel=2'b00; imm_sel=3'b000;
                    case(funct3)
                        3'h0: alu_op=OP_ADD;  // ADDI
                        3'h7: alu_op=OP_AND;  // ANDI
                        3'h6: alu_op=OP_OR;   // ORI
                        3'h4: alu_op=OP_XOR;  // XORI
                        3'h2: alu_op=OP_SLT;  // SLTI
                        3'h3: alu_op=OP_SLTU; // SLTIU
                        3'h1: alu_op=OP_SLL;  // SLLI
                        3'h5: alu_op=(funct7[5])?OP_SRA:OP_SRL; // SRAI/SRLI
                        default: alu_op=OP_ADD;
                    endcase end
            LOAD: begin reg_write=1; alu_src=1; mem_read=1; wb_sel=2'b01; imm_sel=3'b000; alu_op=OP_ADD; end
            STOR: begin alu_src=1; mem_write=1; imm_sel=3'b001; alu_op=OP_ADD; end
            BR:   begin branch=1; imm_sel=3'b010;
                    alu_op=(funct3==3'h4||funct3==3'h5)?OP_SLT:OP_SUB; end
            JAL:  begin reg_write=1; jump=1; wb_sel=2'b10; imm_sel=3'b100; end
            JALR: begin reg_write=1; alu_src=1; jump=1; wb_sel=2'b10; imm_sel=3'b000; alu_op=OP_ADD; end
            LUI:  begin reg_write=1; wb_sel=2'b11; imm_sel=3'b011; end
            AUIP: begin reg_write=1; alu_src=1; wb_sel=2'b00; imm_sel=3'b011; alu_op=OP_ADD; end
            default: ;
        endcase
    end
endmodule