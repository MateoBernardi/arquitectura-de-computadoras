`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// reset_gen: reset sincronico del sistema
//
// - Power-on reset: activo POR_CYCLES ciclos despues de configurar la FPGA
//   (valor inicial de los flip-flops), asi el sistema arranca limpio sin
//   apretar el boton.
// - Boton de reset (asincronico, activo en alto) sincronizado con sync_2ff.
// - POR_CYCLES >= 2.
// -----------------------------------------------------------------------------
module reset_gen #(
    parameter POR_CYCLES = 4
) (
    input  wire i_clk,
    input  wire i_btn_reset,
    output wire o_reset
);
    reg  [POR_CYCLES-1:0] por_reg = {POR_CYCLES{1'b1}};
    wire                  btn_reset;

    always @(posedge i_clk)
        por_reg <= {por_reg[POR_CYCLES-2:0], 1'b0};

    sync_2ff #(
        .INIT(1'b1)
    ) u_btn_sync (
        .i_clk  (i_clk),
        .i_async(i_btn_reset),
        .o_sync (btn_reset)
    );

    assign o_reset = por_reg[POR_CYCLES-1] | btn_reset;
endmodule
