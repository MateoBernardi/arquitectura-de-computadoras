`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 05:44:17 PM
// Design Name: 
// Module Name: flush_unit
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

// flush_unit.v - Inserts NOP bubbles on branch taken
// When branch_taken is asserted, the two instructions that entered
// IF and ID after the branch must be flushed.
module flush_unit (
    input  branch_taken,
    output flush_if_id,   // flush IF/ID register (the instr after branch)
    output flush_id_ex    // flush ID/EX register (two after branch)
);
    // Both stages get a bubble simultaneously when branch is taken
    assign flush_if_id = branch_taken;
    assign flush_id_ex = branch_taken;
endmodule
