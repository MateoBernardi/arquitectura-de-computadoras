`timescale 1ns / 1ps

module tb_top;

    parameter NB_DATA   = 8;
    parameter NB_OP     = 6;
    parameter NB_BITS   = 8;
    parameter NB_BUTTON = 3;

    parameter NUM_RANDOM_PER_OP = 20;
    parameter VERBOSE           = 0;
    
    `include "alu_ops.vh"
    `include "model.vh"

    localparam [NB_BUTTON-1:0] BTN_NONE    = 3'b000;
    localparam [NB_BUTTON-1:0] BTN_DATA_A  = 3'b001;
    localparam [NB_BUTTON-1:0] BTN_DATA_B  = 3'b010;
    localparam [NB_BUTTON-1:0] BTN_DATA_OP = 3'b100;

    reg  [NB_BITS-1:0]       switch;
    reg  [NB_BUTTON-1:0]     button;
    reg                      i_clk;
    wire signed [NB_DATA-1:0] led;
    wire                      f_o;
    wire                      f_z;

    top 
    #(
        .NB_DATA   (NB_DATA),
        .NB_BITS   (NB_BITS),
        .NB_OP     (NB_OP),
        .NB_BUTTON (NB_BUTTON)
    ) 
    uut (
        .switch (switch),
        .button (button),
        .i_clk  (i_clk),
        .led    (led),
        .f_o    (f_o),
        .f_z    (f_z)
    );

    always begin
        i_clk = 0; #10;
        i_clk = 1; #10;
    end

    integer rnd_seed   = 32'hFACADA;
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    reg [NB_OP-1:0] op_list [0:7];

    localparam signed [NB_DATA-1:0] MAX_POS = {1'b0, {(NB_DATA-1){1'b1}}};
    localparam signed [NB_DATA-1:0] MIN_NEG = {1'b1, {(NB_DATA-1){1'b0}}};

    task automatic press_button;
        input [NB_BUTTON-1:0] btn;
        input [NB_BITS-1:0]   value;
        begin
            @(negedge i_clk);
            switch = value;
            button = btn;
            @(posedge i_clk); 
            @(negedge i_clk);
            button = BTN_NONE;
        end
    endtask

    task automatic run_test;
        input signed [NB_DATA-1:0] a;
        input signed [NB_DATA-1:0] b;
        input        [NB_OP-1:0]   op;
        reg signed [NB_DATA-1:0] exp_data;
        reg                      exp_zero;
        reg                      exp_ovf;
        begin
            press_button(BTN_DATA_A,  a);
            press_button(BTN_DATA_B,  b);
            press_button(BTN_DATA_OP, op);
            #1;

            alu_model(a, b, op, exp_data, exp_zero, exp_ovf);

            test_count = test_count + 1;
            if (led !== exp_data || f_z !== exp_zero || f_o !== exp_ovf) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d op=%b A=%0d B=%0d -> led=%0d (esp %0d)  f_z=%b (esp %b)  f_o=%b (esp %b)",
                          test_count, op, a, b, led, exp_data, f_z, exp_zero, f_o, exp_ovf);
            end else begin
                pass_count = pass_count + 1;
                if (VERBOSE)
                    $display("[ OK ] #%0d op=%b A=%0d B=%0d -> led=%0d f_z=%b f_o=%b",
                              test_count, op, a, b, led, f_z, f_o);
            end
        end
    endtask

    integer i, j;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        switch = 0;
        button = BTN_NONE;

        op_list[0] = OP_ADD; op_list[1] = OP_SUB; op_list[2] = OP_AND; op_list[3] = OP_OR;
        op_list[4] = OP_XOR; op_list[5] = OP_SRA; op_list[6] = OP_SRL; op_list[7] = OP_NOR;

        @(negedge i_clk); 

        $display("==========================================================");
        $display(" TB_TOP - probando top (NB_DATA=%0d, NB_OP=%0d, NB_BITS=%0d)", NB_DATA, NB_OP, NB_BITS);
        $display("==========================================================");

        run_test(10, 20, OP_ADD);
        run_test(MAX_POS, 1, OP_ADD);
        run_test(MIN_NEG, -1, OP_ADD);

        run_test(20, 10, OP_SUB);
        run_test(MIN_NEG, 1, OP_SUB);
        run_test(MAX_POS, -1, OP_SUB);
        run_test(42, 42, OP_SUB);

        run_test(8'sb11110000, 8'sb10101010, OP_AND);
        run_test({NB_DATA{1'b1}}, {NB_DATA{1'b0}}, OP_OR);
        run_test(37, 37, OP_XOR);
        run_test({NB_DATA{1'b0}}, {NB_DATA{1'b0}}, OP_NOR);

        run_test(MIN_NEG, 1, OP_SRA);
        run_test(MIN_NEG, 1, OP_SRL);
        run_test(-1, 0, OP_SRA);

        run_test(5, 5, 6'b111111); 

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