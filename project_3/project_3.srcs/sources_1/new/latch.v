`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// latch: registro generico disparado por flanco (flip-flops, no latch por nivel)
//
// - Reset sincronico activo en alto, con prioridad sobre el enable.
// - Con i_enable = 0 mantiene el valor.
// - Uso: registros de pipeline, PC, flags de control.
// -----------------------------------------------------------------------------
module latch #(
    parameter             WIDTH       = 32,
    parameter [WIDTH-1:0] RESET_VALUE = {WIDTH{1'b0}}
) (
    input  wire             i_clock,
    input  wire             i_reset,
    input  wire             i_enable,
    input  wire [WIDTH-1:0] i_data,
    output reg  [WIDTH-1:0] o_data
);
    always @(posedge i_clock) begin
        if (i_reset)
            o_data <= RESET_VALUE;
        else if (i_enable)
            o_data <= i_data;
    end
endmodule
