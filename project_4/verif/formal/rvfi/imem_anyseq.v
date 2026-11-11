`timescale 1ns / 1ps

// imem para riscv-formal: mismo nombre y puertos que pipeline/1_fetch/imem.v,
// pero cada lectura devuelve una instrucción ARBITRARIA (la elige el solver).
// Así las pruebas valen para cualquier programa, no para uno en particular.
module imem #(
    parameter ADDR_W    = 10,
    parameter INIT_FILE = ""
) (
    input  wire              clk,
    input  wire [31:0]       addr,
    output wire [31:0]       instr,
    input  wire              wr_en,
    input  wire [ADDR_W-1:0] wr_addr,
    input  wire [7:0]        wr_data
);
    (* anyseq *) reg [31:0] any_instr;
    assign instr = any_instr;
endmodule
