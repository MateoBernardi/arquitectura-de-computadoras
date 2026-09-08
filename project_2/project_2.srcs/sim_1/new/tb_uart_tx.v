`timescale 1ns/1ps
module tb_uart_tx;
    localparam NB_DATA  = 8;
    localparam N_TICKS  = 16;
    localparam N_BYTES  = 30;

    reg  clk = 0;
    reg  reset = 1;
    reg  tx_ready = 0;
    reg  [NB_DATA-1:0] din = 0;
    reg  tick = 0;
    wire tx_done;
    wire tx;

    always #5 clk = ~clk;

    integer tick_cnt = 0;
    always @(posedge clk) begin
        if (tick_cnt == 3) begin
            tick     <= 1'b1;
            tick_cnt <= 0;
        end else begin
            tick     <= 1'b0;
            tick_cnt <= tick_cnt + 1;
        end
    end
    localparam CYCLES_PER_TICK = 4;
    localparam CYCLES_PER_BIT  = CYCLES_PER_TICK * N_TICKS;
    localparam NS_PER_BIT      = CYCLES_PER_BIT * 10;

    uart_tx #(.NB_DATA(NB_DATA), .N_TICKS(N_TICKS)) DUT (
        .i_clk(clk), .i_reset(reset), .i_tx_ready(tx_ready), .i_tick(tick),
        .i_din(din), .o_tx_done(tx_done), .o_tx(tx)
    );

    // background decoder: waits for a start bit, samples mid-bit, LSB first
    reg [NB_DATA-1:0] decoded;
    reg decoded_flag;
    integer k;
    initial begin
        decoded_flag = 0;
        forever begin
            @(negedge tx);
            #(NS_PER_BIT/2);
            for (k = 0; k < NB_DATA; k = k + 1) begin
                #(NS_PER_BIT);
                decoded = {tx, decoded[NB_DATA-1:1]};
            end
            decoded_flag = 1'b1;
            #(NS_PER_BIT/2);
        end
    end

    integer errors = 0;
    integer j;
    reg [NB_DATA-1:0] expected;

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

    initial begin
        @(negedge clk); reset = 0;
        repeat (5) @(negedge clk);

        for (j = 0; j < N_BYTES; j = j + 1) begin
            expected     = $random;
            decoded_flag = 1'b0;
            din          = expected;
            @(negedge clk); tx_ready = 1'b1;
            @(negedge clk); tx_ready = 1'b0;

            wait (decoded_flag);
            #1;
            if (decoded !== expected) begin
                $display("FAIL byte %0d: got %h expected %h", j, decoded, expected);
                errors = errors + 1;
            end
            wait (tx_done);
            repeat (5) @(negedge clk); // idle gap between frames
        end

        if (errors == 0) $display("ALL PASS (%0d random bytes)", N_BYTES);
        else $display("%0d FAILURE(S) out of %0d bytes", errors, N_BYTES);
        $finish;
    end
endmodule