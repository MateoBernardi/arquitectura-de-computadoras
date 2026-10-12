`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/12/2026 04:32:19 PM
// Design Name: 
// Module Name: if_stage
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


// Instruction Fetch stage: PC register + IMEM
// pc_next is driven by the branch/jump logic (just PC+4 for now)
module if_stage (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] pc_next,   // next PC (PC+4 or branch target)
    output wire [31:0] pc,        // current PC
    output wire [31:0] instr      // fetched instruction
);
    pc   pc_reg  (.clk(clk), .rst(rst), .pc_next(pc_next), .pc(pc));
    imem imem_mod(.addr(pc), .instr(instr));
endmodule
