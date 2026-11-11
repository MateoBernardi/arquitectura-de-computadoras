`timescale 1ns / 1ps

// hazard_unit_precise — VARIANTE propuesta (no está en el diseño).
//
// Igual que hazard_unit, pero solo compara contra rs1/rs2 si la instrucción
// en ID de verdad usa ese registro. En el formato I (addi, lw, jalr) los bits
// [24:20] son parte del inmediato; en U/J (lui, auipc, jal) también los [19:15].
//
// Mismo módulo y mismos puertos que flow/hazard_unit.v: se enchufa sin tocar
// riscv_pipeline.v.
module hazard_unit (
    input       ex_mem_read,
    input [4:0] ex_rd,
    input [4:0] id_rs1,
    input [4:0] id_rs2,
    input [6:0] id_opcode,
    output      stall
);
    // Clasificación por opcode[6:2] (los bits [1:0] valen siempre 11 en RV32I)
    reg reads_rs1, reads_rs2;
    always @(*) begin
        case (id_opcode)
            7'b0110011:                         // R:   add, sub, ...
                {reads_rs1, reads_rs2} = 2'b11;
            7'b0100011, 7'b1100011:             // S, B: sw, beq, ...
                {reads_rs1, reads_rs2} = 2'b11;
            7'b0010011, 7'b0000011, 7'b1100111: // I:   addi, lw, jalr
                {reads_rs1, reads_rs2} = 2'b10;
            default:                            // U, J, SYSTEM, inválidas
                {reads_rs1, reads_rs2} = 2'b00;
        endcase
    end

    assign stall = ex_mem_read && (ex_rd != 5'd0) &&
                   ((reads_rs1 && ex_rd == id_rs1) || (reads_rs2 && ex_rd == id_rs2));
endmodule
