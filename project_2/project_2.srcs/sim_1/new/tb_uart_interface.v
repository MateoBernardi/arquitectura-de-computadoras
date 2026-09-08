`timescale 1ns/1ps
module tb_uart_interface;
    localparam NB_DATA   = 8;
    localparam NB_OPCODE = 6;
    localparam PTR_LEN   = 3;
    localparam N_TRANS   = 40;

    `include "model.vh"

    reg clk = 0;
    reg reset = 1;
    always #5 clk = ~clk;

    // rx-side: a real fifo, fed directly (standing in for uart_rx + write glue)
    reg        rx_write = 0;
    reg  [7:0] rx_wdata  = 0;
    wire       rx_empty, rx_read;
    wire [7:0] rx_rdata;

    fifo #(.NB_DATA(NB_DATA), .PTR_LEN(PTR_LEN)) RXFIFO (
        .i_clk(clk), .i_reset(reset),
        .i_read_fifo(rx_read), .i_write_fifo(rx_write),
        .i_data_to_write(rx_wdata),
        .o_fifo_is_empty(rx_empty), .o_fifo_is_full(),
        .o_data_to_read(rx_rdata)
    );

    // tx-side: observed directly, no fifo needed
    wire       tx_write;
    wire [7:0] tx_wdata;
    reg        tx_full = 0;

    // mock alu: purely combinational, mirrors what a real alu_tp1 would present
    // given whatever the DUT currently has latched on its alu-facing outputs
    wire [NB_OPCODE-1:0] opcode;
    wire [7:0] opA, opB;
    wire [7:0] alu_result = golden_alu(opA, opB, opcode);

    uart_interface #(.NB_DATA(NB_DATA), .NB_OPCODE(NB_OPCODE)) DUT (
        .i_clk(clk), .i_reset(reset),
        .i_alu_result(alu_result),
        .i_data_to_read(rx_rdata),
        .i_fifo_rx_empty(rx_empty),
        .i_fifo_tx_full(tx_full),
        .o_fifo_rx_read(rx_read),
        .o_fifo_tx_write(tx_write),
        .o_data_to_write(tx_wdata),
        .o_alu_opcode(opcode),
        .o_alu_op_A(opA),
        .o_alu_op_B(opB)
    );

    // 8 valid opcodes -- pulled from alu_ops.vh via model.vh's include
    reg [NB_OPCODE-1:0] valid_ops [0:7];
    initial begin
        valid_ops[0] = OP_ADD; valid_ops[1] = OP_SUB;
        valid_ops[2] = OP_AND; valid_ops[3] = OP_OR;
        valid_ops[4] = OP_XOR; valid_ops[5] = OP_SRA;
        valid_ops[6] = OP_SRL; valid_ops[7] = OP_NOR;
    end

    task push_byte(input [7:0] b);
        begin
            @(negedge clk);
            rx_wdata = b;
            rx_write = 1'b1;
            @(negedge clk);
            rx_write = 1'b0;
        end
    endtask

    integer errors = 0;
    integer t;
    reg [NB_OPCODE-1:0] op_sent;
    reg signed [7:0] a_sent, b_sent;
    reg [7:0] expected;

    initial begin #4_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

    initial begin
        @(negedge clk); reset = 0;
        repeat (5) @(negedge clk);

        for (t = 0; t < N_TRANS; t = t + 1) begin
            op_sent = valid_ops[$random % 8];
            a_sent  = $random;
            b_sent  = $random;
            expected = golden_alu(a_sent, b_sent, op_sent);

            push_byte({2'b00, op_sent});
            repeat (6) @(negedge clk);
            push_byte(a_sent);
            repeat (6) @(negedge clk);
            push_byte(b_sent);

            wait (tx_write);
            #1;
            if (tx_wdata !== expected) begin
                $display("FAIL trans %0d: op=%b a=%0d b=%0d got=%h expected=%h",
                          t, op_sent, a_sent, b_sent, tx_wdata, expected);
                errors = errors + 1;
            end
            @(negedge clk);
            repeat (6) @(negedge clk);
        end

        if (errors == 0) $display("ALL PASS (%0d random transactions)", N_TRANS);
        else $display("%0d FAILURE(S) out of %0d transactions", errors, N_TRANS);
        $finish;
    end
endmodule