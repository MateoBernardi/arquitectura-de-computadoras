`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// program_counter: registro del PC
//
// - Carga i_mux_pc cuando i_enable = 1 y i_pc_stall = 0.
// - i_enable: debug unit (ejecucion continua / paso a paso / detenido).
// - i_pc_stall: stall efectivo; en instruction_fetch llega ya anulado por un
//   redirect de EX.
// - Reset sincronico activo en alto a RESET_VECTOR.
// - Los bits [1:0] no se fuerzan a cero: instru_mem los ignora.
// -----------------------------------------------------------------------------
module program_counter #(
    parameter [31:0] RESET_VECTOR = 32'h0000_0000
) (
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire        i_enable,
    input  wire        i_pc_stall,
    input  wire [31:0] i_mux_pc,
    output wire [31:0] o_pc
);
    wire pc_we = i_enable & ~i_pc_stall;

    latch #(
        .WIDTH      (32),
        .RESET_VALUE(RESET_VECTOR)
    ) u_pc_reg (
        .i_clock (i_clock),
        .i_reset (i_reset),
        .i_enable(pc_we),
        .i_data  (i_mux_pc),
        .o_data  (o_pc)
    );
endmodule
