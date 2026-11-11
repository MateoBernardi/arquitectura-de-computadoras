`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Universidad Nacional de Cordoba
// Engineer: Mateo Bernardi, Pablo Castilla
// 
// Create Date: 07.09.2026
// Design Name: 
// Module Name: fifo
// Project Name: TP2
// Target Devices: 
// Tool Versions: 
// Description: Generic circular-buffer FIFO, depth 2**PTR_LEN, NB_DATA-bit words.
//              Reused for both the rx-side and tx-side queues.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module fifo
#(
    parameter NB_DATA = 8,
    parameter PTR_LEN = 4
)
(
    input  wire i_clk,
    input  wire i_reset,
    input  wire i_read_fifo,
    input  wire i_write_fifo,
    input  wire [NB_DATA-1:0] i_data_to_write,
    output wire o_fifo_is_empty,
    output wire o_fifo_is_full,
    output wire [NB_DATA-1:0] o_data_to_read
);

    localparam READ      = 2'b01;
    localparam WRITE     = 2'b10;
    localparam READWRITE = 2'b11;

    reg [NB_DATA-1:0] array [(2**PTR_LEN)-1:0];
    reg [PTR_LEN-1:0] write_ptr, write_ptr_next, write_ptr_ok;
    reg [PTR_LEN-1:0] read_ptr, read_ptr_next, read_ptr_ok;

    reg full, full_next;
    reg empty, empty_next;

    wire write_enable;

    always @(posedge i_clk) begin
        if (write_enable) begin
            array[write_ptr] <= i_data_to_write;
        end
    end

    assign o_data_to_read = array[read_ptr];
    assign write_enable   = i_write_fifo & ~full;

    always @(posedge i_clk) begin
        if (i_reset) begin
            write_ptr <= 0;
            read_ptr  <= 0;
            full      <= 0;
            empty     <= 1;
        end
        else begin
            write_ptr <= write_ptr_next;
            read_ptr  <= read_ptr_next;
            full      <= full_next;
            empty     <= empty_next;
        end
    end

    always @(*) begin
        write_ptr_ok = write_ptr + 1;
        read_ptr_ok  = read_ptr + 1;

        write_ptr_next = write_ptr;
        read_ptr_next  = read_ptr;
        full_next      = full;
        empty_next     = empty;

        case ({i_write_fifo, i_read_fifo})
            READ:
                if (~empty) begin
                    read_ptr_next = read_ptr_ok;
                    full_next     = 1'b0;
                    if (read_ptr_ok == write_ptr) begin
                        empty_next = 1'b1;
                    end
                end

            WRITE:
                if (~full) begin
                    write_ptr_next = write_ptr_ok;
                    empty_next     = 1'b0;
                    if (write_ptr_ok == read_ptr) begin
                        full_next = 1'b1;
                    end
                end

            READWRITE: begin
                write_ptr_next = write_ptr_ok;
                read_ptr_next  = read_ptr_ok;
            end

            default: ;
        endcase
    end

    assign o_fifo_is_full  = full;
    assign o_fifo_is_empty = empty;

endmodule