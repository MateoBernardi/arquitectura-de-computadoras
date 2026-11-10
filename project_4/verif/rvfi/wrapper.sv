// rvfi_wrapper: conecta el CPU (riscv_pipeline) con riscv-formal.
//
// - clock / reset los maneja riscv-formal.
// - i_enable es LIBRE: la debug unit puede pausar el CPU en cualquier ciclo.
//   Durante el reset vale 0: es el contrato de la debug unit (CMD_RESET baja
//   'run' en el mismo ciclo; ver verif/README.md, "Hallazgos").
// - Las instrucciones llegan de imem_anyseq.v (arbitrarias en cada lectura).
// - La memoria de datos es la dmem real del diseño.
module rvfi_wrapper (
    input clock,
    input reset,
    `RVFI_OUTPUTS
);
    (* keep *) `rvformal_rand_reg enable;
    (* keep *) wire        o_halt;
    (* keep *) wire [31:0] o_dbg_data;
    (* keep *) wire [15:0] o_dbg_count;

    riscv_pipeline uut (
        .clk          (clock),
        .i_rst        (reset),
        .i_enable     (enable && !reset),
        .o_halt       (o_halt),
        .i_imem_we    (1'b0),
        .i_imem_waddr (10'd0),
        .i_imem_wdata (8'd0),
        .i_dbg_addr   (16'd0),
        .o_dbg_data   (o_dbg_data),
        .o_dbg_count  (o_dbg_count),
        `RVFI_CONN
    );

endmodule
