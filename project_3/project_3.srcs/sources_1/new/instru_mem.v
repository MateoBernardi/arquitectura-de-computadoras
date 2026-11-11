`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// instru_mem: memoria de instrucciones en BRAM (simple dual port)
//
// - Lectura: palabra de 32 bits, sincronica. i_read_addr es direccion en bytes;
//   se usan los bits [ADDR_W-1:2]. Con i_read_enable = 0 la salida se mantiene.
// - Escritura: de a un byte (debug unit / UART), little-endian: el byte en la
//   direccion A va al carril A[1:0] de la palabra A[ADDR_W-1:2]. Escribir con
//   el procesador detenido: leer y escribir la misma direccion en el mismo
//   ciclo no tiene resultado definido.
// - Contenido inicial: NOP en todas las posiciones; si INIT_FILE no es vacio,
//   se carga con $readmemh (una palabra de 32 bits por linea).
// - Sin reset en la salida: tras un reset, instruction_fetch la enmascara con
//   NOP a traves de flush_reg.
// - Capacidad: 2^ADDR_W bytes = 2^(ADDR_W-2) instrucciones. ADDR_W >= 3.
// -----------------------------------------------------------------------------
module instru_mem #(
    parameter ADDR_W    = 8,
    parameter INIT_FILE = ""
) (
    input  wire              i_clock,
    input  wire              i_enable,
    input  wire              i_read_enable,
    input  wire [31:0]       i_read_addr,
    output reg  [31:0]       o_read_data,
    input  wire              i_write_enable,
    input  wire [ADDR_W-1:0] i_write_addr,
    input  wire [7:0]        i_write_data
);
    localparam        DEPTH = 1 << (ADDR_W - 2);
    localparam [31:0] NOP   = 32'h0000_0013;           // addi x0, x0, 0

    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];

    wire [ADDR_W-3:0] rd_word = i_read_addr[ADDR_W-1:2];
    wire [ADDR_W-3:0] wr_word = i_write_addr[ADDR_W-1:2];
    wire [3:0]        we      = {4{i_enable & i_write_enable}} & (4'b0001 << i_write_addr[1:0]);

    integer k;
    initial begin
        for (k = 0; k < DEPTH; k = k + 1)
            mem[k] = NOP;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
        o_read_data = NOP;
    end

    // Puerto de escritura: un byte por ciclo
    always @(posedge i_clock) begin
        if (we[0]) mem[wr_word][7:0]   <= i_write_data;
        if (we[1]) mem[wr_word][15:8]  <= i_write_data;
        if (we[2]) mem[wr_word][23:16] <= i_write_data;
        if (we[3]) mem[wr_word][31:24] <= i_write_data;
    end

    // Puerto de lectura: una palabra por ciclo
    always @(posedge i_clock) begin
        if (i_enable && i_read_enable)
            o_read_data <= mem[rd_word];
    end
endmodule
