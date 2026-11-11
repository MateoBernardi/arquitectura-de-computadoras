`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: trap_unit
// Description: Exceptions detected in EX, for the instruction in EX. Combinational.
//   - taken branch / jump to an address that is not a multiple of 4
//     (no C extension): instruction-address-misaligned, raised ON THE JUMP;
//   - load/store not naturally aligned: load/store-address-misaligned;
//   - load/store outside the dmem: load/store access fault.
//   Misaligned has priority over access fault
//   (MISALIGNED_LDST_EXCEPTION_PRIORITY = high).
//   Cause codes are the standard mcause exception codes.
//////////////////////////////////////////////////////////////////////////////////
module trap_unit #(
    parameter [32:0] DMEM_BYTES = 33'd1024     // valid data addresses: [0, DMEM_BYTES)
) (
    input  wire        redirect,
    input  wire [31:0] redirect_target,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [2:0]  funct3,             // access size: [1:0] = 00 byte, 01 half, 10 word
    input  wire [31:0] addr,               // load/store address (alu_out)
    output wire        exc,
    output wire        exc_mem,            // only the load/store part of exc
    output reg  [3:0]  cause,
    output reg  [31:0] tval                // faulting address
);
    localparam [3:0] C_PC_MISALIGNED = 4'd0, C_LD_MISALIGNED = 4'd4, C_LD_FAULT = 4'd5,
                     C_ST_MISALIGNED = 4'd6, C_ST_FAULT = 4'd7;

    wire pc_misaligned  = redirect && (redirect_target[1:0] != 2'b00);
    wire mem            = mem_read || mem_write;
    wire mem_misaligned = mem && ((funct3[1:0] == 2'b10 && addr[1:0] != 2'b00) ||
                                  (funct3[1:0] == 2'b01 && addr[0]   != 1'b0));
    wire mem_fault      = mem && ({1'b0, addr} >= DMEM_BYTES);

    assign exc_mem = mem_misaligned || mem_fault;
    assign exc     = pc_misaligned || exc_mem;

    always @(*) begin
        if (pc_misaligned) begin
            cause = C_PC_MISALIGNED;
            tval  = redirect_target;
        end else begin
            cause = mem_misaligned ? (mem_write ? C_ST_MISALIGNED : C_LD_MISALIGNED)
                                   : (mem_write ? C_ST_FAULT      : C_LD_FAULT);
            tval  = addr;
        end
    end
endmodule
