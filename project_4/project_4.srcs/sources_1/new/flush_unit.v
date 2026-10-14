`timescale 1ns / 1ps

// flush_unit: a taken branch or any jump is resolved in EX, so the two younger
// instructions (in IF/ID and in ID/EX's input) are wrong-path and become bubbles.
module flush_unit (
    input  redirect,      // EX: taken branch, JAL or JALR
    output flush_if_id,   // flush IF/ID register (the instr after the jump)
    output flush_id_ex    // flush ID/EX register (two after the jump)
);
    assign flush_if_id = redirect;
    assign flush_id_ex = redirect;
endmodule
