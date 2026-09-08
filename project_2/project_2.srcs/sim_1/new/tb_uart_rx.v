`timescale 1ns/1ps
module tb_uart_rx;
    localparam NB_DATA  = 8;
    localparam N_TICKS  = 16;
    localparam N_BYTES  = 30;

    reg  clk = 0;
    reg  reset = 1;
    reg  rx = 1;
    reg  tick = 0;
    wire rx_done;
    wire [NB_DATA-1:0] dout;

    always #5 clk = ~clk;

    // free-running tick, one pulse every 4 clk cycles (arbitrary, just needs
    // to be periodic -- uart_rx doesn't care about real baud timing)
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

    uart_rx #(.NB_DATA(NB_DATA), .N_TICKS(N_TICKS)) DUT (
        .i_clk(clk), .i_reset(reset), .i_rx(rx), .i_tick(tick),
        .o_rx_done(rx_done), .o_dout(dout)
    );

    task send_byte(input [NB_DATA-1:0] b);
        integer i;
        begin
            @(negedge clk);
            rx = 1'b0;
            repeat (CYCLES_PER_BIT) @(negedge clk);
            for (i = 0; i < NB_DATA; i = i + 1) begin
                rx = b[i];
                repeat (CYCLES_PER_BIT) @(negedge clk);
            end
            rx = 1'b1;
            repeat (CYCLES_PER_BIT) @(negedge clk);
        end
    endtask

    integer errors = 0;
    integer j;
    reg [NB_DATA-1:0] expected;
    reg done_seen;
    reg [NB_DATA-1:0] captured;

    always @(posedge clk) begin
        if (rx_done) begin
            done_seen <= 1'b1;
            captured  <= dout;
        end
    end

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

    initial begin
        @(negedge clk); reset = 0;
        repeat (5) @(negedge clk);

        for (j = 0; j < N_BYTES; j = j + 1) begin
            expected  = $random;
            done_seen = 1'b0;
            send_byte(expected);
            // stop bit just finished; give it a couple cycles margin
            repeat (3) @(negedge clk);
            if (!done_seen) begin
                $display("FAIL byte %0d: o_rx_done never asserted (sent %h)", j, expected);
                errors = errors + 1;
            end else if (captured !== expected) begin
                $display("FAIL byte %0d: got %h expected %h", j, captured, expected);
                errors = errors + 1;
            end
            repeat (5) @(negedge clk); // idle gap between frames
        end

        if (errors == 0) $display("ALL PASS (%0d random bytes)", N_BYTES);
        else $display("%0d FAILURE(S) out of %0d bytes", errors, N_BYTES);
        $finish;
    end
endmodule