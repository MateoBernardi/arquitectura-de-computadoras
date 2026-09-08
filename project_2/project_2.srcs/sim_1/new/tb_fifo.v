`timescale 1ns/1ps
module tb_fifo;
    localparam NB_DATA   = 8;
    localparam PTR_LEN   = 3;
    localparam DEPTH     = 1 << PTR_LEN;
    localparam N_CYCLES  = 500;

    reg  clk = 0;
    reg  reset = 1;
    reg  read_fifo = 0;
    reg  write_fifo = 0;
    reg  [NB_DATA-1:0] data_to_write = 0;
    wire fifo_empty, fifo_full;
    wire [NB_DATA-1:0] data_to_read;

    always #5 clk = ~clk;

    fifo #(.NB_DATA(NB_DATA), .PTR_LEN(PTR_LEN)) DUT (
        .i_clk          (clk),
        .i_reset        (reset),
        .i_read_fifo    (read_fifo),
        .i_write_fifo   (write_fifo),
        .i_data_to_write(data_to_write),
        .o_fifo_is_empty(fifo_empty),
        .o_fifo_is_full (fifo_full),
        .o_data_to_read (data_to_read)
    );

    // reference model: plain array queue
    reg [NB_DATA-1:0] ref_mem [0:DEPTH-1];
    integer ref_wp, ref_rp, ref_count;
    reg [NB_DATA-1:0] expect_data;

    integer errors = 0;
    integer i;

    initial begin
        ref_wp = 0; ref_rp = 0; ref_count = 0;

        @(negedge clk);
        reset = 0;
        @(negedge clk);

        for (i = 0; i < N_CYCLES; i = i + 1) begin
            // check against the state the DUT is holding right now
            // (result of whatever was applied last cycle)
            if (fifo_empty !== (ref_count == 0)) begin
                $display("FAIL @%0t: empty=%b expected=%b", $time, fifo_empty, ref_count == 0);
                errors = errors + 1;
            end
            if (fifo_full !== (ref_count == DEPTH)) begin
                $display("FAIL @%0t: full=%b expected=%b", $time, fifo_full, ref_count == DEPTH);
                errors = errors + 1;
            end
            if (ref_count > 0 && data_to_read !== ref_mem[ref_rp]) begin
                $display("FAIL @%0t: data_to_read=%h expected=%h", $time, data_to_read, ref_mem[ref_rp]);
                errors = errors + 1;
            end

            // pick this cycle's stimulus and fold it into the reference model
            write_fifo    = ($random % 3 != 0) && (ref_count < DEPTH);
            data_to_write = $random;
            read_fifo     = ($random % 3 != 0) && (ref_count > 0);

            if (write_fifo) begin
                ref_mem[ref_wp] = data_to_write;
                ref_wp = (ref_wp + 1) % DEPTH;
                ref_count = ref_count + 1;
            end
            if (read_fifo) begin
                ref_rp = (ref_rp + 1) % DEPTH;
                ref_count = ref_count - 1;
            end

            @(negedge clk);
        end

        if (errors == 0) $display("ALL PASS (%0d random cycles)", N_CYCLES);
        else $display("%0d FAILURE(S) out of %0d cycles", errors, N_CYCLES);
        $finish;
    end
endmodule