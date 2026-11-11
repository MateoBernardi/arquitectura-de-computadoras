`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// top_riscv: top para la Nexys4 DDR (estructural)
//
// uart_core <-> debug_unit <-> riscv_pipeline
// - reset_gen: power-on reset + boton sincronizado. Resetea UART y debug unit;
//   el CPU recibe su reset desde la debug unit (que incluye el del sistema).
// - i_rx pasa por sync_2ff antes de uart_core.
// - LEDs (ver README.md): [0] CPU habilitado, [1] CPU en reset (carga), [2] halt,
//   [7:3] registro de la última escritura (con el display prendido), [10] forwarding
//   al operando A, [11] al B, [12] stall, [13] flush por salto, [14] excepción,
//   [15] halt. Los de eventos (led_eventos) quedan prendidos ~60 ms para que se vean.
// - i_sw[0] prende el display: muestra en hex el valor que escribió en su registro
//   la última instrucción que escribió uno (y su número en los LEDs 7..3).
// - Reloj: con USE_MMCM=1 todo el sistema corre a la frecuencia que genera el MMCM:
//     SYS_FREQ = CLK_FREQ * MMCM_MULT / (MMCM_DIV_X8 / 8)
//   (VCO = CLK_FREQ * MMCM_MULT, entre 600 y 1200 MHz en el Artix-7 -1; el divisor
//   de salida va en pasos de 0.125, por eso se pasa multiplicado por 8). Por defecto,
//   100 MHz * 7 / 10 = 70 MHz. El baud rate se calcula con SYS_FREQ. USE_MMCM=0 usa
//   i_clk directo (simulacion RTL).
// - Version: la ultima palabra del dump (la 89) es BUILD_ID. La sintesis le pasa el
//   commit del RTL, asi el host sabe que bitstream esta cargado en la placa.
// -----------------------------------------------------------------------------
module top_riscv #(
    parameter CLK_FREQ    = 100_000_000,     // frecuencia de i_clk
    parameter USE_MMCM    = 1,               // 1: sistema a SYS_FREQ (MMCM)
    parameter MMCM_MULT   = 7,               // VCO = CLK_FREQ * MMCM_MULT (700 MHz)
    parameter MMCM_DIV_X8 = 80,              // divisor de salida * 8 (80 = 10.0)
    parameter BAUD_RATE   = 19_200,
    parameter N_TICKS     = 16,
    parameter PTR_LEN     = 2,
    parameter IMEM_ADDR_W = 10,                // 1 KB = 256 instrucciones
    parameter [31:0] BUILD_ID = 32'h0          // version del RTL (commit); 0 = sin version
) (
    input  wire       i_clk,
    input  wire       i_reset,
    input  wire       i_rx,
    output wire       o_tx,
    input  wire [0:0] i_sw,
    output wire [15:0] o_led,
    output wire [7:0] o_an,
    output wire [6:0] o_seg
);
    // en kHz para no desbordar 32 bits: 100_000 * 10 * 8 cabe holgado
    localparam integer SYS_FREQ = USE_MMCM ? (CLK_FREQ / 1000 * MMCM_MULT * 8 / MMCM_DIV_X8) * 1000
                                           : CLK_FREQ;

    wire clk, locked;
    wire sys_reset, rx_sync;

    generate
        if (USE_MMCM) begin : g_mmcm
            wire clk_fb, clk_fb_buf, clk_out, clk_out_buf;
            MMCME2_BASE #(
                .CLKIN1_PERIOD  (1.0e9 / CLK_FREQ),
                .CLKFBOUT_MULT_F(MMCM_MULT * 1.0),     // VCO = CLK_FREQ * MMCM_MULT
                .CLKOUT0_DIVIDE_F(MMCM_DIV_X8 / 8.0),  // SYS_FREQ = VCO / divisor
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
    wire [15:0]            dbg_addr, dbg_count, cpu_dbg_count;
    wire [31:0]            dbg_data, cpu_dbg_data;

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

    wire [4:0]  cpu_eventos;
    wire        cpu_wb_we;
    wire [4:0]  cpu_wb_rd;
    wire [31:0] cpu_wb_data;

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
        .o_dbg_data  (cpu_dbg_data),
        .o_dbg_count (cpu_dbg_count),
        .o_eventos   (cpu_eventos),
        .o_wb_we     (cpu_wb_we),
        .o_wb_rd     (cpu_wb_rd),
        .o_wb_data   (cpu_wb_data)
    );

    // Bus de debug: las palabras del CPU y, al final, BUILD_ID
    assign dbg_count = cpu_dbg_count + 16'd1;
    assign dbg_data  = (dbg_addr == cpu_dbg_count) ? BUILD_ID : cpu_dbg_data;

    // --- LEDs y display -------------------------------------------------------------
    // eventos del pipeline: forwarding A/B, stall y flush duran un ciclo, así que se
    // estiran; la excepción y el halt son niveles
    wire [3:0] led_ev;
    // se limpia también con el reset del CPU: al cargar otro programa no quedan
    // eventos del anterior
    led_eventos #(.N(4)) u_led_ev (
        .i_clk(clk), .i_reset(sys_reset | cpu_reset), .i_en(cpu_enable),
        .i_ev(cpu_eventos[3:0]), .o_led(led_ev)
    );

    // la última escritura en el banco de registros (en un ciclo en que el CPU avanzó)
    reg [4:0]  ultimo_rd;
    reg [31:0] ultimo_valor;
    always @(posedge clk) begin
        if (sys_reset || cpu_reset) begin
            ultimo_rd    <= 5'd0;
            ultimo_valor <= 32'd0;
        end else if (cpu_enable && cpu_wb_we) begin
            ultimo_rd    <= cpu_wb_rd;
            ultimo_valor <= cpu_wb_data;
        end
    end

    wire sw_display;
    sync_2ff u_sw_sync (.i_clk(clk), .i_async(i_sw[0]), .o_sync(sw_display));

    display_7seg u_display (
        .i_clk(clk), .i_on(sw_display), .i_valor(ultimo_valor),
        .o_an(o_an), .o_seg(o_seg)
    );

    assign o_led = {cpu_halt, cpu_eventos[4], led_ev, 2'b00,
                    sw_display ? ultimo_rd : 5'd0,
                    cpu_halt, cpu_reset, cpu_enable};
endmodule
