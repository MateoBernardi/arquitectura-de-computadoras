`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// debug_unit_comb: camino de datos combinacional de la debug unit
//
// Proximos valores de los registros de datos segun las senales de control de
// debug_unit_fsm, el byte que se envia por TX y los flags de estado que la
// FSM usa para decidir.
// -----------------------------------------------------------------------------
module debug_unit_comb #(
    parameter IMEM_ADDR_W = 8
) (
    // registros actuales
    input  wire [15:0]            i_len,
    input  wire [17:0]            i_byte_cnt,
    input  wire                   i_overflow,
    input  wire [7:0]             i_reply,
    input  wire [IMEM_ADDR_W-1:0] i_imem_addr,
    input  wire [7:0]             i_imem_data,
    input  wire [15:0]            i_dbg_addr,
    input  wire [31:0]            i_dbg_word,
    input  wire [1:0]             i_byte_idx,
    // entradas externas
    input  wire [7:0]             i_rx_byte,
    input  wire [31:0]            i_dbg_data,
    input  wire [15:0]            i_dbg_count,
    // control (debug_unit_fsm)
    input  wire                   i_len_lo_load,
    input  wire                   i_len_hi_load,
    input  wire                   i_cnt_clear,
    input  wire                   i_cnt_inc,
    input  wire                   i_ovf_load,
    input  wire                   i_imem_load,
    input  wire                   i_imem_fill,
    input  wire                   i_reply_load,
    input  wire [7:0]             i_reply_code,
    input  wire                   i_dbg_addr_clear,
    input  wire                   i_dbg_addr_inc,
    input  wire                   i_word_load,
    input  wire                   i_word_shift,
    input  wire                   i_byte_idx_clear,
    input  wire                   i_byte_idx_inc,
    input  wire                   i_send_count_lo,
    input  wire                   i_send_count_hi,
    input  wire                   i_send_word,
    // proximos valores
    output wire [15:0]            o_len_next,
    output wire [17:0]            o_byte_cnt_next,
    output wire                   o_overflow_next,
    output wire [7:0]             o_reply_next,
    output wire [IMEM_ADDR_W-1:0] o_imem_addr_next,
    output wire [7:0]             o_imem_data_next,
    output wire [15:0]            o_dbg_addr_next,
    output wire [31:0]            o_dbg_word_next,
    output wire [1:0]             o_byte_idx_next,
    output wire [7:0]             o_tx_data,
    // estado para la FSM
    output wire                   o_len_zero,          // la longitud que llega es 0
    output wire                   o_load_last,         // ultimo byte del programa
    output wire                   o_in_range,          // byte_cnt dentro de instru_mem
    output wire                   o_dbg_count_zero,
    output wire                   o_dbg_last,          // ultima palabra del dump
    output wire                   o_byte_last          // ultimo byte de la palabra
);
    localparam [17:0] CAP_BYTES = 18'd1 << IMEM_ADDR_W; // capacidad de instru_mem en bytes

    wire [17:0] n_bytes    = {i_len, 2'b00};                      // bytes del programa
    wire [17:0] n_bytes_rx = {i_rx_byte, i_len[7:0], 2'b00};      // idem, con el byte alto entrante
    wire [7:0]  nop_byte   = (i_byte_cnt[1:0] == 2'b00) ? 8'h13 : 8'h00;   // NOP = 0x00000013

    assign o_len_next       = {i_len_hi_load ? i_rx_byte : i_len[15:8],
                               i_len_lo_load ? i_rx_byte : i_len[7:0]};
    assign o_byte_cnt_next  = i_cnt_clear ? 18'd0 :
                              i_cnt_inc   ? i_byte_cnt + 18'd1 : i_byte_cnt;
    assign o_overflow_next  = i_ovf_load  ? (n_bytes_rx > CAP_BYTES) : i_overflow;
    assign o_reply_next     = i_reply_load ? i_reply_code : i_reply;
    assign o_imem_addr_next = i_imem_load ? i_byte_cnt[IMEM_ADDR_W-1:0] : i_imem_addr;
    assign o_imem_data_next = ~i_imem_load ? i_imem_data :
                              i_imem_fill  ? nop_byte    : i_rx_byte;
    assign o_dbg_addr_next  = i_dbg_addr_clear ? 16'd0 :
                              i_dbg_addr_inc   ? i_dbg_addr + 16'd1 : i_dbg_addr;
    assign o_dbg_word_next  = i_word_load  ? i_dbg_data :
                              i_word_shift ? {8'h00, i_dbg_word[31:8]} : i_dbg_word;
    assign o_byte_idx_next  = i_byte_idx_clear ? 2'd0 :
                              i_byte_idx_inc   ? i_byte_idx + 2'd1 : i_byte_idx;
    assign o_tx_data        = i_send_count_lo ? i_dbg_count[7:0]  :
                              i_send_count_hi ? i_dbg_count[15:8] :
                              i_send_word     ? i_dbg_word[7:0]   : i_reply;

    assign o_len_zero       = (n_bytes_rx == 18'd0);
    assign o_load_last      = (i_byte_cnt == n_bytes - 18'd1);
    assign o_in_range       = (i_byte_cnt < CAP_BYTES);
    assign o_dbg_count_zero = (i_dbg_count == 16'd0);
    assign o_dbg_last       = (i_dbg_addr == i_dbg_count - 16'd1);
    assign o_byte_last      = (i_byte_idx == 2'd3);
endmodule
