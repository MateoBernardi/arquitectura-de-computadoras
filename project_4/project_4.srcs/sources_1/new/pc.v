`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/12/2026 04:29:02 PM
// Design Name: 
// Module Name: pc
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


// Program Counter - 32-bit register, synchronous reset
module pc (
    input  wire        clk,      // clock
    input  wire        rst,      // synchronous reset (active high)
    input  wire        en,       // 0 = hold (stall / CPU paused)
    input  wire [31:0] pc_next,  // next PC value (PC+4 or branch target)
    output reg  [31:0] pc        // current PC value → IMEM address
);
    always @(posedge clk) begin
        if (rst) pc <= 32'h0000_0000;
        else if (en) pc <= pc_next;
    end
endmodule
