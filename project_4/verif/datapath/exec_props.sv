// exec_props — decodificación + inmediato + ALU + branch_unit contra el manual RV32I.
//
// Combinacional: para CUALQUIER instrucción aritmética o
// de salto legal y CUALQUIER valor de operandos, el resultado que calcula el
// CPU es el que dice la ISA. Complementa a riscv-formal (rvfi/): acá la
// decodificación y la ALU se prueban de forma exhaustiva y aislada.
//
// Las piezas del RTL se conectan EXACTAMENTE como en riscv_pipeline.v:
// control → immgen → muxes alu_a / alu_b → alu → branch_unit.

module exec_props (
    input [31:0] inst,      // la instrucción (el solver la elige)
    input [31:0] a, b,      // valores de rs1 y rs2 (ya reenviados)
    input [31:0] pc
);
    wire [6:0] opcode = inst[6:0];
    wire [2:0] f3     = inst[14:12];
    wire [6:0] f7     = inst[31:25];

    // ------------------------------------------------- RTL real
    wire       reg_write, alu_src, mem_read, mem_write, branch, jump, halt;
    wire [1:0] wb_sel;
    wire [3:0] alu_op;
    wire [2:0] imm_sel;
    control u_ctrl (.opcode(opcode), .funct3(f3), .funct7(f7),
        .reg_write(reg_write), .alu_src(alu_src), .mem_read(mem_read),
        .mem_write(mem_write), .branch(branch), .jump(jump), .halt(halt),
        .wb_sel(wb_sel), .alu_op(alu_op), .imm_sel(imm_sel));
    wire [31:0] imm;
    immgen u_imm (.instr(inst), .imm_sel(imm_sel), .imm(imm));

    wire is_auipc = (opcode == 7'b0010111);                 // como riscv_pipeline.v
    wire [31:0] alu_a = is_auipc ? pc  : a;
    wire [31:0] alu_b = alu_src  ? imm : b;
    wire [31:0] alu_out;
    wire z, o, lt, ltu;
    alu_tp1 u_alu (.i_data_a(alu_a), .i_data_b(alu_b), .i_data_op(alu_op),
        .o_data(alu_out), .o_z(z), .o_o(o), .o_lt(lt), .o_ltu(ltu));
    wire        taken;
    wire [31:0] target;
    branch_unit u_bu (.funct3(f3), .zero(z), .alu_lt(lt), .alu_ltu(ltu),
        .pc(pc), .b_imm(imm), .branch_taken(taken), .branch_target(target));

    // valor que escribe en rd (mux wb_sel de la etapa MEM, sin load ni PC+4)
    wire [31:0] result = (wb_sel == 2'b11) ? imm : alu_out;

    // -------------------------------------- especificación (manual RV32I)
    localparam OP = 7'b0110011, OP_IMM = 7'b0010011, BRANCH = 7'b1100011,
               LUI = 7'b0110111, AUIPC = 7'b0010111;
    wire [31:0] imm_i = {{20{inst[31]}}, inst[31:20]};
    wire [31:0] imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    wire [31:0] imm_u = {inst[31:12], 12'b0};

    function [31:0] spec_alu(input [2:0] fn, input alt, input [31:0] x, input [31:0] y);
        case (fn)
            3'd0: spec_alu = alt ? x - y : x + y;
            3'd1: spec_alu = x << y[4:0];
            3'd2: spec_alu = ($signed(x) < $signed(y)) ? 32'd1 : 32'd0;
            3'd3: spec_alu = (x < y) ? 32'd1 : 32'd0;
            3'd4: spec_alu = x ^ y;
            3'd5: spec_alu = alt ? $unsigned($signed(x) >>> y[4:0]) : x >> y[4:0];
            3'd6: spec_alu = x | y;
            3'd7: spec_alu = x & y;
        endcase
    endfunction
    reg spec_taken;
    always @(*) case (f3)
        3'd0: spec_taken = (a == b);
        3'd1: spec_taken = (a != b);
        3'd4: spec_taken = ($signed(a) <  $signed(b));
        3'd5: spec_taken = ($signed(a) >= $signed(b));
        3'd6: spec_taken = (a <  b);
        default: spec_taken = (a >= b);
    endcase

    reg [31:0] spec_result;
    always @(*) case (opcode)
        OP:      spec_result = spec_alu(f3, inst[30], a, b);
        OP_IMM:  spec_result = spec_alu(f3, f3 == 3'd5 && inst[30], a, imm_i);
        LUI:     spec_result = imm_u;
        default: spec_result = pc + imm_u;              // AUIPC
    endcase

    // Codificaciones legales de RV32I
    wire legal_op  = opcode == OP &&
                     (f7 == 7'h00 || (f7 == 7'h20 && (f3 == 3'd0 || f3 == 3'd5)));
    wire legal_imm = opcode == OP_IMM &&
                     ((f3 == 3'd1) ? f7 == 7'h00 : (f3 == 3'd5) ? (f7 == 7'h00 || f7 == 7'h20) : 1'b1);
    wire legal_br  = opcode == BRANCH && f3 != 3'd2 && f3 != 3'd3;
    wire is_arith  = legal_op || legal_imm || opcode == LUI || opcode == AUIPC;

    always @(*) begin
        assume (is_arith || legal_br);

        if (is_arith) begin
            e1_result:    assert (result == spec_result);
            e2_writes_rd: assert (reg_write && !mem_read && !mem_write && !branch && !jump);
        end
        if (legal_br) begin
            e3_taken:     assert ((branch && taken) == spec_taken);
            e4_target:    assert (target == pc + imm_b);
            e5_no_write:  assert (!reg_write && !mem_write && !jump);
        end

        // cada operación aparece (los covers garantizan que no sea vacuo)
        c_sra:  cover (opcode == OP_IMM && f3 == 3'd5 && inst[30] && a[31]);
        c_slt:  cover (opcode == OP && f3 == 3'd2 && spec_result == 32'd1);
        c_bgeu: cover (legal_br && f3 == 3'd7 && spec_taken);
    end
endmodule
