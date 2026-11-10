// pma.sv: mapa de memoria del CPU para riscv-formal (RISCV_FORMAL_PMA_MAP).
// Con IMEM_ADDR_W = 10 y DMEM_DEPTH = 256 (los valores del diseño):
//   X (se puede ejecutar): [0, 1 KB)  = la imem
//   R/W (load/store):      [0, 1 KB)  = la dmem
// Un acceso fuera de estos rangos tiene que generar un access fault (trap).
module tp4_pma (
    input  [31:0] address,
    input  [1:0]  log2len,
    output        X, R, W
);
    localparam [31:0] IMEM_BYTES = 32'd1024;
    localparam [31:0] DMEM_BYTES = 32'd1024;
    assign X = address < IMEM_BYTES;
    assign R = address < DMEM_BYTES;
    assign W = address < DMEM_BYTES;
endmodule
