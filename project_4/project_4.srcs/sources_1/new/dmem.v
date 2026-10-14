`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/12/2026 04:31:08 PM
// Design Name: 
// Module Name: dmem
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

// dmem.v - Data Memory (byte-addressable, 1 KB)
// Synchronous write, asynchronous read, byte/half/word via funct3
// dmem.v - Data Memory (byte-addressable, 1 KB)
// Synchronous write, asynchronous read, byte/half/word via funct3.
// Organised as 4 byte lanes of DEPTH words so that Vivado maps it to distributed
// RAM (a flat byte array with unaligned multi-byte writes becomes 8K flip-flops).
// Accesses must be naturally aligned (LH/LHU/SH on even, LW/SW on multiples of 4),
// as RV32I allows misaligned accesses to trap; here they are not supported.
module dmem #(parameter DEPTH = 256) (
    input         clk,
    input         we,
    input  [31:0] addr,
    input  [31:0] wdata,
    input  [ 2:0] funct3,
    output reg [31:0] rdata,
    input  [ 7:0] dbg_addr,    // debug read port: word index
    output [31:0] dbg_data
);
    localparam AW = $clog2(DEPTH);

    reg [7:0] lane0 [0:DEPTH-1];
    reg [7:0] lane1 [0:DEPTH-1];
    reg [7:0] lane2 [0:DEPTH-1];
    reg [7:0] lane3 [0:DEPTH-1];

    integer k;
    initial for (k = 0; k < DEPTH; k = k + 1) begin
        lane0[k] = 8'b0; lane1[k] = 8'b0; lane2[k] = 8'b0; lane3[k] = 8'b0;
    end

    wire [AW-1:0] widx = addr[AW+1:2];
    wire [1:0]    boff = addr[1:0];

    // --- Synchronous Write (byte enables per lane) ---
    reg [3:0] be;
    always @(*) begin
        case (funct3[1:0])
            2'b00:   be = 4'b0001 << boff;                 // SB
            2'b01:   be = boff[1] ? 4'b1100 : 4'b0011;     // SH
            default: be = 4'b1111;                         // SW
        endcase
    end

    wire sw = (funct3[1:0] == 2'b10);
    wire sb = (funct3[1:0] == 2'b00);
    wire [7:0] d0 = wdata[7:0];
    wire [7:0] d1 = sb ? wdata[7:0]  : wdata[15:8];
    wire [7:0] d2 = sw ? wdata[23:16] : wdata[7:0];
    wire [7:0] d3 = sw ? wdata[31:24] : wdata[15:8];

    always @(posedge clk) begin
        if (we && funct3[2] == 1'b0 && funct3[1:0] != 2'b11) begin
            if (be[0]) lane0[widx] <= d0;
            if (be[1]) lane1[widx] <= d1;
            if (be[2]) lane2[widx] <= d2;
            if (be[3]) lane3[widx] <= d3;
        end
    end

    // --- Asynchronous Read ---
    wire [31:0] word = {lane3[widx], lane2[widx], lane1[widx], lane0[widx]};
    wire [ 7:0] b    = word[boff*8 +: 8];
    wire [15:0] h    = boff[1] ? word[31:16] : word[15:0];

    always @(*) begin
        case (funct3)
            3'b000:  rdata = {{24{b[7]}}, b};              // LB
            3'b001:  rdata = {{16{h[15]}}, h};             // LH
            3'b010:  rdata = word;                         // LW
            3'b100:  rdata = {24'b0, b};                   // LBU
            3'b101:  rdata = {16'b0, h};                   // LHU
            default: rdata = 32'b0;
        endcase
    end

    assign dbg_data = {lane3[dbg_addr], lane2[dbg_addr], lane1[dbg_addr], lane0[dbg_addr]};
endmodule
