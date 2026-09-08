`timescale 1ns/1ps
module tb_top;
    localparam CLK_FREQ  = 6400;
    localparam BAUD_RATE = 100;
    localparam N_TICKS   = 16;
    localparam N_TRANS   = 15;

    `include "model.vh"

    reg clk = 0;
    reg reset = 1;
    reg rx = 1;
    wire tx;

    always #5 clk = ~clk;

    top #(
        .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE),
        .NB_DATA(8), .NB_OPCODE(6), .N_TICKS(N_TICKS), .PTR_LEN(2)
    ) DUT (
        .i_clk(clk), .i_reset(reset), .i_rx(rx), .o_tx(tx)
    );

    localparam MODULUS    = CLK_FREQ / (BAUD_RATE * N_TICKS);
    localparam CYCLES_BIT = MODULUS * N_TICKS;
    localparam NS_BIT     = CYCLES_BIT * 10;

    task send_byte(input [7:0] b);
        integer i;
        begin
            @(negedge clk);
            rx = 1'b0;
            repeat (CYCLES_BIT) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];
                repeat (CYCLES_BIT) @(negedge clk);
            end
            rx = 1'b1;
            repeat (CYCLES_BIT) @(negedge clk);
        end
    endtask

    reg [7:0] got_byte;
    reg       got_flag;
    integer   k;
    initial begin
        got_flag = 0;
        forever begin
            @(negedge tx);
            #(NS_BIT/2);
            for (k = 0; k < 8; k = k + 1) begin
                #(NS_BIT);
                got_byte = {tx, got_byte[7:1]};
            end
            got_flag = 1'b1;
            #(NS_BIT/2);
        end
    end

    reg [5:0] valid_ops [0:7];
    initial begin
        valid_ops[0] = OP_ADD; valid_ops[1] = OP_SUB;
        valid_ops[2] = OP_AND; valid_ops[3] = OP_OR;
        valid_ops[4] = OP_XOR; valid_ops[5] = OP_SRA;
        valid_ops[6] = OP_SRL; valid_ops[7] = OP_NOR;
    end

    integer errors = 0;
    integer t;
    reg [5:0] op_sent;
    reg signed [7:0] a_sent, b_sent;
    reg [7:0] expected;

    initial begin #6_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

    initial begin
        #23 reset = 0;
        repeat (5) @(negedge clk);

        for (t = 0; t < N_TRANS; t = t + 1) begin
            op_sent  = valid_ops[$random % 8];
            a_sent   = $random;
            b_sent   = $random;
            expected = golden_alu(a_sent, b_sent, op_sent);
            got_flag = 1'b0;

            send_byte({2'b00, op_sent});
            send_byte(a_sent);
            send_byte(b_sent);

            wait (got_flag);
            #1;
            if (got_byte !== expected) begin
                $display("FAIL trans %0d: op=%b a=%0d b=%0d got=%h expected=%h",
                          t, op_sent, a_sent, b_sent, got_byte, expected);
                errors = errors + 1;
            end
            repeat (10) @(negedge clk);
        end

        if (errors == 0) $display("ALL PASS (%0d random transactions)", N_TRANS);
        else $display("%0d FAILURE(S) out of %0d transactions", errors, N_TRANS);
        $finish;
    end
endmodule