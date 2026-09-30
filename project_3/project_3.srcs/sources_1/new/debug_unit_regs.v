`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// debug_unit_regs: registros de la debug unit
//
// Estado de la FSM, modo (run) y pulsos (step, reset del CPU), y los registros
// del camino de datos. Reset sincronico activo en alto; todo resetea a 0
// (IDLE = 0 en debug_unit_fsm).
// -----------------------------------------------------------------------------
module debug_unit_regs #(
    parameter IMEM_ADDR_W = 8
) (
    input  wire                   i_clk,
    input  wire                   i_reset,
    input  wire [3:0]             i_state_next,
    input  wire                   i_run_next,
    input  wire                   i_step_next,
    input  wire                   i_cpu_rst_next,
    input  wire [15:0]            i_len_next,
    input  wire [17:0]            i_byte_cnt_next,
    input  wire                   i_overflow_next,
    input  wire [7:0]             i_reply_next,
    input  wire                   i_imem_we_next,
    input  wire [IMEM_ADDR_W-1:0] i_imem_addr_next,
    input  wire [7:0]             i_imem_data_next,
    input  wire [15:0]            i_dbg_addr_next,
    input  wire [31:0]            i_dbg_word_next,
    input  wire [1:0]             i_byte_idx_next,
    output reg  [3:0]             o_state,
    output reg                    o_run,
    output reg                    o_step,
    output reg                    o_cpu_rst,
    output reg  [15:0]            o_len,
    output reg  [17:0]            o_byte_cnt,
    output reg                    o_overflow,
    output reg  [7:0]             o_reply,
    output reg                    o_imem_we,
    output reg  [IMEM_ADDR_W-1:0] o_imem_addr,
    output reg  [7:0]             o_imem_data,
    output reg  [15:0]            o_dbg_addr,
    output reg  [31:0]            o_dbg_word,
    output reg  [1:0]             o_byte_idx
);
    always @(posedge i_clk) begin
        if (i_reset) begin
            o_state     <= 4'd0;
            o_run       <= 1'b0;
            o_step      <= 1'b0;
            o_cpu_rst   <= 1'b0;
            o_len       <= 16'd0;
            o_byte_cnt  <= 18'd0;
            o_overflow  <= 1'b0;
            o_reply     <= 8'd0;
            o_imem_we   <= 1'b0;
            o_imem_addr <= {IMEM_ADDR_W{1'b0}};
            o_imem_data <= 8'd0;
            o_dbg_addr  <= 16'd0;
            o_dbg_word  <= 32'd0;
            o_byte_idx  <= 2'd0;
        end
        else begin
            o_state     <= i_state_next;
            o_run       <= i_run_next;
            o_step      <= i_step_next;
            o_cpu_rst   <= i_cpu_rst_next;
            o_len       <= i_len_next;
            o_byte_cnt  <= i_byte_cnt_next;
            o_overflow  <= i_overflow_next;
            o_reply     <= i_reply_next;
            o_imem_we   <= i_imem_we_next;
            o_imem_addr <= i_imem_addr_next;
            o_imem_data <= i_imem_data_next;
            o_dbg_addr  <= i_dbg_addr_next;
            o_dbg_word  <= i_dbg_word_next;
            o_byte_idx  <= i_byte_idx_next;
        end
    end
endmodule
