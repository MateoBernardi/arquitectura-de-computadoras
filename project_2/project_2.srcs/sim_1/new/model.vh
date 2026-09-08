// model.vh - golden reference mirroring alu_tp2.v's combinational logic.
// Used only in testbenches for auto-checking; include inside a module body.
// No include guard: this (and alu_ops.vh) may be included in more than one
// module scope within the same simulation run, and a guard would silently
// blank out the second inclusion.

`include "alu_ops.vh"

function [7:0] golden_alu;
    input signed [7:0] a;
    input signed [7:0] b;
    input [5:0] op;
    reg [8:0] tmp;
    begin
        case (op)
            OP_ADD:  begin tmp = a + b; golden_alu = tmp[7:0]; end
            OP_SUB:  begin tmp = a - b; golden_alu = tmp[7:0]; end
            OP_AND:  golden_alu = a & b;
            OP_OR:   golden_alu = a | b;
            OP_XOR:  golden_alu = a ^ b;
            OP_SRA:  golden_alu = a >>> b;
            OP_SRL:  golden_alu = a >> b;
            OP_NOR:  golden_alu = ~(a | b);
            default: golden_alu = 8'b0;
        endcase
    end
endfunction
