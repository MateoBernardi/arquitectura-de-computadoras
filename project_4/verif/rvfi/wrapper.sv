// rvfi_wrapper: conecta el CPU (riscv_pipeline) con riscv-formal.
//
// - clock / reset los maneja riscv-formal.
// - i_enable es LIBRE en todo ciclo, incluso durante el reset: la debug unit
//   puede pausar el CPU cuando quiera.
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
        .i_enable     (enable),
        .o_halt       (o_halt),
        .i_imem_we    (1'b0),
        .i_imem_waddr (10'd0),
        .i_imem_wdata (8'd0),
        .i_dbg_addr   (16'd0),
        .o_dbg_data   (o_dbg_data),
        .o_dbg_count  (o_dbg_count),
        `RVFI_CONN
    );

`ifdef TP4_FAIRNESS
    // Equidad, solo para el chequeo 'liveness': i_enable no vale 0 más de 2 ciclos seguidos.
    reg [1:0] paused = 2'b00;
    always @(posedge clock) begin
        paused <= {paused[0], !enable};
        assume (!(paused == 2'b11 && !enable));
    end
`endif
endmodule
