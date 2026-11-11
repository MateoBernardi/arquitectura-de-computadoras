`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// alu_tb: testbench autoverificable de alu_tp1 (32 bits, codigos de 4 bits)
//
// - Modelo de referencia escrito con otras expresiones que la ALU (SLT, SLTU y
//   SRA no usan $signed ni >>>), para no repetir el mismo error en los dos.
// - Prueba cada operacion con todos los pares de valores borde y con valores
//   aleatorios, incluida la cantidad de shift > 31 (solo cuentan los 5 bits
//   bajos de b).
// - Verifica tambien los flags: o_z (resultado = 0) y o_o (overflow de ADD / SUB).
// - Codigo de operacion no definido: el resultado tiene que ser 0.
// - Al final imprime "ALU TEST: PASSED" o la cantidad de errores.
// -----------------------------------------------------------------------------
module tb_alu;
    `include "riscv_defs.vh"                            // ALU_* (los codigos que genera control_unit)

    localparam [3:0] NOR_CODE = 4'b1011;                // OP_NOR de alu_ops.vh

    reg  [31:0] a, b;
    reg  [3:0]  op;
    wire [31:0] result;
    wire        z, ovf;

    integer errors;
    integer checks;
    integer i, j, k;

    alu_tp1 #(.NB_DATA(32), .NB_OP(4)) dut (
        .i_data_a (a),
        .i_data_b (b),
        .i_data_op(op),
        .o_data   (result),
        .o_z      (z),
        .o_o      (ovf)
    );

    // Modelo de referencia
    function [31:0] ref_alu;
        input [3:0]  f_op;
        input [31:0] f_a;
        input [31:0] f_b;
        reg   [4:0]  s;
        reg          lt;
        begin
            s = f_b[4:0];
            case (f_op)
                ALU_ADD:  ref_alu = f_a + f_b;
                ALU_SUB:  ref_alu = f_a + (~f_b) + 32'd1;
                ALU_SLL:  ref_alu = f_a << s;
                ALU_SLT:  begin
                    if (f_a[31] != f_b[31]) lt = f_a[31];   // signos distintos: el negativo es menor
                    else                    lt = (f_a < f_b);
                    ref_alu = {31'd0, lt};
                end
                ALU_SLTU: ref_alu = {31'd0, (f_a < f_b)};
                ALU_XOR:  ref_alu = (f_a & ~f_b) | (~f_a & f_b);
                ALU_SRL:  ref_alu = f_a >> s;
                ALU_SRA:  ref_alu = (f_a >> s) | (f_a[31] ? ~(32'hFFFF_FFFF >> s) : 32'd0);
                ALU_OR:   ref_alu = f_a | f_b;
                ALU_AND:  ref_alu = f_a & f_b;
                NOR_CODE: ref_alu = ~(f_a | f_b);
                default:  ref_alu = 32'd0;
            endcase
        end
    endfunction

    task check;
        input [3:0]  t_op;
        input [31:0] t_a;
        input [31:0] t_b;
        reg   [31:0] expected;
        reg          exp_z;
        reg          exp_o;
        begin
            op = t_op; a = t_a; b = t_b;
            #1;
            expected = ref_alu(t_op, t_a, t_b);
            exp_z    = (expected == 32'd0);
            exp_o    = 1'b0;
            if (t_op == ALU_ADD) exp_o = (t_a[31] == t_b[31]) && (expected[31] != t_a[31]);
            if (t_op == ALU_SUB) exp_o = (t_a[31] != t_b[31]) && (expected[31] != t_a[31]);
            checks = checks + 1;
            if (result !== expected || z !== exp_z || ovf !== exp_o) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("ERROR op=%b a=%h b=%h : obtenido=%h z=%b o=%b  esperado=%h z=%b o=%b",
                             t_op, t_a, t_b, result, z, ovf, expected, exp_z, exp_o);
            end
        end
    endtask

    // Valores borde y operaciones
    reg [31:0] edge_val [0:9];
    reg [3:0]  ops      [0:10];

    initial begin
        errors = 0;
        checks = 0;

        edge_val[0] = 32'h0000_0000;
        edge_val[1] = 32'h0000_0001;
        edge_val[2] = 32'hFFFF_FFFF;
        edge_val[3] = 32'h8000_0000;
        edge_val[4] = 32'h7FFF_FFFF;
        edge_val[5] = 32'h0000_001F;   // shift 31
        edge_val[6] = 32'h0000_0020;   // shift 32 -> cuenta como 0
        edge_val[7] = 32'hFFFF_FFE1;   // [4:0] = 1
        edge_val[8] = 32'hAAAA_AAAA;
        edge_val[9] = 32'h5555_5555;

        ops[0] = ALU_ADD;  ops[1] = ALU_SUB;  ops[2] = ALU_SLL;  ops[3] = ALU_SLT;
        ops[4] = ALU_SLTU; ops[5] = ALU_XOR;  ops[6] = ALU_SRL;  ops[7] = ALU_SRA;
        ops[8] = ALU_OR;   ops[9] = ALU_AND;  ops[10] = NOR_CODE;

        // 1) Todas las operaciones x todos los pares de valores borde
        for (k = 0; k < 11; k = k + 1)
            for (i = 0; i < 10; i = i + 1)
                for (j = 0; j < 10; j = j + 1)
                    check(ops[k], edge_val[i], edge_val[j]);

        // 2) Aleatorios
        for (k = 0; k < 11; k = k + 1)
            for (i = 0; i < 2000; i = i + 1)
                check(ops[k], $urandom, $urandom);

        // 3) Codigos no definidos -> 0
        check(4'b1001, 32'h1234_5678, 32'h0000_0001);
        check(4'b1010, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        check(4'b1100, 32'h0000_0001, 32'h0000_0001);
        check(4'b1110, 32'h0000_0001, 32'h0000_0001);
        check(4'b1111, 32'h0000_0001, 32'h0000_0001);

        // 4) Casos puntuales para mirar en la forma de onda
        check(ALU_ADD,  32'd5,         32'd3);          // 8
        check(ALU_SUB,  32'd5,         32'd7);          // FFFFFFFE (-2)
        check(ALU_SLT,  32'hFFFF_FFFF, 32'd1);          // 1  (-1 < 1)
        check(ALU_SLTU, 32'hFFFF_FFFF, 32'd1);          // 0
        check(ALU_SRA,  32'h8000_0000, 32'd4);          // F8000000
        check(ALU_SRL,  32'h8000_0000, 32'd4);          // 08000000
        check(ALU_SLL,  32'd1,         32'd31);         // 80000000

        $display("----------------------------------------");
        $display("Chequeos: %0d   Errores: %0d", checks, errors);
        if (errors == 0) $display("ALU TEST: PASSED");
        else             $display("ALU TEST: FAILED");
        $display("----------------------------------------");
        $finish;
    end
endmodule
