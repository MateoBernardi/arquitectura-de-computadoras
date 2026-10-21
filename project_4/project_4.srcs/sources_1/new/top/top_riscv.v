`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// top_riscv: top para la Nexys4 DDR (estructural)
//
// uart_core <-> debug_unit <-> riscv_pipeline
// - reset_gen: power-on reset + boton sincronizado. Resetea UART y debug unit;
//   el CPU recibe su reset desde la debug unit (que incluye el del sistema).
// - i_rx pasa por sync_2ff antes de uart_core.
// - LEDs: [0] CPU habilitado, [1] CPU en reset (carga), [2] halt.
// - Reloj: el camino critico del pipeline (dmem -> forwarding -> ALU -> branch ->
//   flush) no cierra a 100 MHz (WNS ~ -5 ns post-ruteo). Con USE_MMCM=1 todo el
//   sistema corre a CLK_FREQ/2 (50 MHz) generado con un MMCM; el baud rate se
//   calcula con la frecuencia interna. USE_MMCM=0 usa i_clk directo (simulacion).
// -----------------------------------------------------------------------------
module top_riscv #(
    parameter CLK_FREQ    = 100_000_000,     // frecuencia de i_clk
    parameter USE_MMCM    = 1,               // 1: sistema a CLK_FREQ/2
    parameter BAUD_RATE   = 19_200,
    parameter N_TICKS     = 16,
    parameter PTR_LEN     = 2,
    parameter IMEM_ADDR_W = 10                 // 1 KB = 256 instrucciones
) (
    input  wire       i_clk,
    input  wire       i_reset,
    input  wire       i_rx,
    output wire       o_tx,
    output wire [2:0] o_led
);
    localparam SYS_FREQ = USE_MMCM ? CLK_FREQ / 2 : CLK_FREQ;

    wire clk, locked;
    wire sys_reset, rx_sync;

    generate
        if (USE_MMCM) begin : g_mmcm
            wire clk_fb, clk_fb_buf, clk_out, clk_out_buf;
            MMCME2_BASE #(
                .CLKIN1_PERIOD  (1.0e9 / CLK_FREQ),
                .CLKFBOUT_MULT_F(10.0),                // VCO = CLK_FREQ * 10
                .CLKOUT0_DIVIDE_F(20.0),               // CLK_FREQ / 2
                .DIVCLK_DIVIDE  (1)
            ) u_mmcm (
                .CLKIN1(i_clk), .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb),
                .CLKOUT0(clk_out), .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0),
                .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
                .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
            );
            BUFG u_fb  (.I(clk_fb),  .O(clk_fb_buf));
            BUFG u_out (.I(clk_out), .O(clk_out_buf));
            assign clk = clk_out_buf;
        end
        else begin : g_direct
            assign clk    = i_clk;
            assign locked = 1'b1;
        end
    endgenerate

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
        .i_clk      (clk),
        .i_btn_reset(i_reset | ~locked),
        .o_reset    (sys_reset)
    );

    sync_2ff #(
        .INIT(1'b1)                                    // linea UART en reposo = 1
    ) u_rx_sync (
        .i_clk  (clk),
        .i_async(i_rx),
        .o_sync (rx_sync)
    );

    uart_core #(
        .CLK_FREQ (SYS_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .NB_DATA  (8),
        .N_TICKS  (N_TICKS),
        .PTR_LEN  (PTR_LEN)
    ) u_uart (
        .i_clk          (clk),
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
        .i_clk              (clk),
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

    riscv_pipeline #(
        .IMEM_ADDR_W(IMEM_ADDR_W)
    ) u_cpu (
        .clk         (clk),
        .i_rst       (cpu_reset),
        .i_enable    (cpu_enable),
        .o_halt      (cpu_halt),
        .i_imem_we   (imem_we),
        .i_imem_waddr(imem_waddr),
        .i_imem_wdata(imem_wdata),
        .i_dbg_addr  (dbg_addr),
        .o_dbg_data  (dbg_data),
        .o_dbg_count (dbg_count)
    );

    assign o_led = {cpu_halt, cpu_reset, cpu_enable};
endmodule
