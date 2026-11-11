`timescale 1ns / 1ps

// imem_formal — reemplazo de imem SOLO para verificación formal.
//
// Mismo nombre de módulo y mismos puertos que pipeline/1_fetch/imem.v (mismo
// contrato), pero en vez de arrancar con NOPs, su contenido es el cable
// fv_prog, que el script de Yosys conecta (con `connect`, después de
// `flatten`) a un valor (* anyconst *) del harness: el solver elige el
// programa, y el harness conoce ese mismo programa para el modelo de referencia.
//
// El puerto de escritura se ignora: los harness asumen i_imem_we = 0.
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
    localparam DEPTH = 1 << (ADDR_W - 2);

    (* keep *) wire [32*DEPTH-1:0] fv_prog;   // lo maneja el script de Yosys

    // Misma lectura que la imem real: combinacional, ignora addr[1:0] y los
    // bits por encima de ADDR_W (la memoria se repite cada 2^ADDR_W bytes).
    wire [ADDR_W-3:0] idx = addr[ADDR_W-1:2];
    assign instr = fv_prog[32*idx +: 32];
endmodule
