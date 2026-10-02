`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// branch_cmp_tb: testbench autoverificable de branch_cmp
//
// - Prueba los 8 valores de funct3 (000, 001, 100, 101, 110, 111 son branches;
//   010 y 011 son invalidos y nunca deben saltar), con i_branch = 1 y = 0.
// - Todos los pares de valores borde + aleatorios (la mitad con a == b, para
//   cubrir BEQ / BNE / BGE / BGEU en el caso de igualdad).
// - Modelo de referencia con otras expresiones que el modulo (no usa $signed).
// - Al final imprime "BRANCH_CMP TEST: PASSED" o la cantidad de errores.
// -----------------------------------------------------------------------------
module tb_branch_cmp;
    `include "riscv_defs.vh"

    reg  [31:0] a, b;
    reg  [2:0]  f3;
    reg         br;
    wire        taken;

    integer errors;
    integer checks;
    integer f, i, j;
    reg [31:0] ra, rb;

    branch_cmp dut (
        .i_a     (a),
        .i_b     (b),
        .i_funct3(f3),
        .i_branch(br),
        .o_taken (taken)
    );

    // Modelo de referencia
    function ref_taken;
        input [2:0]  f_f3;
        input [31:0] f_a;
        input [31:0] f_b;
        input        f_br;
        reg eq, lt, ltu, c;
        begin
            eq  = ~|(f_a ^ f_b);
            ltu = (f_a < f_b);
            if (f_a[31] != f_b[31]) lt = f_a[31];       // signos distintos: el negativo es menor
            else                    lt = ltu;
            case (f_f3)
                F3_BEQ:  c = eq;
                F3_BNE:  c = ~eq;
                F3_BLT:  c = lt;
                F3_BGE:  c = ~lt;
                F3_BLTU: c = ltu;
                F3_BGEU: c = ~ltu;
                default: c = 1'b0;                      // 010 y 011
            endcase
            ref_taken = f_br & c;
        end
    endfunction

    task check;
        input [2:0]  t_f3;
        input [31:0] t_a;
        input [31:0] t_b;
        input        t_br;
        reg          expected;
        begin
            f3 = t_f3; a = t_a; b = t_b; br = t_br;
            #1;
            expected = ref_taken(t_f3, t_a, t_b, t_br);
            checks = checks + 1;
            if (taken !== expected) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("ERROR f3=%b br=%b a=%h b=%h : obtenido=%b esperado=%b",
                             t_f3, t_br, t_a, t_b, taken, expected);
            end
        end
    endtask

    reg [31:0] edge_val [0:9];

    initial begin
        errors = 0;
        checks = 0;

        edge_val[0] = 32'h0000_0000;
        edge_val[1] = 32'h0000_0001;
        edge_val[2] = 32'hFFFF_FFFF;   // -1 con signo, maximo sin signo
        edge_val[3] = 32'h8000_0000;   // minimo con signo
        edge_val[4] = 32'h7FFF_FFFF;   // maximo con signo
        edge_val[5] = 32'h0000_0002;
        edge_val[6] = 32'hFFFF_FFFE;   // -2
        edge_val[7] = 32'h8000_0001;
        edge_val[8] = 32'hAAAA_AAAA;
        edge_val[9] = 32'h5555_5555;

        // 1) Todos los funct3 x todos los pares borde x branch 0 / 1
        for (f = 0; f < 8; f = f + 1)
            for (i = 0; i < 10; i = i + 1)
                for (j = 0; j < 10; j = j + 1) begin
                    check(f[2:0], edge_val[i], edge_val[j], 1'b1);
                    check(f[2:0], edge_val[i], edge_val[j], 1'b0);
                end

        // 2) Aleatorios (la mitad con a == b)
        for (f = 0; f < 8; f = f + 1)
            for (i = 0; i < 2000; i = i + 1) begin
                ra = $urandom;
                rb = (i % 2 == 0) ? ra : $urandom;
                check(f[2:0], ra, rb, 1'b1);
                check(f[2:0], ra, rb, 1'b0);
            end

        // 3) Casos puntuales para mirar en la forma de onda
        check(F3_BEQ,  32'd5,         32'd5,  1'b1);    // 1
        check(F3_BNE,  32'd5,         32'd5,  1'b1);    // 0
        check(F3_BLT,  32'hFFFF_FFFF, 32'd1,  1'b1);    // 1  (-1 < 1 con signo)
        check(F3_BLTU, 32'hFFFF_FFFF, 32'd1,  1'b1);    // 0  (4294967295 > 1 sin signo)
        check(F3_BGE,  32'd1,         32'd1,  1'b1);    // 1
        check(F3_BGEU, 32'd0,         32'd1,  1'b1);    // 0
        check(F3_BEQ,  32'd5,         32'd5,  1'b0);    // 0  (no es branch)

        $display("----------------------------------------");
        $display("Chequeos: %0d   Errores: %0d", checks, errors);
        if (errors == 0) $display("BRANCH_CMP TEST: PASSED");
        else             $display("BRANCH_CMP TEST: FAILED");
        $display("----------------------------------------");
        $finish;
    end
endmodule
