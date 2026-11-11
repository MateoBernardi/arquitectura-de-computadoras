`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// top_riscv: top para la Nexys4 DDR (estructural)
//
// uart_core <-> debug_unit <-> cpu
// - uart_core (TP2) sin cambios de puertos; debug_unit ocupa el lugar de
//   uart_interface.
// - reset_gen: power-on reset + boton sincronizado. Resetea UART y debug unit;
//   el CPU recibe su reset desde la debug unit (que incluye el del sistema).
// - i_rx pasa por sync_2ff antes de uart_core.
// - LEDs: [0] CPU habilitado, [1] CPU en reset (carga), [2] halt.
// -----------------------------------------------------------------------------
module top_riscv #(
    parameter CLK_FREQ    = 100_000_000,
    parameter BAUD_RATE   = 19_200,
    parameter N_TICKS     = 16,
    parameter PTR_LEN     = 2,
    parameter IMEM_ADDR_W = 8
) (
    input  wire       i_clk,
    input  wire       i_reset,
    input  wire       i_rx,
    output wire       o_tx,
    output wire [2:0] o_led
);
    wire sys_reset, rx_sync;

    // uart_core <-> debug_unit
    wire       rx_read, tx_write, rx_empty, tx_full;
    wire [7:0] rx_data, tx_data;

    // debug_unit <-> cpu
    wire                   cpu_enable, cpu_reset, cpu_halt;
    wire                   imem_we;
    wire [IMEM_ADDR_W-1:0] imem_waddr;
    wire [7:0]             imem_wdata;
    wire [15:0]            dbg_addr, dbg_count;
    wire [31:0]            dbg_data;

    reset_gen u_reset (
        .i_clk      (i_clk),
        .i_btn_reset(i_reset),
        .o_reset    (sys_reset)
    );

    sync_2ff #(
        .INIT(1'b1)                                    // linea UART en reposo = 1
    ) u_rx_sync (
        .i_clk  (i_clk),
        .i_async(i_rx),
        .o_sync (rx_sync)
    );

    uart_core #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .NB_DATA  (8),
        .N_TICKS  (N_TICKS),
        .PTR_LEN  (PTR_LEN)
    ) u_uart (
        .i_clk          (i_clk),
        .i_reset        (sys_reset),
        .i_rx           (rx_sync),
        .o_tx           (o_tx),
        .i_read_uart    (rx_read),
        .i_write_uart   (tx_write),
        .i_data_to_write(tx_data),
        .o_tx_full      (tx_full),
        .o_rx_empty     (rx_empty),
        .o_rx_full      (),
        .o_data_to_read (rx_data)
    );

    debug_unit #(
        .IMEM_ADDR_W(IMEM_ADDR_W)
    ) u_debug (
        .i_clk              (i_clk),
        .i_reset            (sys_reset),
        .i_data_to_read     (rx_data),
        .i_fifo_rx_empty    (rx_empty),
        .i_fifo_tx_full     (tx_full),
        .o_fifo_rx_read     (rx_read),
        .o_fifo_tx_write    (tx_write),
        .o_data_to_write    (tx_data),
        .o_cpu_enable       (cpu_enable),
        .o_cpu_reset        (cpu_reset),
        .i_cpu_halt         (cpu_halt),
        .o_imem_write_enable(imem_we),
        .o_imem_write_addr  (imem_waddr),
        .o_imem_write_data  (imem_wdata),
        .o_dbg_addr         (dbg_addr),
        .i_dbg_data         (dbg_data),
        .i_dbg_count        (dbg_count)
    );

    cpu #(
        .IMEM_ADDR_W(IMEM_ADDR_W)
    ) u_cpu (
        .i_clk              (i_clk),
        .i_reset            (cpu_reset),
        .i_enable           (cpu_enable),
        .o_halt             (cpu_halt),
        .i_imem_write_enable(imem_we),
        .i_imem_write_addr  (imem_waddr),
        .i_imem_write_data  (imem_wdata),
        .i_dbg_addr         (dbg_addr),
        .o_dbg_data         (dbg_data),
        .o_dbg_count        (dbg_count)
    );

    assign o_led = {cpu_halt, cpu_reset, cpu_enable};
endmodule
