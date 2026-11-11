// illegal_props — illegal_check contra la lista oficial de instrucciones RV32I.
//
// La especificación es independiente del RTL: las 40 instrucciones de RV32I como
// pares (máscara, patrón), copiados de riscv-opcodes (rv_i, rv32_i, rv_system),
// el repositorio de RISC-V International del que salen los encoders de binutils.
// Una instrucción es legal si y solo si coincide con alguno.
//
// Prueba exhaustiva (combinacional): para CUALQUIERA de las 2^32 instrucciones,
//   L1: illegal == !(coincide con alguna de las 40)
//   L2: ecall / ebreak valen exactamente para su única codificación.
module illegal_props (
    input [31:0] instr
);
    wire illegal, ecall, ebreak;
    illegal_check dut (.instr(instr), .illegal(illegal), .ecall(ecall), .ebreak(ebreak));

    function automatic is(input [31:0] mask, input [31:0] match);
        is = (instr & mask) == match;
    endfunction

    localparam [31:0] OPC = 32'h0000_007f, F3 = 32'h0000_707f, F7 = 32'hfe00_707f;
    wire legal =
        is(OPC, 32'h0000_0037) || is(OPC, 32'h0000_0017) ||                   // lui auipc
        is(OPC, 32'h0000_006f) || is(F3,  32'h0000_0067) ||                   // jal jalr
        is(F3, 32'h0000_0063) || is(F3, 32'h0000_1063) || is(F3, 32'h0000_4063) ||  // beq bne blt
        is(F3, 32'h0000_5063) || is(F3, 32'h0000_6063) || is(F3, 32'h0000_7063) ||  // bge bltu bgeu
        is(F3, 32'h0000_0003) || is(F3, 32'h0000_1003) || is(F3, 32'h0000_2003) ||  // lb lh lw
        is(F3, 32'h0000_4003) || is(F3, 32'h0000_5003) ||                           // lbu lhu
        is(F3, 32'h0000_0023) || is(F3, 32'h0000_1023) || is(F3, 32'h0000_2023) ||  // sb sh sw
        is(F3, 32'h0000_0013) || is(F3, 32'h0000_2013) || is(F3, 32'h0000_3013) ||  // addi slti sltiu
        is(F3, 32'h0000_4013) || is(F3, 32'h0000_6013) || is(F3, 32'h0000_7013) ||  // xori ori andi
        is(F7, 32'h0000_1013) || is(F7, 32'h0000_5013) || is(F7, 32'h4000_5013) ||  // slli srli srai
        is(F7, 32'h0000_0033) || is(F7, 32'h4000_0033) || is(F7, 32'h0000_1033) ||  // add sub sll
        is(F7, 32'h0000_2033) || is(F7, 32'h0000_3033) || is(F7, 32'h0000_4033) ||  // slt sltu xor
        is(F7, 32'h0000_5033) || is(F7, 32'h4000_5033) || is(F7, 32'h0000_6033) ||  // srl sra or
        is(F7, 32'h0000_7033) ||                                                    // and
        is(F3, 32'h0000_000f) ||                                                    // fence
        instr == 32'h0000_0073 || instr == 32'h0010_0073;                          // ecall ebreak

    always @(*) begin
        l1_illegal: assert (illegal == !legal);
        l2_ecall:   assert (ecall  == (instr == 32'h0000_0073));
        l2_ebreak:  assert (ebreak == (instr == 32'h0010_0073));
    end
endmodule
