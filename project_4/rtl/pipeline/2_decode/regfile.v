`timescale 1ns / 1ps

module regfile #(
    parameter BYPASS = 0            // 1 = write-through (needed by the pipeline; would form a
                                    // combinational loop in the single-cycle core)
) (
    input  wire        clk,
    input  wire        rst,         // synchronous: clears x1..x31
    input  wire        we,          // write enable
    input  wire [4:0]  waddr,       // write address (rd)
    input  wire [31:0] wdata,       // write data
    input  wire [4:0]  raddr1,      // read address 1 (rs1)
    output wire [31:0] rdata1,      // read data 1
    input  wire [4:0]  raddr2,      // read address 2 (rs2)
    output wire [31:0] rdata2,      // read data 2
    input  wire [4:0]  dbg_addr,    // debug read port
    output wire [31:0] dbg_data
);
    reg [31:0] regs [0:31];
    integer i;
    initial for(i=0;i<32;i=i+1) regs[i]=32'b0; // power-on reset all zero

    // synchronous write - x0 stays zero (waddr==0 is ignored)
    always @(posedge clk)
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) regs[i] <= 32'b0;
        end
        else if (we && waddr != 5'd0) regs[waddr] <= wdata;

    // asynchronous reads - x0 always returns 0. Internal bypass: a write in the
    // same cycle (WB stage) is visible to the read (ID stage).
    wire wr = we && (waddr != 5'd0);
    assign rdata1   = (raddr1 == 5'd0) ? 32'd0 : (BYPASS && wr && waddr == raddr1) ? wdata : regs[raddr1];
    assign rdata2   = (raddr2 == 5'd0) ? 32'd0 : (BYPASS && wr && waddr == raddr2) ? wdata : regs[raddr2];
    assign dbg_data = regs[dbg_addr];
endmodule
