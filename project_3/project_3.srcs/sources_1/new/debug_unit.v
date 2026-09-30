`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// debug_unit: carga del programa por UART y control de ejecucion del CPU
//
// Estructural: conecta debug_unit_fsm (maquina de estados), debug_unit_comb
// (camino de datos combinacional) y debug_unit_regs (registros).
//
// Reemplaza a uart_interface: se conecta a uart_core con los mismos nombres de
// puertos. Lee la FIFO de RX solo cuando no esta vacia y escribe la de TX solo
// cuando no esta llena.
//
// Protocolo (host -> FPGA: un byte de comando; FPGA -> host: un byte de respuesta)
//   'L' n_lo n_hi b0 b1 ... b(4n-1)
//        Carga n instrucciones (n de 16 bits, little-endian). Cada instruccion
//        va en 4 bytes little-endian, el orden de un .bin de RISC-V: el byte k
//        se escribe en la direccion k de instru_mem. Las posiciones que el
//        programa no cubre se rellenan con NOP. Durante la carga el CPU queda
//        en reset; al terminar queda detenido con PC = 0.
//        Respuesta: 'K', o 'E' si el programa no entra en la memoria (los
//        bytes se consumen igual y se escriben los que entran).
//        Con n = 0 la memoria queda toda en NOP.
//   'S'  Avanza el CPU un ciclo. Respuesta: 'K', o 'H' si esta en halt.
//   'R'  Ejecucion continua. Respuesta: 'K', o 'H' si esta en halt.
//        Si durante la ejecucion i_cpu_halt pasa a 1, se detiene y envia 'H'.
//   'P'  Detiene la ejecucion continua. Respuesta: 'K'.
//   'X'  Reset del CPU (PC = 0, pipeline limpio). El programa se conserva y
//        el CPU queda detenido. Respuesta: 'K'.
//   'D'  Dump: count_lo count_hi y despues count palabras de 32 bits
//        little-endian, leidas del bus de debug en las direcciones
//        0 .. count-1. Mientras dura el dump el CPU no avanza; al terminar
//        vuelve al modo en que estaba.
//   Otro byte: respuesta '?'.
//
// Bus de debug: o_dbg_addr se mantiene un ciclo antes de muestrear i_dbg_data,
// asi sirve tanto para fuentes combinacionales como para fuentes con un ciclo
// de latencia (BRAM de la memoria de datos). i_dbg_count lo define el CPU.
//
// o_cpu_reset: reset del CPU (reset del sistema, carga o comando 'X').
// i_cpu_halt: nivel. Mientras vale 1 el CPU no avanza (o_cpu_enable = 0).
// -----------------------------------------------------------------------------
module debug_unit #(
    parameter IMEM_ADDR_W = 8                          // igual que en instruction_fetch, <= 16
) (
    input  wire                   i_clk,
    input  wire                   i_reset,
    // uart_core
    input  wire [7:0]             i_data_to_read,
    input  wire                   i_fifo_rx_empty,
    input  wire                   i_fifo_tx_full,
    output wire                   o_fifo_rx_read,
    output wire                   o_fifo_tx_write,
    output wire [7:0]             o_data_to_write,
    // control del CPU
    output wire                   o_cpu_enable,
    output wire                   o_cpu_reset,
    input  wire                   i_cpu_halt,
    // puerto de escritura de instru_mem
    output wire                   o_imem_write_enable,
    output wire [IMEM_ADDR_W-1:0] o_imem_write_addr,
    output wire [7:0]             o_imem_write_data,
    // bus de debug
    output wire [15:0]            o_dbg_addr,
    input  wire [31:0]            i_dbg_data,
    input  wire [15:0]            i_dbg_count
);
    // Registros
    wire [3:0]             state,     state_next;
    wire                   run,       run_next;
    wire                   step,      step_next;
    wire                   cpu_rst,   cpu_rst_next;
    wire [15:0]            len,       len_next;
    wire [17:0]            byte_cnt,  byte_cnt_next;
    wire                   overflow,  overflow_next;
    wire [7:0]             reply,     reply_next;
    wire                   imem_we,   imem_we_next;
    wire [IMEM_ADDR_W-1:0] imem_addr, imem_addr_next;
    wire [7:0]             imem_data, imem_data_next;
    wire [15:0]            dbg_addr,  dbg_addr_next;
    wire [31:0]            dbg_word,  dbg_word_next;
    wire [1:0]             byte_idx,  byte_idx_next;

    // Control (FSM -> camino de datos)
    wire       len_lo_load, len_hi_load, cnt_clear, cnt_inc, ovf_load;
    wire       imem_load, imem_fill, reply_load;
    wire [7:0] reply_code;
    wire       dbg_addr_clear, dbg_addr_inc, word_load, word_shift;
    wire       byte_idx_clear, byte_idx_inc;
    wire       send_count_lo, send_count_hi, send_word;

    // Estado (camino de datos -> FSM)
    wire       len_zero, load_last, in_range, dbg_count_zero, dbg_last, byte_last;

    debug_unit_fsm FSM (
        .i_reset         (i_reset),
        .i_state         (state),
        .i_run           (run),
        .i_step          (step),
        .i_cpu_rst       (cpu_rst),
        .i_rx_empty      (i_fifo_rx_empty),
        .i_tx_full       (i_fifo_tx_full),
        .i_rx_byte       (i_data_to_read),
        .i_cpu_halt      (i_cpu_halt),
        .i_overflow      (overflow),
        .i_len_zero      (len_zero),
        .i_load_last     (load_last),
        .i_in_range      (in_range),
        .i_dbg_count_zero(dbg_count_zero),
        .i_dbg_last      (dbg_last),
        .i_byte_last     (byte_last),
        .o_state_next    (state_next),
        .o_run_next      (run_next),
        .o_step_next     (step_next),
        .o_cpu_rst_next  (cpu_rst_next),
        .o_rx_read       (o_fifo_rx_read),
        .o_tx_write      (o_fifo_tx_write),
        .o_len_lo_load   (len_lo_load),
        .o_len_hi_load   (len_hi_load),
        .o_cnt_clear     (cnt_clear),
        .o_cnt_inc       (cnt_inc),
        .o_ovf_load      (ovf_load),
        .o_imem_we_next  (imem_we_next),
        .o_imem_load     (imem_load),
        .o_imem_fill     (imem_fill),
        .o_reply_load    (reply_load),
        .o_reply_code    (reply_code),
        .o_dbg_addr_clear(dbg_addr_clear),
        .o_dbg_addr_inc  (dbg_addr_inc),
        .o_word_load     (word_load),
        .o_word_shift    (word_shift),
        .o_byte_idx_clear(byte_idx_clear),
        .o_byte_idx_inc  (byte_idx_inc),
        .o_send_count_lo (send_count_lo),
        .o_send_count_hi (send_count_hi),
        .o_send_word     (send_word),
        .o_cpu_enable    (o_cpu_enable),
        .o_cpu_reset     (o_cpu_reset)
    );

    debug_unit_comb #(
        .IMEM_ADDR_W(IMEM_ADDR_W)
    ) COMB (
        .i_len           (len),
        .i_byte_cnt      (byte_cnt),
        .i_overflow      (overflow),
        .i_reply         (reply),
        .i_imem_addr     (imem_addr),
        .i_imem_data     (imem_data),
        .i_dbg_addr      (dbg_addr),
        .i_dbg_word      (dbg_word),
        .i_byte_idx      (byte_idx),
        .i_rx_byte       (i_data_to_read),
        .i_dbg_data      (i_dbg_data),
        .i_dbg_count     (i_dbg_count),
        .i_len_lo_load   (len_lo_load),
        .i_len_hi_load   (len_hi_load),
        .i_cnt_clear     (cnt_clear),
        .i_cnt_inc       (cnt_inc),
        .i_ovf_load      (ovf_load),
        .i_imem_load     (imem_load),
        .i_imem_fill     (imem_fill),
        .i_reply_load    (reply_load),
        .i_reply_code    (reply_code),
        .i_dbg_addr_clear(dbg_addr_clear),
        .i_dbg_addr_inc  (dbg_addr_inc),
        .i_word_load     (word_load),
        .i_word_shift    (word_shift),
        .i_byte_idx_clear(byte_idx_clear),
        .i_byte_idx_inc  (byte_idx_inc),
        .i_send_count_lo (send_count_lo),
        .i_send_count_hi (send_count_hi),
        .i_send_word     (send_word),
        .o_len_next      (len_next),
        .o_byte_cnt_next (byte_cnt_next),
        .o_overflow_next (overflow_next),
        .o_reply_next    (reply_next),
        .o_imem_addr_next(imem_addr_next),
        .o_imem_data_next(imem_data_next),
        .o_dbg_addr_next (dbg_addr_next),
        .o_dbg_word_next (dbg_word_next),
        .o_byte_idx_next (byte_idx_next),
        .o_tx_data       (o_data_to_write),
        .o_len_zero      (len_zero),
        .o_load_last     (load_last),
        .o_in_range      (in_range),
        .o_dbg_count_zero(dbg_count_zero),
        .o_dbg_last      (dbg_last),
        .o_byte_last     (byte_last)
    );

    debug_unit_regs #(
        .IMEM_ADDR_W(IMEM_ADDR_W)
    ) REGS (
        .i_clk           (i_clk),
        .i_reset         (i_reset),
        .i_state_next    (state_next),
        .i_run_next      (run_next),
        .i_step_next     (step_next),
        .i_cpu_rst_next  (cpu_rst_next),
        .i_len_next      (len_next),
        .i_byte_cnt_next (byte_cnt_next),
        .i_overflow_next (overflow_next),
        .i_reply_next    (reply_next),
        .i_imem_we_next  (imem_we_next),
        .i_imem_addr_next(imem_addr_next),
        .i_imem_data_next(imem_data_next),
        .i_dbg_addr_next (dbg_addr_next),
        .i_dbg_word_next (dbg_word_next),
        .i_byte_idx_next (byte_idx_next),
        .o_state         (state),
        .o_run           (run),
        .o_step          (step),
        .o_cpu_rst       (cpu_rst),
        .o_len           (len),
        .o_byte_cnt      (byte_cnt),
        .o_overflow      (overflow),
        .o_reply         (reply),
        .o_imem_we       (imem_we),
        .o_imem_addr     (imem_addr),
        .o_imem_data     (imem_data),
        .o_dbg_addr      (dbg_addr),
        .o_dbg_word      (dbg_word),
        .o_byte_idx      (byte_idx)
    );

    assign o_imem_write_enable = imem_we;
    assign o_imem_write_addr   = imem_addr;
    assign o_imem_write_data   = imem_data;
    assign o_dbg_addr          = dbg_addr;
endmodule
