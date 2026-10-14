`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_pipeline: self-checking test of riscv_pipeline.
// Loads PROG_FILE into imem, runs until o_halt, then compares x0..x31 and the
// first 16 dmem words against EXP_FILE (32 + 16 words, $readmemh format).
// The reference files come from a Python RV32I model (see host/ tests).
// Also checks that nothing after the EBREAK executed (checked through EXP_FILE)
// and that pausing (i_enable=0) freezes the pipeline.
//////////////////////////////////////////////////////////////////////////////////
module tb_pipeline;
    parameter PROG_FILE = "pipeline_prog.hex";
    parameter EXP_FILE  = "pipeline_exp.hex";

    reg clk = 0, rst = 1, en = 0;
    always #5 clk = ~clk;

    wire        halt;
    reg  [15:0] dbg_addr = 0;
    wire [31:0] dbg_data;
    wire [15:0] dbg_count;

    riscv_pipeline #(.IMEM_ADDR_W(10), .IMEM_INIT(PROG_FILE)) dut (
        .clk(clk), .i_rst(rst), .i_enable(en), .o_halt(halt),
        .i_imem_we(1'b0), .i_imem_waddr(10'd0), .i_imem_wdata(8'd0),
        .i_dbg_addr(dbg_addr), .o_dbg_data(dbg_data), .o_dbg_count(dbg_count)
    );

    reg [31:0] exp [0:47];
    integer i, errors, cycles;
    reg [31:0] got;
    reg [31:0] pc_frozen;

    initial begin
        errors = 0;
        $readmemh(EXP_FILE, exp);
        repeat (3) @(posedge clk);
        #1 rst = 0;
        en = 1;
        cycles = 0;
        while (!halt && cycles < 2000) begin
            @(posedge clk); #1;
            cycles = cycles + 1;
            if (cycles == 20) begin                     // pause test
                en = 0; pc_frozen = dut.pc;
                repeat (5) @(posedge clk);
                #1;
                if (dut.pc !== pc_frozen) begin
                    errors = errors + 1; $display("FAIL: PC moved while paused");
                end
                en = 1;
            end
        end
        if (!halt) begin errors = errors + 1; $display("FAIL: timeout, no halt"); end
        else $display("halt after %0d cycles", cycles);
        en = 0;

        for (i = 0; i < 32; i = i + 1) begin
            dbg_addr = 22 + i; #1;
            if (dbg_data !== exp[i]) begin
                errors = errors + 1;
                $display("FAIL x%0d = %h, expected %h", i, dbg_data, exp[i]);
            end
        end
        for (i = 0; i < 16; i = i + 1) begin
            dbg_addr = 54 + i; #1;
            if (dbg_data !== exp[32 + i]) begin
                errors = errors + 1;
                $display("FAIL dmem[%0d] = %h, expected %h", i, dbg_data, exp[32 + i]);
            end
        end
        if (dbg_count !== 86) begin errors = errors + 1; $display("FAIL dbg_count=%0d", dbg_count); end

        if (errors == 0) $display("PASS: tb_pipeline");
        else             $display("FAILED: %0d errors", errors);
        $finish;
    end
endmodule
