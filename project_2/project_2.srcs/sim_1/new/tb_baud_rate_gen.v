`timescale 1ns / 1ps

module tb_baud_rate_gen();

    // Clock parameters (100 MHz -> Period = 10 ns)
    localparam CLK_PERIOD = 10;
    localparam CLK_FREQ   = 100_000_000;
    localparam BAUD_RATE  = 19_200;
    
    // Expected period between ticks in nanoseconds:
    // T_tick = 1 / (BAUD_RATE * 16)
    // For 19200 baud -> 1 / 307200 s ~= 3.255 us = 3255 ns

    reg  clk;
    reg  reset;
    wire tick;

    // Clock generation: 100 MHz
    always begin
        #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Unit Under Test (UUT)
    baud_rate_gen
    #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    )
    uut (
        .i_clk(clk),
        .i_reset(reset),
        .o_tick(tick)
    );

    // Test sequence
    initial begin
        // Initialize signals
        clk   = 0;
        reset = 1;

        // Hold reset for 100 ns
        #100;
        @(posedge clk);
        reset = 0;

        // Run simulation long enough to observe multiple ticks
        // Each tick occurs roughly every 3.25 us
        #20000; // 20 microseconds

        $finish;
    end

endmodule