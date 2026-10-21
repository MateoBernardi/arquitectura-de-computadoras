`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// debug_unit_fsm: maquina de estados de la debug unit (combinacional)
//
// Logica de negocio del protocolo (ver debug_unit.v): decodifica comandos,
// decide el proximo estado, las respuestas y las senales de control del
// camino de datos (debug_unit_comb) y del CPU.
// El registro de estado esta en debug_unit_regs; IDLE = 0 es su valor de reset.
// -----------------------------------------------------------------------------
module debug_unit_fsm (
    input  wire       i_reset,                         // reset del sistema
    input  wire [3:0] i_state,
    input  wire       i_run,
    input  wire       i_step,
    input  wire       i_cpu_rst,
    // entradas externas
    input  wire       i_rx_empty,
    input  wire       i_tx_full,
    input  wire [7:0] i_rx_byte,                       // comando recibido
    input  wire       i_cpu_halt,
    // estado del camino de datos
    input  wire       i_overflow,
    input  wire       i_len_zero,
    input  wire       i_load_last,
    input  wire       i_in_range,
    input  wire       i_dbg_count_zero,
    input  wire       i_dbg_last,
    input  wire       i_byte_last,
    // proximo estado y modo
    output reg  [3:0] o_state_next,
    output reg        o_run_next,
    output reg        o_step_next,
    output reg        o_cpu_rst_next,
    // FIFOs de uart_core
    output reg        o_rx_read,
    output reg        o_tx_write,
    // control del camino de datos
    output reg        o_len_lo_load,
    output reg        o_len_hi_load,
    output reg        o_cnt_clear,
    output reg        o_cnt_inc,
    output reg        o_ovf_load,
    output reg        o_imem_we_next,
    output reg        o_imem_load,
    output reg        o_imem_fill,
    output reg        o_reply_load,
    output reg  [7:0] o_reply_code,
    output reg        o_dbg_addr_clear,
    output reg        o_dbg_addr_inc,
    output reg        o_word_load,
    output reg        o_word_shift,
    output reg        o_byte_idx_clear,
    output reg        o_byte_idx_inc,
    output reg        o_send_count_lo,
    output reg        o_send_count_hi,
    output reg        o_send_word,
    // control del CPU
    output wire       o_cpu_enable,
    output wire       o_cpu_reset
);
    localparam [7:0] CMD_LOAD  = 8'h4C;                // 'L'
    localparam [7:0] CMD_STEP  = 8'h53;                // 'S'
    localparam [7:0] CMD_RUN   = 8'h52;                // 'R'
    localparam [7:0] CMD_PAUSE = 8'h50;                // 'P'
    localparam [7:0] CMD_RESET = 8'h58;                // 'X'
    localparam [7:0] CMD_DUMP  = 8'h44;                // 'D'
    localparam [7:0] RSP_OK    = 8'h4B;                // 'K'
    localparam [7:0] RSP_ERR   = 8'h45;                // 'E'
    localparam [7:0] RSP_HALT  = 8'h48;                // 'H'
    localparam [7:0] RSP_UNK   = 8'h3F;                // '?'

    localparam [3:0] IDLE        = 4'd0;
    localparam [3:0] LOAD_LEN_LO = 4'd1;
    localparam [3:0] LOAD_LEN_HI = 4'd2;
    localparam [3:0] LOAD_DATA   = 4'd3;
    localparam [3:0] LOAD_FILL   = 4'd4;
    localparam [3:0] REPLY       = 4'd5;
    localparam [3:0] DUMP_CNT_LO = 4'd6;
    localparam [3:0] DUMP_CNT_HI = 4'd7;
    localparam [3:0] DUMP_ADDR   = 4'd8;
    localparam [3:0] DUMP_LATCH  = 4'd9;
    localparam [3:0] DUMP_BYTE   = 4'd10;

    wire loading = (i_state == LOAD_LEN_LO) | (i_state == LOAD_LEN_HI) |
                   (i_state == LOAD_DATA)   | (i_state == LOAD_FILL);
    wire dumping = (i_state == DUMP_CNT_LO) | (i_state == DUMP_CNT_HI) |
                   (i_state == DUMP_ADDR)   | (i_state == DUMP_LATCH)  |
                   (i_state == DUMP_BYTE);

    always @(*) begin
        o_state_next     = i_state;
        o_run_next       = i_run;
        o_step_next      = 1'b0;
        o_cpu_rst_next   = 1'b0;
        o_rx_read        = 1'b0;
        o_tx_write       = 1'b0;
        o_len_lo_load    = 1'b0;
        o_len_hi_load    = 1'b0;
        o_cnt_clear      = 1'b0;
        o_cnt_inc        = 1'b0;
        o_ovf_load       = 1'b0;
        o_imem_we_next   = 1'b0;
        o_imem_load      = 1'b0;
        o_imem_fill      = 1'b0;
        o_reply_load     = 1'b0;
        o_reply_code     = RSP_OK;
        o_dbg_addr_clear = 1'b0;
        o_dbg_addr_inc   = 1'b0;
        o_word_load      = 1'b0;
        o_word_shift     = 1'b0;
        o_byte_idx_clear = 1'b0;
        o_byte_idx_inc   = 1'b0;
        o_send_count_lo  = 1'b0;
        o_send_count_hi  = 1'b0;
        o_send_word      = 1'b0;

        case (i_state)
            IDLE: begin
                if (i_run && i_cpu_halt) begin         // se detuvo durante la ejecucion
                    o_run_next   = 1'b0;
                    o_reply_load = 1'b1;
                    o_reply_code = RSP_HALT;
                    o_state_next = REPLY;
                end
                else if (~i_rx_empty) begin
                    o_rx_read = 1'b1;
                    case (i_rx_byte)
                        CMD_LOAD: begin
                            o_run_next   = 1'b0;
                            o_state_next = LOAD_LEN_LO;
                        end
                        CMD_STEP: begin
                            o_run_next   = 1'b0;
                            o_reply_load = 1'b1;
                            if (i_cpu_halt)
                                o_reply_code = RSP_HALT;
                            else begin
                                o_step_next  = 1'b1;
                                o_reply_code = RSP_OK;
                            end
                            o_state_next = REPLY;
                        end
                        CMD_RUN: begin
                            o_reply_load = 1'b1;
                            if (i_cpu_halt)
                                o_reply_code = RSP_HALT;
                            else begin
                                o_run_next   = 1'b1;
                                o_reply_code = RSP_OK;
                            end
                            o_state_next = REPLY;
                        end
                        CMD_PAUSE: begin
                            o_run_next   = 1'b0;
                            o_reply_load = 1'b1;
                            o_reply_code = RSP_OK;
                            o_state_next = REPLY;
                        end
                        CMD_RESET: begin
                            o_run_next     = 1'b0;
                            o_cpu_rst_next = 1'b1;
                            o_reply_load   = 1'b1;
                            o_reply_code   = RSP_OK;
                            o_state_next   = REPLY;
                        end
                        CMD_DUMP: begin
                            o_dbg_addr_clear = 1'b1;
                            o_state_next     = DUMP_CNT_LO;
                        end
                        default: begin
                            o_reply_load = 1'b1;
                            o_reply_code = RSP_UNK;
                            o_state_next = REPLY;
                        end
                    endcase
                end
            end

            LOAD_LEN_LO: begin
                if (~i_rx_empty) begin
                    o_rx_read     = 1'b1;
                    o_len_lo_load = 1'b1;
                    o_state_next  = LOAD_LEN_HI;
                end
            end

            LOAD_LEN_HI: begin
                if (~i_rx_empty) begin
                    o_rx_read     = 1'b1;
                    o_len_hi_load = 1'b1;
                    o_cnt_clear   = 1'b1;
                    o_ovf_load    = 1'b1;
                    o_state_next  = i_len_zero ? LOAD_FILL : LOAD_DATA;
                end
            end

            LOAD_DATA: begin
                if (~i_rx_empty) begin
                    o_rx_read      = 1'b1;
                    o_imem_we_next = i_in_range;       // lo que no entra se descarta
                    o_imem_load    = 1'b1;
                    o_cnt_inc      = 1'b1;
                    if (i_load_last)
                        o_state_next = LOAD_FILL;
                end
            end

            LOAD_FILL: begin                           // resto de la memoria con NOP
                if (i_in_range) begin
                    o_imem_we_next = 1'b1;
                    o_imem_load    = 1'b1;
                    o_imem_fill    = 1'b1;
                    o_cnt_inc      = 1'b1;
                end
                else begin
                    o_reply_load = 1'b1;
                    o_reply_code = i_overflow ? RSP_ERR : RSP_OK;
                    o_state_next = REPLY;
                end
            end

            REPLY: begin
                if (~i_tx_full) begin
                    o_tx_write   = 1'b1;
                    o_state_next = IDLE;
                end
            end

            DUMP_CNT_LO: begin
                if (~i_tx_full) begin
                    o_tx_write      = 1'b1;
                    o_send_count_lo = 1'b1;
                    o_state_next    = DUMP_CNT_HI;
                end
            end

            DUMP_CNT_HI: begin
                if (~i_tx_full) begin
                    o_tx_write      = 1'b1;
                    o_send_count_hi = 1'b1;
                    o_state_next    = i_dbg_count_zero ? IDLE : DUMP_ADDR;
                end
            end

            DUMP_ADDR: begin                           // direccion estable un ciclo
                o_state_next = DUMP_LATCH;
            end

            DUMP_LATCH: begin
                o_word_load      = 1'b1;
                o_byte_idx_clear = 1'b1;
                o_state_next     = DUMP_BYTE;
            end

            DUMP_BYTE: begin
                if (~i_tx_full) begin
                    o_tx_write     = 1'b1;
                    o_send_word    = 1'b1;
                    o_word_shift   = 1'b1;
                    o_byte_idx_inc = 1'b1;
                    if (i_byte_last) begin
                        if (i_dbg_last)
                            o_state_next = IDLE;
                        else begin
                            o_dbg_addr_inc = 1'b1;
                            o_state_next   = DUMP_ADDR;
                        end
                    end
                end
            end

            default: begin
                o_state_next = IDLE;
            end
        endcase
    end

    assign o_cpu_enable = (i_run | i_step) & ~i_cpu_halt & ~dumping;
    assign o_cpu_reset  = i_reset | i_cpu_rst | loading;
endmodule
