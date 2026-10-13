`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 05:44:17 PM
// Design Name: 
// Module Name: forward_unit
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

// forward_unit.v - Detects RAW hazards and generates forwarding mux selects
// forward_a/B encoding:
//   2'b00 - use register file value (no hazard)
//   2'b10 - forward from EX/MEM pipeline register (1 instruction ago)
//   2'b01 - forward from MEM/WB pipeline register (2 instructions ago)
module forward_unit (
    input [4:0] ex_rs1,
    input [4:0] ex_rs2,
    input [4:0] mem_rd,
    input       mem_reg_write,
    input [4:0] wb_rd,
    input       wb_reg_write,
    output reg [1:0] forward_a,
    output reg [1:0] forward_b
);
    always @(*) begin
        // Default: no forwarding
        forward_a = 2'b00;
        forward_b = 2'b00;

        // EX/MEM forwarding (higher priority - more recent result)
        if (mem_reg_write && (mem_rd != 5'b0)) begin
            if (mem_rd == ex_rs1) forward_a = 2'b10;
            if (mem_rd == ex_rs2) forward_b = 2'b10;
        end

        // MEM/WB forwarding (lower priority)
        if (wb_reg_write && (wb_rd != 5'b0)) begin
            // Only forward from WB if EX/MEM didn't already cover it
            if (wb_rd == ex_rs1 && !(mem_reg_write && mem_rd == ex_rs1))
                forward_a = 2'b01;
            if (wb_rd == ex_rs2 && !(mem_reg_write && mem_rd == ex_rs2))
                forward_b = 2'b01;
        end
    end
endmodule
