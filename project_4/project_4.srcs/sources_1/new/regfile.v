`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/12/2026 04:33:07 PM
// Design Name: 
// Module Name: regfile
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// RISC-V Register File: 32 × 32-bit registers
// 2 asynchronous read ports, 1 synchronous write port
// x0 (index 0) always reads as zero - writes to x0 are ignored
module regfile (
    input  wire        clk,
    input  wire        we,          // write enable
    input  wire [4:0]  waddr,       // write address (rd)
    input  wire [31:0] wdata,       // write data
    input  wire [4:0]  raddr1,      // read address 1 (rs1)
    output wire [31:0] rdata1,      // read data 1
    input  wire [4:0]  raddr2,      // read address 2 (rs2)
    output wire [31:0] rdata2       // read data 2
);
    reg [31:0] regs [0:31];
    integer i;
    initial for(i=0;i<32;i=i+1) regs[i]=32'b0; // power-on reset all zero

    // synchronous write - x0 stays zero (waddr==0 is ignored)
    always @(posedge clk)
        if (we && waddr != 5'd0) regs[waddr] <= wdata;

    // asynchronous reads - x0 always returns 0
    assign rdata1 = (raddr1 == 5'd0) ? 32'd0 : regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'd0 : regs[raddr2];
endmodule
