`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/12/2026 04:30:53 PM
// Design Name: 
// Module Name: imem
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

// Instruction Memory - combinational ROM, word-addressed
// Holds up to 256 instructions (1 KB). Pre-load with $readmemh.
module imem #(parameter DEPTH = 256) (
    input  wire [31:0] addr,   // byte address from PC
    output wire [31:0] instr   // 32-bit instruction word
);
    reg [31:0] mem [0:DEPTH-1];

    // Load program at simulation start.
    // Replace "program.hex" with the actual UART programming here.
    initial $readmemh("program.mem", mem);

    // Word-aligned read: divide byte address by 4
    assign instr = mem[addr[31:2]];
endmodule
