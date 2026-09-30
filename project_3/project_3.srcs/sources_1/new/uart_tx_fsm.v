`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
//
// Create Date: 28.09.2026
// Design Name:
// Module Name: uart_tx_fsm
// Project Name: TP2
// Target Devices:
// Tool Versions:
// Description: uart_tx state machine (combinational). From the current state,
//              i_tx_ready, the baud tick and the datapath status flags it
//              computes the next state, the datapath control signals and what
//              the line must show (fixed level or the current data bit).
//              The state register lives in uart_tx_regs; IDLE = 0 is its
//              reset value.
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created (split out of uart_tx)
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module uart_tx_fsm
(
    input  wire [1:0] i_state,
    input  wire       i_tx_ready,
    input  wire       i_tick,
    input  wire       i_s_last,     // s == N_TICKS - 1
    input  wire       i_n_last,     // n == NB_DATA - 1
    output reg  [1:0] o_state_next,
    output reg        o_s_clear,
    output reg        o_s_inc,
    output reg        o_n_clear,
    output reg        o_n_inc,
    output reg        o_load,       // load i_din into the send byte
    output reg        o_shift,      // shift the send byte right
    output reg        o_tx_data,    // 1: line = current data bit
    output reg        o_tx_level,   // line level when o_tx_data = 0
    output reg        o_tx_done
);

    localparam [1:0] IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;

    always @(*) begin
        o_state_next = i_state;
        o_s_clear    = 1'b0;
        o_s_inc      = 1'b0;
        o_n_clear    = 1'b0;
        o_n_inc      = 1'b0;
        o_load       = 1'b0;
        o_shift      = 1'b0;
        o_tx_data    = 1'b0;
        o_tx_level   = 1'b1;
        o_tx_done    = 1'b0;

        case (i_state)
            IDLE: begin
                o_tx_level = 1'b1;
                if (i_tx_ready) begin
                    o_state_next = START;
                    o_s_clear    = 1'b1;
                    o_load       = 1'b1;
                end
            end

            START: begin
                o_tx_level = 1'b0;
                if (i_tick) begin
                    if (i_s_last) begin
                        o_state_next = DATA;
                        o_s_clear    = 1'b1;
                        o_n_clear    = 1'b1;
                    end
                    else begin
                        o_s_inc = 1'b1;
                    end
                end
            end

            DATA: begin
                o_tx_data = 1'b1;
                if (i_tick) begin
                    if (i_s_last) begin
                        o_s_clear = 1'b1;
                        o_shift   = 1'b1;
                        if (i_n_last) begin
                            o_state_next = STOP;
                        end
                        else begin
                            o_n_inc = 1'b1;
                        end
                    end
                    else begin
                        o_s_inc = 1'b1;
                    end
                end
            end

            STOP: begin
                o_tx_level = 1'b1;
                if (i_tick) begin
                    if (i_s_last) begin
                        o_state_next = IDLE;
                        o_tx_done    = 1'b1;
                    end
                    else begin
                        o_s_inc = 1'b1;
                    end
                end
            end

            default: begin
                o_state_next = IDLE;
            end
        endcase
    end

endmodule
