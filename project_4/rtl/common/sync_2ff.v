`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// sync_2ff: sincronizador de 2 flip-flops para una entrada asincronica
//
// - Sin reset: arranca en INIT despues de configurar la FPGA.
// - ASYNC_REG le indica a Vivado que son flip-flops de sincronizacion.
// -----------------------------------------------------------------------------
module sync_2ff #(
    parameter [0:0] INIT = 1'b0
) (
    input  wire i_clk,
    input  wire i_async,
    output wire o_sync
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_reg = {2{INIT}};

    always @(posedge i_clk)
        sync_reg <= {sync_reg[0], i_async};

    assign o_sync = sync_reg[1];
endmodule
