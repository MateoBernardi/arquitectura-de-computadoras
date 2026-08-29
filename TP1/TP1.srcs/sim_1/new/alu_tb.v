module tb_alu;

    parameter NB_DATA = 8;
    parameter NB_OP   = 6;
    
    `include "alu_ops.vh"
    `include "model.vh"

    parameter NUM_RANDOM_PER_OP = 50; 
    parameter VERBOSE           = 0;

    reg  signed [NB_DATA-1:0] tb_i_data_a;
    reg  signed [NB_DATA-1:0] tb_i_data_b;
    reg         [NB_OP-1:0]   tb_i_data_op;
    wire signed [NB_DATA-1:0] tb_o_data;
    wire                      tb_o_z;
    wire                      tb_o_o;

    alu_tp1 
    #(
        .NB_DATA (NB_DATA),
        .NB_OP   (NB_OP)
    ) 
    uut(
        .i_data_a  (tb_i_data_a),
        .i_data_b  (tb_i_data_b),
        .i_data_op (tb_i_data_op),
        .o_data    (tb_o_data),
        .o_z       (tb_o_z),
        .o_o       (tb_o_o)
    );

    integer rnd_seed   = 32'hC0FFEE;
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    reg [NB_OP-1:0] op_list [0:7];

    localparam signed [NB_DATA-1:0] MAX_POS = {1'b0, {(NB_DATA-1){1'b1}}};
    localparam signed [NB_DATA-1:0] MIN_NEG = {1'b1, {(NB_DATA-1){1'b0}}};

    task automatic run_test;
        input signed [NB_DATA-1:0] a;
        input signed [NB_DATA-1:0] b;
        input        [NB_OP-1:0]   op;
        reg signed [NB_DATA-1:0] exp_data;
        reg                      exp_zero;
        reg                      exp_ovf;
        begin
            tb_i_data_a  = a;
            tb_i_data_b  = b;
            tb_i_data_op = op;
            #10;

            alu_model(a, b, op, exp_data, exp_zero, exp_ovf);

            test_count = test_count + 1;
            if (tb_o_data !== exp_data || tb_o_z !== exp_zero || tb_o_o !== exp_ovf) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d op=%b A=%0d B=%0d -> o_data=%0d (esp %0d)  o_z=%b (esp %b)  o_o=%b (esp %b)",
                          test_count, op, a, b, tb_o_data, exp_data, tb_o_z, exp_zero, tb_o_o, exp_ovf);
            end else begin
                pass_count = pass_count + 1;
                if (VERBOSE)
                    $display("[ OK ] #%0d op=%b A=%0d B=%0d -> o_data=%0d o_z=%b o_o=%b",
                              test_count, op, a, b, tb_o_data, tb_o_z, tb_o_o);
            end
        end
    endtask

    integer i, j;

    initial begin
        run_test(10, 20, OP_ADD);                            // ADD normal
        run_test(MAX_POS, 1, OP_ADD);                        // ADD overflow positivo
        run_test(MIN_NEG, -1, OP_ADD);                       // ADD overflow negativo

        run_test(20, 10, OP_SUB);                            // SUB normal
        run_test(MIN_NEG, 1, OP_SUB);                        // SUB overflow (neg - pos)
        run_test(MAX_POS, -1, OP_SUB);                       // SUB overflow (pos - neg)
        run_test(42, 42, OP_SUB);                            // resultado 0 -> o_z=1

        run_test(8'sb11110000, 8'sb10101010, OP_AND);        // AND (patron tipo ejemplo original)
        run_test({NB_DATA{1'b1}}, {NB_DATA{1'b0}}, OP_OR);   // OR con todo 0
        run_test(37, 37, OP_XOR);                            // A^A = 0
        run_test({NB_DATA{1'b0}}, {NB_DATA{1'b0}}, OP_NOR);  // NOR(0,0) = todo 1

        run_test(MIN_NEG, 1, OP_SRA);                        // SRA: extiende signo
        run_test(MIN_NEG, 1, OP_SRL);                        // SRL: NO extiende signo
        run_test(-1, 0, OP_SRA);                             // shift 0 -> igual a la entrada
        run_test(MIN_NEG, NB_DATA-1, OP_SRA);                // shift casi completo

        run_test(5, 5, 6'b111111);                           // opcode invalido -> default

        for (i = 0; i < 8; i = i + 1) begin
            for (j = 0; j < NUM_RANDOM_PER_OP; j = j + 1) begin
                if (op_list[i] == OP_SRA || op_list[i] == OP_SRL)
                    run_test($random(rnd_seed), rand_range(0, NB_DATA-1), op_list[i]);
                else
                    run_test($random(rnd_seed), $random(rnd_seed), op_list[i]);
            end
        end

        // ------------------- Resumen -------------------
        $display("==========================================================");
        $display(" %0d tests | %0d OK | %0d FALLADOS", test_count, pass_count, fail_count);
        if (fail_count == 0)
            $display(" RESULTADO: PASS");
        else
            $display(" RESULTADO: FAIL");
        $display("==========================================================");

        $finish;
    end

endmodule