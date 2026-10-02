`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_execute: testbench autoverificable de la etapa EX (execute)
//
// - Barre las 3 selecciones de operando A (ALU_A_RS1 / ALU_A_PC / ALU_A_ZERO),
//   las 2 de operando B, las 10 operaciones de RV32I y las 4 codificaciones
//   sin uso (para ver que caen en el default de alu_tp1).
// - Barre los 8 funct3 de branch con branch = 0/1 y jalr = 0/1, para el
//   comparador y para los dos destinos de salto.
// - Valores borde + aleatorios en pc, rs1_data, rs2_data e imm.
// - Modelo de referencia propio: no reutiliza alu_tp1 ni branch_cmp, y escribe
//   el overflow y los shifts con otras expresiones.
// - Al final imprime "EXECUTE TEST: PASSED" o la cantidad de errores.
// -----------------------------------------------------------------------------
module tb_execute;
    `include "riscv_defs.vh"

    // Codigos de ALU de RV32I (los 4 que no son RV32I se dejan para el default)
    reg [3:0] op_list [0:13];
    integer   n_ops;

    reg  [31:0] pc, rs1_data, rs2_data, imm;
    reg  [2:0]  funct3;
    reg  [1:0]  alu_src_a;
    reg         alu_src_b, branch, jalr;
    reg  [3:0]  alu_op;

    wire        redirect, branch_taken, alu_zero, alu_overflow;
    wire [31:0] target, alu_result, alu_a, alu_b;

    integer errors, checks, i, j, f, k, sa, sb, rnd;

    execute dut (
        .i_pc          (pc),
        .i_rs1_data    (rs1_data),
        .i_rs2_data    (rs2_data),
        .i_imm         (imm),
        .i_funct3      (funct3),
        .i_alu_src_a   (alu_src_a),
        .i_alu_src_b   (alu_src_b),
        .i_alu_op      (alu_op),
        .i_branch      (branch),
        .i_jalr        (jalr),
        .o_redirect    (redirect),
        .o_target      (target),
        .o_alu_result  (alu_result),
        .o_alu_zero    (alu_zero),
        .o_alu_overflow(alu_overflow),
        .o_branch_taken(branch_taken),
        .o_alu_a       (alu_a),
        .o_alu_b       (alu_b)
    );

    // ---------------------------------------------------------------- referencia
    function [31:0] ref_oper_a;
        input [1:0]  f_sel;
        input [31:0] f_pc;
        input [31:0] f_rs1;
        begin
            case (f_sel)
                ALU_A_PC:   ref_oper_a = f_pc;
                ALU_A_ZERO: ref_oper_a = 32'd0;
                default:    ref_oper_a = f_rs1;
            endcase
        end
    endfunction

    function [31:0] ref_alu;
        input [3:0]  f_op;
        input [31:0] f_a;
        input [31:0] f_b;
        reg [31:0] r;
        reg [4:0]  sh;
        begin
            sh = f_b[4:0];                               // RV32I: solo 5 bits
            case (f_op)
                ALU_ADD:  r = f_a + f_b;
                ALU_SUB:  r = f_a - f_b;
                ALU_SLL:  r = f_a << sh;
                ALU_SLT:  r = (($signed(f_a) < $signed(f_b)) ? 32'd1 : 32'd0);
                ALU_SLTU: r = ((f_a < f_b) ? 32'd1 : 32'd0);
                ALU_XOR:  r = f_a ^ f_b;
                ALU_SRL:  r = f_a >> sh;
                ALU_SRA:  r = $signed(f_a) >>> sh;
                ALU_OR:   r = f_a | f_b;
                ALU_AND:  r = f_a & f_b;
                default:  r = 32'd0;
            endcase
            ref_alu = r;
        end
    endfunction

    function ref_ovf;
        input [3:0]  f_op;
        input [31:0] f_a;
        input [31:0] f_b;
        input [31:0] f_r;
        begin
            case (f_op)
                ALU_ADD: ref_ovf = (f_a[31] == f_b[31]) && (f_r[31] != f_a[31]);
                ALU_SUB: ref_ovf = (f_a[31] != f_b[31]) && (f_r[31] != f_a[31]);
                default: ref_ovf = 1'b0;
            endcase
        end
    endfunction

    function ref_taken;
        input [2:0]  f_f3;
        input [31:0] f_a;
        input [31:0] f_b;
        input        f_branch;
        reg c;
        begin
            case (f_f3)
                F3_BEQ:  c = (f_a == f_b);
                F3_BNE:  c = (f_a != f_b);
                F3_BLT:  c = ($signed(f_a) < $signed(f_b));
                F3_BGE:  c = ($signed(f_a) >= $signed(f_b));
                F3_BLTU: c = (f_a < f_b);
                F3_BGEU: c = (f_a >= f_b);
                default: c = 1'b0;                        // 010 y 011
            endcase
            ref_taken = f_branch & c;
        end
    endfunction

    // ---------------------------------------------------------------- chequeo
    task check;
        input [1:0]  t_sa;
        input        t_sb;
        input [3:0]  t_op;
        input [2:0]  t_f3;
        input        t_br;
        input        t_jalr;
        input [31:0] t_pc;
        input [31:0] t_rs1;
        input [31:0] t_rs2;
        input [31:0] t_imm;
        reg [31:0] ea, eb, er, et, jsum;
        reg        ez, eo, ebr, ered;
        begin
            alu_src_a = t_sa; alu_src_b = t_sb; alu_op = t_op;
            funct3 = t_f3; branch = t_br; jalr = t_jalr;
            pc = t_pc; rs1_data = t_rs1; rs2_data = t_rs2; imm = t_imm;
            #1;

            ea   = ref_oper_a(t_sa, t_pc, t_rs1);
            eb   = t_sb ? t_imm : t_rs2;
            er   = ref_alu(t_op, ea, eb);
            eo   = ref_ovf(t_op, ea, eb, er);
            ez   = (er == 32'd0);
            ebr  = ref_taken(t_f3, t_rs1, t_rs2, t_br);
            ered = ebr | t_jalr;
            jsum = t_rs1 + t_imm;
            et   = t_jalr ? {jsum[31:1], 1'b0} : t_pc + t_imm;

            checks = checks + 1;
            if (alu_a !== ea || alu_b !== eb || alu_result !== er || alu_zero !== ez ||
                alu_overflow !== eo || branch_taken !== ebr || redirect !== ered ||
                target !== et) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("ERROR sa=%b sb=%b op=%b f3=%b br=%b jalr=%b pc=%h rs1=%h rs2=%h imm=%h",
                             t_sa, t_sb, t_op, t_f3, t_br, t_jalr, t_pc, t_rs1, t_rs2, t_imm);
                if (errors <= 20) begin
                    $display("       a  %h / %h   b %h / %h", alu_a, ea, alu_b, eb);
                    $display("       r  %h / %h   z %b/%b  ovf %b/%b",
                             alu_result, er, alu_zero, ez, alu_overflow, eo);
                    $display("       taken %b/%b  redirect %b/%b  target %h / %h",
                             branch_taken, ebr, redirect, ered, target, et);
                end
            end
        end
    endtask

    reg [31:0] edge_val [0:11];

    initial begin
        errors = 0;
        checks = 0;

        // Operaciones de RV32I + las 4 codificaciones sin uso de alu_ops.vh
        op_list[0]  = ALU_ADD;
        op_list[1]  = ALU_SUB;
        op_list[2]  = ALU_SLL;
        op_list[3]  = ALU_SLT;
        op_list[4]  = ALU_SLTU;
        op_list[5]  = ALU_XOR;
        op_list[6]  = ALU_SRL;
        op_list[7]  = ALU_SRA;
        op_list[8]  = ALU_OR;
        op_list[9]  = ALU_AND;
        op_list[10] = 4'b0110;                            // no usada
        op_list[11] = 4'b1010;                            // no usada
        op_list[12] = 4'b1110;                            // no usada
        op_list[13] = 4'b1111;                            // no usada
        n_ops = 14;

        edge_val[0]  = 32'h0000_0000;
        edge_val[1]  = 32'h0000_0001;
        edge_val[2]  = 32'hFFFF_FFFF;
        edge_val[3]  = 32'h8000_0000;
        edge_val[4]  = 32'h7FFF_FFFF;
        edge_val[5]  = 32'h0000_0002;
        edge_val[6]  = 32'hFFFF_FFFE;
        edge_val[7]  = 32'h8000_0001;
        edge_val[8]  = 32'h0000_001F;                         // shamt maximo
        edge_val[9]  = 32'h0000_0020;                         // un bit mas que shamt
        edge_val[10] = 32'hAAAA_AAAA;
        edge_val[11] = 32'h5555_5555;

        // 1) ALU: todas las operaciones x las 3 selecciones de A x las 2 de B
        //    x pares de valores borde
        for (k = 0; k < n_ops; k = k + 1)
            for (sa = 0; sa < 3; sa = sa + 1)
                for (sb = 0; sb < 2; sb = sb + 1)
                    for (i = 0; i < 12; i = i + 1)
                        for (j = 0; j < 12; j = j + 1)
                            check(sa[1:0], sb[0], op_list[k], 3'b000, 1'b0, 1'b0,
                                  edge_val[i], edge_val[j], edge_val[i], edge_val[j]);

        // 2) Comparador y destinos: todos los funct3 x branch x jalr
        for (f = 0; f < 8; f = f + 1)
            for (i = 0; i < 12; i = i + 1)
                for (j = 0; j < 12; j = j + 1)
                    for (sb = 0; sb < 2; sb = sb + 1)
                            check(ALU_A_RS1, ALU_B_RS2, ALU_SUB, f[2:0], 1'b1, 1'b0,
                                  edge_val[i], edge_val[i], edge_val[j], edge_val[j]);
        for (f = 0; f < 8; f = f + 1)
            for (i = 0; i < 12; i = i + 1)
                for (j = 0; j < 12; j = j + 1)
                    check(ALU_A_RS1, ALU_B_IMM, ALU_ADD, f[2:0], 1'b1, 1'b1,
                          edge_val[i], edge_val[j], edge_val[i], edge_val[j]);

        // 3) Aleatorios: todo mezclado
        for (rnd = 0; rnd < 30000; rnd = rnd + 1) begin
            sa = $urandom_range(2, 0);
            sb = $urandom_range(1, 0);
            f  = $urandom_range(7, 0);
            k  = $urandom_range(n_ops - 1, 0);
            check(sa[1:0], sb[0], op_list[k], f[2:0], $urandom_range(1, 0),
                  $urandom_range(1, 0), $urandom, $urandom, $urandom, $urandom);
        end

        // 4) Casos puntuales para mirar en la forma de onda
        check(ALU_A_RS1, ALU_B_RS2, ALU_ADD,  3'b000, 1'b0, 1'b0, 32'h10, 32'd5, 32'd7, 32'd0);
        check(ALU_A_PC,  ALU_B_IMM, ALU_ADD,  3'b000, 1'b0, 1'b0, 32'h10, 32'd5, 32'd7, 32'h24);
        check(ALU_A_ZERO, ALU_B_IMM, ALU_ADD, 3'b000, 1'b0, 1'b0, 32'h10, 32'd5, 32'd7, 32'h12345);
        check(ALU_A_RS1, ALU_B_RS2, ALU_ADD,  F3_BEQ, 1'b1, 1'b0, 32'h10, 32'd5, 32'd5, 32'h8); // taken
        check(ALU_A_RS1, ALU_B_RS2, ALU_SUB,  F3_BEQ, 1'b1, 1'b0, 32'h10, 32'd5, 32'd6, 32'h8); // no
        check(ALU_A_RS1, ALU_B_IMM, ALU_ADD,  F3_BEQ, 1'b1, 1'b1, 32'h10, 32'd5, 32'd6, 32'h3); // jalr
        check(ALU_A_RS1, ALU_B_RS2, ALU_ADD,  3'b000, 1'b0, 1'b0,
              32'h10, 32'h7FFF_FFFF, 32'd1, 32'd0);                                               // overflow
        check(ALU_A_RS1, ALU_B_IMM, ALU_SRA, 3'b101, 1'b0, 1'b0,
              32'h10, 32'h8000_0000, 32'd0, 32'h4000_0004);                                       // shamt = 4

        $display("----------------------------------------");
        $display("Chequeos: %0d   Errores: %0d", checks, errors);
        if (errors == 0) $display("EXECUTE TEST: PASSED");
        else             $display("EXECUTE TEST: FAILED");
        $display("----------------------------------------");
        $finish;
    end
endmodule