`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_instruction_decode: testbench autoverificado de la etapa ID
//
// 1. Banco de registros: escritura desde WB, x0 = 0, bypass, escritura
//    bloqueada con el pipeline deshabilitado, puerto de debug y reset.
// 2. Lista dirigida (todas las instrucciones RV32I, codificadas con el
//    ensamblador de GNU) + palabras ilegales. id_monitor imprime cada una.
// 3. Instrucciones aleatorias: mitad a partir de la tabla mascara/match de
//    RV32I, mitad palabras cualquiera.
// Para cada instruccion se chequea, contra una tabla independiente de la
// unidad de control:
//   - legal / ilegal,
//   - senales de control, indices de registros, funct3 e inmediato esperados,
//   - datos leidos del banco de registros,
//   - que id_monitor reconstruya la instruccion original desde las salidas,
//   - destino de JAL = pc + imm, y pc / pc+4 sin cambios.
//
// Icarus (desde la raiz del proyecto):
//   iverilog -Wall -g2005 -I rtl -s tb_instruction_decode -o tb_id \
//            sim/tb_instruction_decode.v sim/id_monitor.v rtl/*.v
//   vvp tb_id            (vvp tb_id +trace imprime tambien las aleatorias)
// XSIM: run -all
// -----------------------------------------------------------------------------
module tb_instruction_decode;
    `include "riscv_defs.vh"

    localparam integer N_RANDOM = 200000;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------ DUT
    reg         rst, en;
    reg  [31:0] instr, pc, pc4;
    reg         wb_we;
    reg  [4:0]  wb_rd;
    reg  [31:0] wb_data;
    reg  [4:0]  dbg_addr;
    reg         sample;

    wire [31:0] dbg_data, jal_target, o_pc, o_pc4, rs1_data, rs2_data, imm;
    wire [4:0]  rs1, rs2, rd;
    wire [2:0]  funct3;
    wire [1:0]  alu_src_a, result_src;
    wire [3:0]  alu_op;
    wire        jal, alu_src_b, reg_write, mem_read, mem_write, branch, jalr, halt, illegal;
    wire [31:0] rebuilt;

    instruction_decode dut (
        .i_clock       (clk),
        .i_reset       (rst),
        .i_enable      (en),
        .i_instruction (instr),
        .i_pc          (pc),
        .i_pc4         (pc4),
        .i_wb_reg_write(wb_we),
        .i_wb_rd       (wb_rd),
        .i_wb_data     (wb_data),
        .i_dbg_reg_addr(dbg_addr),
        .o_dbg_reg_data(dbg_data),
        .o_jal         (jal),
        .o_jal_target  (jal_target),
        .o_pc          (o_pc),
        .o_pc4         (o_pc4),
        .o_rs1_data    (rs1_data),
        .o_rs2_data    (rs2_data),
        .o_imm         (imm),
        .o_rs1         (rs1),
        .o_rs2         (rs2),
        .o_rd          (rd),
        .o_funct3      (funct3),
        .o_alu_src_a   (alu_src_a),
        .o_alu_src_b   (alu_src_b),
        .o_alu_op      (alu_op),
        .o_reg_write   (reg_write),
        .o_result_src  (result_src),
        .o_mem_read    (mem_read),
        .o_mem_write   (mem_write),
        .o_branch      (branch),
        .o_jalr        (jalr),
        .o_halt        (halt),
        .o_illegal     (illegal)
    );

    id_monitor #(.DETAIL(1)) mon (
        .i_clock      (clk),
        .i_sample     (sample),
        .i_instruction(instr),
        .i_pc         (o_pc),
        .i_rs1_data   (rs1_data),
        .i_rs2_data   (rs2_data),
        .i_imm        (imm),
        .i_rs1        (rs1),
        .i_rs2        (rs2),
        .i_rd         (rd),
        .i_funct3     (funct3),
        .i_alu_src_a  (alu_src_a),
        .i_alu_src_b  (alu_src_b),
        .i_alu_op     (alu_op),
        .i_reg_write  (reg_write),
        .i_result_src (result_src),
        .i_mem_read   (mem_read),
        .i_mem_write  (mem_write),
        .i_branch     (branch),
        .i_jal        (jal),
        .i_jalr       (jalr),
        .i_halt       (halt),
        .i_illegal    (illegal),
        .o_rebuilt    (rebuilt)
    );

    // ------------------------------------------------ tabla RV32I (mascara / match)
    localparam C_LUI = 0, C_AUIPC = 1, C_JAL = 2, C_JALR = 3, C_BRANCH = 4, C_LOAD = 5,
               C_STORE = 6, C_OPIMM = 7, C_OP = 8, C_FENCE = 9, C_SYSTEM = 10;
    localparam integer N_INSTR = 40;

    reg [31:0] t_mask  [0:N_INSTR-1];
    reg [31:0] t_match [0:N_INSTR-1];
    reg [3:0]  t_class [0:N_INSTR-1];
    reg [3:0]  t_aluop [0:N_INSTR-1];
    integer    t_hits  [0:N_INSTR-1];

    task def(input integer i, input [31:0] m, input [31:0] v, input [3:0] c, input [3:0] op);
        begin
            t_mask[i] = m; t_match[i] = v; t_class[i] = c; t_aluop[i] = op; t_hits[i] = 0;
        end
    endtask

    initial begin
        def( 0, 32'h0000007f, 32'h00000037, C_LUI,    ALU_ADD);   // lui
        def( 1, 32'h0000007f, 32'h00000017, C_AUIPC,  ALU_ADD);   // auipc
        def( 2, 32'h0000007f, 32'h0000006f, C_JAL,    ALU_ADD);   // jal
        def( 3, 32'h0000707f, 32'h00000067, C_JALR,   ALU_ADD);   // jalr
        def( 4, 32'h0000707f, 32'h00000063, C_BRANCH, ALU_ADD);   // beq
        def( 5, 32'h0000707f, 32'h00001063, C_BRANCH, ALU_ADD);   // bne
        def( 6, 32'h0000707f, 32'h00004063, C_BRANCH, ALU_ADD);   // blt
        def( 7, 32'h0000707f, 32'h00005063, C_BRANCH, ALU_ADD);   // bge
        def( 8, 32'h0000707f, 32'h00006063, C_BRANCH, ALU_ADD);   // bltu
        def( 9, 32'h0000707f, 32'h00007063, C_BRANCH, ALU_ADD);   // bgeu
        def(10, 32'h0000707f, 32'h00000003, C_LOAD,   ALU_ADD);   // lb
        def(11, 32'h0000707f, 32'h00001003, C_LOAD,   ALU_ADD);   // lh
        def(12, 32'h0000707f, 32'h00002003, C_LOAD,   ALU_ADD);   // lw
        def(13, 32'h0000707f, 32'h00004003, C_LOAD,   ALU_ADD);   // lbu
        def(14, 32'h0000707f, 32'h00005003, C_LOAD,   ALU_ADD);   // lhu
        def(15, 32'h0000707f, 32'h00000023, C_STORE,  ALU_ADD);   // sb
        def(16, 32'h0000707f, 32'h00001023, C_STORE,  ALU_ADD);   // sh
        def(17, 32'h0000707f, 32'h00002023, C_STORE,  ALU_ADD);   // sw
        def(18, 32'h0000707f, 32'h00000013, C_OPIMM,  ALU_ADD);   // addi
        def(19, 32'h0000707f, 32'h00002013, C_OPIMM,  ALU_SLT);   // slti
        def(20, 32'h0000707f, 32'h00003013, C_OPIMM,  ALU_SLTU);  // sltiu
        def(21, 32'h0000707f, 32'h00004013, C_OPIMM,  ALU_XOR);   // xori
        def(22, 32'h0000707f, 32'h00006013, C_OPIMM,  ALU_OR);    // ori
        def(23, 32'h0000707f, 32'h00007013, C_OPIMM,  ALU_AND);   // andi
        def(24, 32'hfe00707f, 32'h00001013, C_OPIMM,  ALU_SLL);   // slli
        def(25, 32'hfe00707f, 32'h00005013, C_OPIMM,  ALU_SRL);   // srli
        def(26, 32'hfe00707f, 32'h40005013, C_OPIMM,  ALU_SRA);   // srai
        def(27, 32'hfe00707f, 32'h00000033, C_OP,     ALU_ADD);   // add
        def(28, 32'hfe00707f, 32'h40000033, C_OP,     ALU_SUB);   // sub
        def(29, 32'hfe00707f, 32'h00001033, C_OP,     ALU_SLL);   // sll
        def(30, 32'hfe00707f, 32'h00002033, C_OP,     ALU_SLT);   // slt
        def(31, 32'hfe00707f, 32'h00003033, C_OP,     ALU_SLTU);  // sltu
        def(32, 32'hfe00707f, 32'h00004033, C_OP,     ALU_XOR);   // xor
        def(33, 32'hfe00707f, 32'h00005033, C_OP,     ALU_SRL);   // srl
        def(34, 32'hfe00707f, 32'h40005033, C_OP,     ALU_SRA);   // sra
        def(35, 32'hfe00707f, 32'h00006033, C_OP,     ALU_OR);    // or
        def(36, 32'hfe00707f, 32'h00007033, C_OP,     ALU_AND);   // and
        def(37, 32'h0000707f, 32'h0000000f, C_FENCE,  ALU_ADD);   // fence
        def(38, 32'hffffffff, 32'h00000073, C_SYSTEM, ALU_ADD);   // ecall
        def(39, 32'hffffffff, 32'h00100073, C_SYSTEM, ALU_ADD);   // ebreak
    end

    function integer identify(input [31:0] w);
        integer i;
        begin
            identify = -1;
            for (i = 0; i < N_INSTR; i = i + 1)
                if ((w & t_mask[i]) == t_match[i])
                    identify = i;
        end
    endfunction

    // ------------------------------------------------ modelo del banco de registros
    reg [31:0] rf [0:31];

    function [31:0] rf_read(input [4:0] a);
        rf_read = (a == 5'd0) ? 32'd0 : rf[a];
    endfunction

    // ------------------------------------------------ chequeo de una instruccion
    integer errors, checks, n_legal, n_illegal;

    reg [31:0] e_imm;
    reg [4:0]  e_rs1, e_rs2, e_rd;
    reg [2:0]  e_funct3;
    reg [1:0]  e_a, e_res;
    reg        e_b, e_wr, e_mr, e_mw, e_br, e_jal, e_jalr, e_halt;
    reg [3:0]  e_op;

    task check_decode;
        integer idx;
        reg [3:0] cls;
        reg       ok;
        begin
            idx = identify(instr);
            // valores esperados por defecto: nada con efecto
            e_imm = 32'd0; e_rs1 = 5'd0; e_rs2 = 5'd0; e_rd = 5'd0; e_funct3 = 3'd0;
            e_a = ALU_A_RS1; e_b = ALU_B_RS2; e_op = ALU_ADD; e_res = RES_ALU;
            e_wr = 1'b0; e_mr = 1'b0; e_mw = 1'b0; e_br = 1'b0; e_jal = 1'b0; e_jalr = 1'b0; e_halt = 1'b0;
            if (idx >= 0) begin
                t_hits[idx] = t_hits[idx] + 1;
                cls = t_class[idx];
                case (cls)
                    C_LUI: begin
                        e_imm = {instr[31:12], 12'd0}; e_a = ALU_A_ZERO; e_b = ALU_B_IMM; e_rd = instr[11:7];
                    end
                    C_AUIPC: begin
                        e_imm = {instr[31:12], 12'd0}; e_a = ALU_A_PC; e_b = ALU_B_IMM; e_rd = instr[11:7];
                    end
                    C_JAL: begin
                        e_imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
                        e_a = ALU_A_PC; e_b = ALU_B_IMM; e_res = RES_PC4; e_jal = 1'b1; e_rd = instr[11:7];
                    end
                    C_JALR: begin
                        e_imm = {{20{instr[31]}}, instr[31:20]}; e_b = ALU_B_IMM; e_res = RES_PC4;
                        e_jalr = 1'b1; e_rd = instr[11:7]; e_rs1 = instr[19:15];
                    end
                    C_BRANCH: begin
                        e_imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
                        e_a = ALU_A_PC; e_b = ALU_B_IMM; e_br = 1'b1; e_funct3 = instr[14:12];
                        e_rs1 = instr[19:15]; e_rs2 = instr[24:20];
                    end
                    C_LOAD: begin
                        e_imm = {{20{instr[31]}}, instr[31:20]}; e_b = ALU_B_IMM; e_res = RES_MEM; e_mr = 1'b1;
                        e_funct3 = instr[14:12]; e_rd = instr[11:7]; e_rs1 = instr[19:15];
                    end
                    C_STORE: begin
                        e_imm = {{20{instr[31]}}, instr[31:25], instr[11:7]}; e_b = ALU_B_IMM; e_mw = 1'b1;
                        e_funct3 = instr[14:12]; e_rs1 = instr[19:15]; e_rs2 = instr[24:20];
                    end
                    C_OPIMM: begin
                        e_imm = {{20{instr[31]}}, instr[31:20]}; e_b = ALU_B_IMM; e_op = t_aluop[idx];
                        e_rd = instr[11:7]; e_rs1 = instr[19:15];
                    end
                    C_OP: begin
                        e_op = t_aluop[idx]; e_rd = instr[11:7]; e_rs1 = instr[19:15]; e_rs2 = instr[24:20];
                    end
                    C_FENCE: begin
                        e_b = ALU_B_IMM;
                    end
                    C_SYSTEM: begin
                        e_imm = {{20{instr[31]}}, instr[31:20]}; e_halt = 1'b1;
                    end
                    default: ;
                endcase
                e_wr = (e_rd != 5'd0);
            end

            ok = (illegal     === (idx < 0))  &&
                 (imm         === e_imm)      &&
                 (rs1         === e_rs1)      &&
                 (rs2         === e_rs2)      &&
                 (rd          === e_rd)       &&
                 (funct3      === e_funct3)   &&
                 (alu_src_a   === e_a)        &&
                 (alu_src_b   === e_b)        &&
                 (alu_op      === e_op)       &&
                 (reg_write   === e_wr)       &&
                 (result_src  === e_res)      &&
                 (mem_read    === e_mr)       &&
                 (mem_write   === e_mw)       &&
                 (branch      === e_br)       &&
                 (jal         === e_jal)      &&
                 (jalr        === e_jalr)     &&
                 (halt        === e_halt)     &&
                 (rs1_data    === rf_read(e_rs1)) &&
                 (rs2_data    === rf_read(e_rs2)) &&
                 (jal_target  === pc + imm)   &&
                 (o_pc        === pc)         &&
                 (o_pc4       === pc4);
            if (idx >= 0)
                ok = ok && (rebuilt === ((t_class[idx] == C_FENCE) ? INSTR_NOP : instr));

            checks = checks + 1;
            if (idx >= 0) n_legal = n_legal + 1; else n_illegal = n_illegal + 1;
            if (!ok) begin
                errors = errors + 1;
                if (errors <= 10) begin
                    $display("FAIL instr=%h (tabla: %0d) illegal=%b imm=%h/%h rs1=%0d/%0d rs2=%0d/%0d rd=%0d/%0d f3=%b/%b",
                             instr, idx, illegal, imm, e_imm, rs1, e_rs1, rs2, e_rs2, rd, e_rd, funct3, e_funct3);
                    $display("     a=%0d/%0d b=%b/%b op=%b/%b wr=%b/%b res=%0d/%0d mr=%b/%b mw=%b/%b br=%b/%b jal=%b/%b jalr=%b/%b halt=%b/%b rebuilt=%h",
                             alu_src_a, e_a, alu_src_b, e_b, alu_op, e_op, reg_write, e_wr, result_src, e_res,
                             mem_read, e_mr, mem_write, e_mw, branch, e_br, jal, e_jal, jalr, e_jalr, halt, e_halt, rebuilt);
                end
            end
        end
    endtask

    // Presenta una instruccion un ciclo y la chequea
    task present(input [31:0] w, input [31:0] addr, input show);
        begin
            @(negedge clk);
            instr  = w;
            pc     = addr;
            pc4    = addr + 32'd4;
            sample = show;
            @(posedge clk);
            check_decode;
        end
    endtask

    // Escritura desde WB (un ciclo)
    task wb_write(input [4:0] r, input [31:0] v);
        begin
            @(negedge clk);
            wb_we = 1'b1; wb_rd = r; wb_data = v;
            @(posedge clk);
            if (en && r != 5'd0) rf[r] = v;
            @(negedge clk);
            wb_we = 1'b0;
        end
    endtask

    task expect(input cond, input [8*48-1:0] what);
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL %0s", what);
            end
        end
    endtask

    // ------------------------------------------------ lista dirigida
    reg [31:0] dir [0:63];
    integer    n_dir;

    initial begin
        n_dir = 0;
        dir[n_dir] = 32'h123450b7; n_dir = n_dir + 1;  // lui   x1,0x12345
        dir[n_dir] = 32'hfffff037; n_dir = n_dir + 1;  // lui   x0,0xfffff
        dir[n_dir] = 32'h00001117; n_dir = n_dir + 1;  // auipc x2,0x1
        dir[n_dir] = 32'h80000f97; n_dir = n_dir + 1;  // auipc x31,0x80000
        dir[n_dir] = 32'h00c000ef; n_dir = n_dir + 1;  // jal   x1,+12
        dir[n_dir] = 32'h801ff06f; n_dir = n_dir + 1;  // jal   x0,-2048
        dir[n_dir] = 32'h00028067; n_dir = n_dir + 1;  // jalr  x0,0(x5)
        dir[n_dir] = 32'hffff80e7; n_dir = n_dir + 1;  // jalr  x1,-1(x31)
        dir[n_dir] = 32'hfe208ce3; n_dir = n_dir + 1;  // beq   x1,x2,-8
        dir[n_dir] = 32'h7e419fe3; n_dir = n_dir + 1;  // bne   x3,x4,+4094
        dir[n_dir] = 32'h0062c863; n_dir = n_dir + 1;  // blt   x5,x6,+16
        dir[n_dir] = 32'h8083d063; n_dir = n_dir + 1;  // bge   x7,x8,-4096
        dir[n_dir] = 32'h00a4e163; n_dir = n_dir + 1;  // bltu  x9,x10,+2
        dir[n_dir] = 32'h000ff263; n_dir = n_dir + 1;  // bgeu  x31,x0,+4
        dir[n_dir] = 32'hfff30283; n_dir = n_dir + 1;  // lb    x5,-1(x6)
        dir[n_dir] = 32'h00241383; n_dir = n_dir + 1;  // lh    x7,2(x8)
        dir[n_dir] = 32'h00802403; n_dir = n_dir + 1;  // lw    x8,8(x0)
        dir[n_dir] = 32'h0000c003; n_dir = n_dir + 1;  // lbu   x0,0(x1)
        dir[n_dir] = 32'h7ff55483; n_dir = n_dir + 1;  // lhu   x9,2047(x10)
        dir[n_dir] = 32'h80b60023; n_dir = n_dir + 1;  // sb    x11,-2048(x12)
        dir[n_dir] = 32'h00d71323; n_dir = n_dir + 1;  // sh    x13,6(x14)
        dir[n_dir] = 32'h00602423; n_dir = n_dir + 1;  // sw    x6,8(x0)
        dir[n_dir] = 32'hffb00193; n_dir = n_dir + 1;  // addi  x3,x0,-5
        dir[n_dir] = 32'h7ff2a213; n_dir = n_dir + 1;  // slti  x4,x5,2047
        dir[n_dir] = 32'hfff63593; n_dir = n_dir + 1;  // sltiu x11,x12,-1
        dir[n_dir] = 32'h80074693; n_dir = n_dir + 1;  // xori  x13,x14,-2048
        dir[n_dir] = 32'h07f86793; n_dir = n_dir + 1;  // ori   x15,x16,127
        dir[n_dir] = 32'h0ff97893; n_dir = n_dir + 1;  // andi  x17,x18,255
        dir[n_dir] = 32'h00319213; n_dir = n_dir + 1;  // slli  x4,x3,3
        dir[n_dir] = 32'h01f35293; n_dir = n_dir + 1;  // srli  x5,x6,31
        dir[n_dir] = 32'h4011d293; n_dir = n_dir + 1;  // srai  x5,x3,1
        dir[n_dir] = 32'h00208333; n_dir = n_dir + 1;  // add   x6,x1,x2
        dir[n_dir] = 32'h402083b3; n_dir = n_dir + 1;  // sub   x7,x1,x2
        dir[n_dir] = 32'h00a49433; n_dir = n_dir + 1;  // sll   x8,x9,x10
        dir[n_dir] = 32'h00d625b3; n_dir = n_dir + 1;  // slt   x11,x12,x13
        dir[n_dir] = 32'h0107b733; n_dir = n_dir + 1;  // sltu  x14,x15,x16
        dir[n_dir] = 32'h013948b3; n_dir = n_dir + 1;  // xor   x17,x18,x19
        dir[n_dir] = 32'h016ada33; n_dir = n_dir + 1;  // srl   x20,x21,x22
        dir[n_dir] = 32'h419c5bb3; n_dir = n_dir + 1;  // sra   x23,x24,x25
        dir[n_dir] = 32'h01cded33; n_dir = n_dir + 1;  // or    x26,x27,x28
        dir[n_dir] = 32'h01ff7eb3; n_dir = n_dir + 1;  // and   x29,x30,x31
        dir[n_dir] = 32'h00208033; n_dir = n_dir + 1;  // add   x0,x1,x2   (escribe x0)
        dir[n_dir] = 32'h00000013; n_dir = n_dir + 1;  // addi  x0,x0,0   (nop)
        dir[n_dir] = 32'h0ff0000f; n_dir = n_dir + 1;  // fence iorw,iorw
        dir[n_dir] = 32'h00000073; n_dir = n_dir + 1;  // ecall
        dir[n_dir] = 32'h00100073; n_dir = n_dir + 1;  // ebreak
        // ilegales en RV32I
        dir[n_dir] = 32'h00000000; n_dir = n_dir + 1;  // todo en 0
        dir[n_dir] = 32'hffffffff; n_dir = n_dir + 1;  // todo en 1
        dir[n_dir] = 32'h00002063; n_dir = n_dir + 1;  // branch con funct3 = 010
        dir[n_dir] = 32'h00001067; n_dir = n_dir + 1;  // jalr con funct3 = 001
        dir[n_dir] = 32'h00003003; n_dir = n_dir + 1;  // ld (RV64)
        dir[n_dir] = 32'h00003023; n_dir = n_dir + 1;  // sd (RV64)
        dir[n_dir] = 32'h40001013; n_dir = n_dir + 1;  // slli con funct7 = 0100000
        dir[n_dir] = 32'h02001013; n_dir = n_dir + 1;  // slli con shamt[5] = 1 (RV64)
        dir[n_dir] = 32'h40006033; n_dir = n_dir + 1;  // or con funct7 = 0100000
        dir[n_dir] = 32'h02000033; n_dir = n_dir + 1;  // mul (extension M)
        dir[n_dir] = 32'h00001073; n_dir = n_dir + 1;  // csrrw (Zicsr)
        dir[n_dir] = 32'h0000100f; n_dir = n_dir + 1;  // fence.i (Zifencei)
        dir[n_dir] = 32'h00000001; n_dir = n_dir + 1;  // instruccion comprimida
    end

    // ------------------------------------------------ secuencia
    integer    i, k, seed, trace, n_trace;
    reg [31:0] w;

    initial begin
        errors = 0; checks = 0; n_legal = 0; n_illegal = 0;
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        trace = $test$plusargs("trace");
        rst = 1'b1; en = 1'b1; instr = INSTR_NOP; pc = 32'd0; pc4 = 32'd4;
        wb_we = 1'b0; wb_rd = 5'd0; wb_data = 32'd0; dbg_addr = 5'd0; sample = 1'b0;
        for (i = 0; i < 32; i = i + 1) rf[i] = 32'd0;

        #100;                                          // GSR de XSIM
        @(negedge clk);
        rst = 1'b0;

        $display("-- Banco de registros");
        for (i = 0; i < 32; i = i + 1)
            wb_write(i, 32'h0101_0101 * i + 32'h0000_0100);
        for (i = 0; i < 32; i = i + 1) begin
            dbg_addr = i;
            #1;
            expect(dbg_data === rf_read(i), "puerto de debug = modelo (x0 = 0)");
        end

        // Con el pipeline deshabilitado no se escribe, pero el bypass ve el dato
        @(negedge clk);
        en = 1'b0; wb_we = 1'b1; wb_rd = 5'd5; wb_data = 32'hDEAD_BEEF;
        instr = 32'h00028033;                          // add x0,x5,x0: lee x5
        #1;
        expect(rs1_data === 32'hDEAD_BEEF, "bypass con el pipeline detenido");
        @(posedge clk);
        @(negedge clk);
        wb_we = 1'b0; en = 1'b1; dbg_addr = 5'd5;
        #1;
        expect(dbg_data === rf[5], "sin escritura con i_enable = 0");
        expect(rs1_data === rf[5], "lectura normal despues");

        // Bypass: WB escribe x7 en el mismo ciclo en que ID lo lee
        @(negedge clk);
        wb_we = 1'b1; wb_rd = 5'd7; wb_data = 32'h1234_5678;
        instr = 32'h00738033;                          // add x0,x7,x7
        #1;
        expect(rs1_data === 32'h1234_5678 && rs2_data === 32'h1234_5678, "bypass rs1 y rs2");
        @(posedge clk);
        rf[7] = 32'h1234_5678;
        @(negedge clk);
        wb_we = 1'b0; dbg_addr = 5'd7;
        #1;
        expect(dbg_data === 32'h1234_5678, "escritura despues del bypass");

        // Escribir x0 no tiene efecto
        wb_write(5'd0, 32'hFFFF_FFFF);
        dbg_addr = 5'd0;
        #1;
        expect(dbg_data === 32'd0, "x0 sigue en 0");

        $display("-- Lista dirigida");
        for (i = 0; i < n_dir; i = i + 1)
            present(dir[i], 32'h0000_0100 + 4 * i, 1'b1);
        @(negedge clk);
        sample = 1'b0;

        $display("-- %0d instrucciones aleatorias", N_RANDOM);
        n_trace = 0;
        for (i = 0; i < N_RANDOM; i = i + 1) begin
            if (i % 2 == 0) begin                      // instruccion legal con campos al azar
                k = $unsigned($random(seed)) % N_INSTR;
                w = $random(seed);
                w = (w & ~t_mask[k]) | t_match[k];
            end
            else begin                                 // palabra cualquiera
                w = $random(seed);
            end
            if (trace && identify(w) >= 0 && w[6:0] != OPC_FENCE) begin
                present(w, 4 * n_trace, 1'b1);
                n_trace = n_trace + 1;
            end
            else begin
                present(w, $random(seed), 1'b0);
            end
        end

        for (i = 0; i < N_INSTR; i = i + 1)
            expect(t_hits[i] > 100, "cobertura: cada instruccion aparece mas de 100 veces");

        $display("-- Reset");
        @(negedge clk);
        rst = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        for (i = 0; i < 32; i = i + 1) begin
            dbg_addr = i;
            #1;
            expect(dbg_data === 32'd0, "reset pone todos los registros en 0");
        end

        $display("legales=%0d ilegales=%0d", n_legal, n_illegal);
        if (errors == 0)
            $display("PASS: %0d chequeos OK", checks);
        else
            $display("FAIL: %0d errores en %0d chequeos", errors, checks);
        $finish;
    end
endmodule
