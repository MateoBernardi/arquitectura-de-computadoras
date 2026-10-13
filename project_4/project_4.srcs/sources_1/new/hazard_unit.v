`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 05:44:17 PM
// Design Name: 
// Module Name: hazard_unit
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

// hazard_unit.v - Detects load-use hazards and generates stall
// When a load is in EX and the next instruction in ID uses the
// loaded register, we must stall for one cycle.
module hazard_unit (
    input       ex_mem_read, // is EX instruction a load?
    input [4:0] ex_rd,      // load destination register
    input [4:0] id_rs1,     // ID instruction source 1
    input [4:0] id_rs2,     // ID instruction source 2
    output reg  stall          // 1 = insert stall
);
    always @(*) begin
        stall = 1'b0;
        if (ex_mem_read && (ex_rd != 5'd0)) begin
            if ((ex_rd == id_rs1) || (ex_rd == id_rs2))
                stall = 1'b1;
        end
    end
endmodule
