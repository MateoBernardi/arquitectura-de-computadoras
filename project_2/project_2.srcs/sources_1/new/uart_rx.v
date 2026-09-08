`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
// 
// Create Date: 07.09.2026
// Design Name: 
// Module Name: uart_rx
// Project Name: TP2
// Target Devices: 
// Tool Versions: 
// Description: UART receiver, N_TICKS-oversampling, NB_DATA-bit frame (1 start
//              bit + 1 stop bit).
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - s/n widths and the mid-bit/full-bit thresholds now derive
//                 from N_TICKS/NB_DATA instead of being fixed at 16/8.
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module uart_rx
#(
    parameter NB_DATA = 8,
    parameter N_TICKS = 16
)
(
    input  wire i_clk,
    input  wire i_reset,
    input  wire i_rx,
    input  wire i_tick,
    output reg  o_rx_done,
    output wire [NB_DATA-1:0] o_dout
);

    localparam [1:0] IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;

    localparam NB_TICKCNT = $clog2(N_TICKS);
    localparam NB_BITCNT  = $clog2(NB_DATA);
    localparam HALF_TICK  = (N_TICKS / 2) - 1; // mid-bit sample point for the start bit

    reg [1:0] state, state_next;
    reg [NB_TICKCNT-1:0] s, s_next;
    reg [NB_BITCNT-1:0]  n, n_next;
    reg [NB_DATA-1:0] received_byte, received_byte_next;

    always @(posedge i_clk) begin
        if (i_reset) begin
            state         <= IDLE;
            s             <= 0;
            n             <= 0;
            received_byte <= 0;
        end
        else begin
            state         <= state_next;
            s             <= s_next;
            n             <= n_next;
            received_byte <= received_byte_next;
        end
    end

    always @(*) begin
        state_next         = state;
        o_rx_done          = 1'b0;
        s_next             = s;
        n_next             = n;
        received_byte_next = received_byte;

        case (state)
            IDLE:
                if (~i_rx) begin
                    state_next = START;
                    s_next     = 0;
                end

            START:
                if (i_tick) begin
                    if (s == HALF_TICK) begin
                        state_next = DATA;
                        s_next     = 0;
                        n_next     = 0;
                    end
                    else begin
                        s_next = s + 1;
                    end
                end

            DATA:
                if (i_tick) begin
                    if (s == (N_TICKS-1)) begin
                        s_next             = 0;
                        received_byte_next = {i_rx, received_byte[NB_DATA-1:1]};
                        if (n == (NB_DATA-1)) begin
                            state_next = STOP;
                        end
                        else begin
                            n_next = n + 1;
                        end
                    end
                    else begin
                        s_next = s + 1;
                    end
                end

            STOP:
                if (i_tick) begin
                    if (s == (N_TICKS-1)) begin
                        state_next = IDLE;
                        if (i_rx) begin
                            o_rx_done = 1'b1;
                        end
                    end
                    else begin
                        s_next = s + 1;
                    end
                end

            default:
                state_next = IDLE;
        endcase
    end

    assign o_dout = received_byte;

endmodule