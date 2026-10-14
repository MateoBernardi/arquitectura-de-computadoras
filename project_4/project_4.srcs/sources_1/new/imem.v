`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: imem
// Description: Instruction memory. Combinational read (word-addressed from the
//              byte address of the PC) and a byte-wide write port used by the
//              debug unit to load a program over UART. The write port is not
//              gated by the CPU enable: the CPU is held in reset while loading.
//              Little-endian: byte k of the program lands at byte address k.
//              Powers up filled with NOP (addi x0,x0,0); INIT_FILE (optional,
//              $readmemh format) overrides it for simulation.
//////////////////////////////////////////////////////////////////////////////////
module imem #(
    parameter ADDR_W    = 10,           // byte-address width: 2**ADDR_W bytes
    parameter INIT_FILE = ""
) (
    input  wire              clk,
    // fetch port
    input  wire [31:0]       addr,      // byte address from PC
    output wire [31:0]       instr,
    // load port (byte write)
    input  wire              wr_en,
    input  wire [ADDR_W-1:0] wr_addr,
    input  wire [7:0]        wr_data
);
    localparam        DEPTH = 1 << (ADDR_W - 2);
    localparam [31:0] NOP   = 32'h0000_0013;

    reg [31:0] mem [0:DEPTH-1];

    integer k;
    initial begin
        for (k = 0; k < DEPTH; k = k + 1)
            mem[k] = NOP;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    wire [ADDR_W-3:0] wr_word = wr_addr[ADDR_W-1:2];

    always @(posedge clk) begin
        if (wr_en) begin
            case (wr_addr[1:0])
                2'd0: mem[wr_word][7:0]   <= wr_data;
                2'd1: mem[wr_word][15:8]  <= wr_data;
                2'd2: mem[wr_word][23:16] <= wr_data;
                2'd3: mem[wr_word][31:24] <= wr_data;
            endcase
        end
    end

    assign instr = mem[addr[ADDR_W-1:2]];
endmodule
