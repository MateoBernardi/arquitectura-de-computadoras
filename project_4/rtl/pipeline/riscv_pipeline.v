`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: riscv_pipeline
// Description: 5-stage RV32I pipeline (IF, ID, EX, MEM, WB) with forwarding
//              (from MEM: ALU / pc+4 / LUI results; from WB: everything, loads
//              included), load-use stall and branch/jump flush (resolved in EX).
//
// Debug-unit interface:
//  - i_rst    : synchronous reset (PC=0, pipeline emptied, x1..x31 cleared).
//               dmem is NOT cleared. imem is kept.
//  - i_enable : 0 freezes every state element (no clock gating).
//  - o_halt   : level, 1 when an instruction that stops execution reaches WB:
//               ECALL, EBREAK or a fatal trap. Everything older has retired,
//               the instruction itself wrote nothing, and nothing younger was
//               allowed to execute. Debug words 86..88 say why (see below).
//
// Exceptions (RV32I without the privileged architecture: no CSRs). Every
// exception is a fatal trap: the CPU halts and the execution environment (the
// debug unit) reports it. Codes are the standard mcause exception codes:
//    0 instruction address misaligned (taken jump/branch to pc % 4 != 0)
//    1 instruction access fault       (fetch outside the imem)
//    2 illegal instruction            (anything that is not RV32I, incl. CSR*)
//    3 breakpoint                     (EBREAK)
//    4 / 6 load / store address misaligned
//    5 / 7 load / store access fault  (outside the dmem)
//   11 environment call               (ECALL)
//  - imem write port: byte-wide, used to load a program.
//  - debug bus: o_dbg_data = word i_dbg_addr of the map below (combinational).
//               o_dbg_count = number of words. New words go at the end.
//
// Debug map (32-bit words):
//    0 PC (IF)
//    1 IF/ID pc                2 IF/ID instr
//    3 ID/EX ctrl  [0]reg_write [1]mem_read [2]mem_write [3]branch [4]jump
//                  [5]is_jalr [6]is_auipc [7]halt [8]alu_src [10:9]wb_sel [14:11]alu_op
//    4 ID/EX fields [4:0]rs1 [9:5]rs2 [14:10]rd [17:15]funct3
//    5 ID/EX pc   6 rdata1   7 rdata2   8 imm
//    9 EX alu_a (after forwarding)   10 EX alu_b   11 EX alu_out   12 EX redirect target
//   13 EX flags [0]stall [1]flush_if_id [2]flush_id_ex [3]redirect [4]branch_taken
//               [5]zero [6]overflow [7]halting [9:8]forward_a [11:10]forward_b
//   14 EX/MEM ctrl [0]reg_write [1]mem_read [2]mem_write [3]halt [5:4]wb_sel
//   15 EX/MEM alu_out   16 rdata2   17 fields [4:0]rd [7:5]funct3
//   18 MEM dmem read data
//   19 MEM/WB ctrl [0]reg_write [1]halt   20 MEM/WB result   21 MEM/WB rd
//   22..53 x0..x31
//   54..85 dmem words 0..31
//   86 trap cause (code above)   87 trap pc   88 trap value (faulting address)
//      valid while o_halt = 1
//////////////////////////////////////////////////////////////////////////////////
module riscv_pipeline #(
    parameter IMEM_ADDR_W = 10,           // imem size: 2**IMEM_ADDR_W bytes
    parameter IMEM_INIT   = "",
    parameter DMEM_DEPTH  = 256           // dmem size in words (simulation uses more)
) (
`ifdef RISCV_FORMAL
    `RVFI_OUTPUTS,                // puertos RVFI: solo para riscv-formal
`endif
    input  wire                   clk,
    input  wire                   i_rst,
    input  wire                   i_enable,
    output wire                   o_halt,
    // imem load port
    input  wire                   i_imem_we,
    input  wire [IMEM_ADDR_W-1:0] i_imem_waddr,
    input  wire [7:0]             i_imem_wdata,
    // debug bus
    input  wire [15:0]            i_dbg_addr,
    output reg  [31:0]            o_dbg_data,
    output wire [15:0]            o_dbg_count
);
    localparam [15:0] DBG_REGS       = 16'd22;
    localparam [15:0] DBG_DMEM       = DBG_REGS + 16'd32;
    localparam [15:0] DBG_DMEM_WORDS = 16'd32;
    localparam [15:0] DBG_TRAP       = DBG_DMEM + DBG_DMEM_WORDS;
    localparam [15:0] DBG_COUNT      = DBG_TRAP + 16'd3;
    localparam [32:0] IMEM_BYTES     = 33'd1 << IMEM_ADDR_W;
    localparam [32:0] DMEM_BYTES     = 33'd4 * DMEM_DEPTH;

    wire en  = i_enable;
    wire [15:0] dbg_reg_off  = i_dbg_addr - DBG_REGS;
    wire [15:0] dbg_dmem_off = i_dbg_addr - DBG_DMEM;
    wire [4:0]  dbg_reg_idx  = dbg_reg_off[4:0];
    wire [7:0]  dbg_dmem_idx = dbg_dmem_off[7:0];
    wire rst = i_rst;

    // ------------------------------------------------------------ hazard / flush
    wire        stall, redirect, halting, ex_stop;
    wire        stop_fetch = ex_stop | halting;     // nothing younger than a halt may run
    wire        flush_if_id_r, flush_id_ex_r;
    wire        flush_if_id = flush_if_id_r | stop_fetch;
    wire        flush_id_ex = flush_id_ex_r | stop_fetch | stall;   // stall -> bubble

    // ------------------------------------------------------------------- IF
    reg  [31:0] pc;
    wire [31:0] pc_next;
    wire [31:0] if_inst;
    wire        pc_en = en & ~stall & ~stop_fetch;

    always @(posedge clk) begin
        if (rst)        pc <= 32'd0;
        else if (pc_en) pc <= pc_next;
    end

    imem #(.ADDR_W(IMEM_ADDR_W), .INIT_FILE(IMEM_INIT)) u_imem (
        .clk(clk), .addr(pc), .instr(if_inst),
        .wr_en(i_imem_we), .wr_addr(i_imem_waddr), .wr_data(i_imem_wdata)
    );

    wire [31:0] id_pc, id_inst;
    if_id_reg u_if_id (
        .clk(clk), .rst(rst), .en(en), .stall(stall), .flush(flush_if_id),
        .if_pc(pc), .if_inst(if_inst),
        .id_pc(id_pc), .id_inst(id_inst)
    );

    // ------------------------------------------------------------------- ID
    wire [6:0] id_opcode = id_inst[6:0];
    wire [4:0] id_rd     = id_inst[11:7];
    wire [2:0] id_funct3 = id_inst[14:12];
    wire [4:0] id_rs1    = id_inst[19:15];
    wire [4:0] id_rs2    = id_inst[24:20];
    wire [6:0] id_funct7 = id_inst[31:25];

    wire       id_reg_write, id_alu_src, id_mem_read, id_mem_write, id_branch, id_jump, id_halt;
    wire [1:0] id_wb_sel;
    wire [3:0] id_alu_op;
    wire [2:0] id_imm_sel;
    control u_ctrl (
        .opcode(id_opcode), .funct3(id_funct3), .funct7(id_funct7),
        .reg_write(id_reg_write), .alu_src(id_alu_src),
        .mem_read(id_mem_read), .mem_write(id_mem_write),
        .branch(id_branch), .jump(id_jump), .halt(id_halt),
        .wb_sel(id_wb_sel), .alu_op(id_alu_op), .imm_sel(id_imm_sel)
    );
    wire id_is_jalr  = (id_opcode == 7'b1100111);
    wire id_is_auipc = (id_opcode == 7'b0010111);

    // instructions that stop execution, detected in ID: they only take effect
    // when they reach EX (a younger wrong-path one is flushed like any other)
    wire id_illegal, id_ecall, id_ebreak;
    illegal_check u_illegal (
        .instr(id_inst), .illegal(id_illegal), .ecall(id_ecall), .ebreak(id_ebreak)
    );
    wire       id_fetch_fault = ({1'b0, id_pc} >= IMEM_BYTES);
    wire       id_stop  = id_fetch_fault | id_illegal | id_halt;
    wire [3:0] id_cause = id_fetch_fault ? 4'd1  :
                          id_illegal     ? 4'd2  :
                          id_ebreak      ? 4'd3  : 4'd11;
    // such an instruction does nothing else
    wire id_reg_write_q = id_reg_write & ~id_stop;
    wire id_mem_read_q  = id_mem_read  & ~id_stop;
    wire id_mem_write_q = id_mem_write & ~id_stop;
    wire id_branch_q    = id_branch    & ~id_stop;
    wire id_jump_q      = id_jump      & ~id_stop;

    wire [31:0] id_imm;
    immgen u_immgen (.instr(id_inst), .imm_sel(id_imm_sel), .imm(id_imm));

    wire [31:0] id_rdata1, id_rdata2, wb_result, dbg_reg_data;
    wire [4:0]  wb_rd;
    wire        wb_reg_write, wb_halt;
    regfile #(.BYPASS(1)) u_rf (
        .clk(clk), .rst(rst), .we(wb_reg_write & en),
        .waddr(wb_rd), .wdata(wb_result),
        .raddr1(id_rs1), .rdata1(id_rdata1),
        .raddr2(id_rs2), .rdata2(id_rdata2),
        .dbg_addr(dbg_reg_idx), .dbg_data(dbg_reg_data)
    );

    wire [31:0] id_pc4 = id_pc + 32'd4;

    // ID/EX
    wire        ex_reg_write, ex_alu_src, ex_mem_read, ex_mem_write;
    wire        ex_branch, ex_jump, ex_is_jalr, ex_is_auipc;
    wire [1:0]  ex_wb_sel;
    wire [3:0]  ex_alu_op;
    wire [31:0] ex_pc, ex_pc4, ex_rdata1, ex_rdata2, ex_imm;
    wire [4:0]  ex_rs1, ex_rs2, ex_rd;
    wire [2:0]  ex_funct3;
    wire [3:0]  ex_cause;
    wire        ex_halt;
    id_ex_reg u_id_ex (
        .clk(clk), .rst(rst), .en(en), .flush(flush_id_ex),
        .id_reg_write(id_reg_write_q), .id_alu_src(id_alu_src),
        .id_mem_read(id_mem_read_q), .id_mem_write(id_mem_write_q),
        .id_branch(id_branch_q), .id_jump(id_jump_q),
        .id_is_jalr(id_is_jalr), .id_is_auipc(id_is_auipc), .id_halt(id_stop),
        .id_wb_sel(id_wb_sel), .id_alu_op(id_alu_op),
        .id_pc(id_pc), .id_pc4(id_pc4), .id_rdata1(id_rdata1), .id_rdata2(id_rdata2),
        .id_imm(id_imm), .id_rs1(id_rs1), .id_rs2(id_rs2), .id_rd(id_rd),
        .id_funct3(id_funct3), .id_cause(id_cause),
        .ex_reg_write(ex_reg_write), .ex_alu_src(ex_alu_src),
        .ex_mem_read(ex_mem_read), .ex_mem_write(ex_mem_write),
        .ex_branch(ex_branch), .ex_jump(ex_jump),
        .ex_is_jalr(ex_is_jalr), .ex_is_auipc(ex_is_auipc), .ex_halt(ex_halt),
        .ex_wb_sel(ex_wb_sel), .ex_alu_op(ex_alu_op),
        .ex_pc(ex_pc), .ex_pc4(ex_pc4), .ex_rdata1(ex_rdata1), .ex_rdata2(ex_rdata2),
        .ex_imm(ex_imm), .ex_rs1(ex_rs1), .ex_rs2(ex_rs2), .ex_rd(ex_rd),
        .ex_funct3(ex_funct3), .ex_cause(ex_cause)
    );

    hazard_unit u_hazard (
        .ex_mem_read(ex_mem_read), .ex_rd(ex_rd),
        .id_rs1(id_rs1), .id_rs2(id_rs2), .id_opcode(id_opcode), .stall(stall)
    );

    // ------------------------------------------------------------------- EX
    wire [1:0]  forward_a, forward_b;
    wire        mem_reg_write;
    wire [4:0]  mem_rd;
    wire [31:0] mem_result, mem_fwd;
    forward_unit u_fwd (
        .ex_rs1(ex_rs1), .ex_rs2(ex_rs2),
        .mem_rd(mem_rd), .mem_reg_write(mem_reg_write),
        .wb_rd(wb_rd), .wb_reg_write(wb_reg_write),
        .forward_a(forward_a), .forward_b(forward_b)
    );

    reg [31:0] fwd_a_val, fwd_b_val;
    always @(*) begin
        case (forward_a)
            2'b10:   fwd_a_val = mem_fwd;
            2'b01:   fwd_a_val = wb_result;
            default: fwd_a_val = ex_rdata1;
        endcase
        case (forward_b)
            2'b10:   fwd_b_val = mem_fwd;
            2'b01:   fwd_b_val = wb_result;
            default: fwd_b_val = ex_rdata2;
        endcase
    end

    wire [31:0] alu_a = ex_is_auipc ? ex_pc  : fwd_a_val;
    wire [31:0] alu_b = ex_alu_src  ? ex_imm : fwd_b_val;
    wire [31:0] alu_out;
    wire        alu_zero, alu_ovf, alu_lt, alu_ltu;
    alu_tp1 u_alu (
        .i_data_a(alu_a), .i_data_b(alu_b), .i_data_op(ex_alu_op),
        .o_data(alu_out), .o_z(alu_zero), .o_o(alu_ovf),
        .o_lt(alu_lt), .o_ltu(alu_ltu)
    );

    wire        bu_taken;
    wire [31:0] bu_target;
    branch_unit u_bu (
        .funct3(ex_funct3), .zero(alu_zero), .alu_lt(alu_lt), .alu_ltu(alu_ltu),
        .pc(ex_pc), .b_imm(ex_imm),
        .branch_taken(bu_taken), .branch_target(bu_target)
    );

    wire        branch_taken = ex_branch & bu_taken;
    assign      redirect     = branch_taken | ex_jump;
    // BRANCH/JAL: pc + imm (same adder in branch_unit); JALR: (rs1 + imm) & ~1
    wire [31:0] redirect_target = ex_is_jalr ? (alu_out & ~32'h1) : bu_target;
    assign      pc_next      = redirect ? redirect_target : (pc + 32'd4);

    flush_unit u_flush (
        .redirect(redirect),
        .flush_if_id(flush_if_id_r), .flush_id_ex(flush_id_ex_r)
    );

    // exceptions detected in EX (misaligned jump target, misaligned or
    // out-of-range load/store)
    wire        ex_exc;
    wire [3:0]  ex_exc_cause;
    wire [31:0] ex_exc_tval;
    trap_unit #(.DMEM_BYTES(DMEM_BYTES)) u_trap (
        .redirect(redirect), .redirect_target(redirect_target),
        .mem_read(ex_mem_read), .mem_write(ex_mem_write),
        .funct3(ex_funct3), .addr(alu_out),
        .exc(ex_exc), .cause(ex_exc_cause), .tval(ex_exc_tval)
    );
    // the instruction in EX stops execution (from ID: ecall/ebreak/illegal/fetch
    // fault; from EX: an exception). It reaches WB writing nothing.
    assign ex_stop = ex_halt | ex_exc;

    // halting: sticky from the moment a stopping instruction reaches EX, until reset
    reg halting_r;
    always @(posedge clk) begin
        if (rst)               halting_r <= 1'b0;
        else if (en && ex_stop) halting_r <= 1'b1;
    end
    assign halting = halting_r;

    // why it stopped (debug words 86..88)
    reg [3:0]  trap_cause;
    reg [31:0] trap_pc, trap_tval;
    always @(posedge clk) begin
        if (rst) begin
            trap_cause <= 4'd0; trap_pc <= 32'd0; trap_tval <= 32'd0;
        end else if (en && ex_stop && !halting_r) begin
            trap_cause <= ex_halt ? ex_cause : ex_exc_cause;
            trap_pc    <= ex_pc;
            trap_tval  <= ex_halt ? ((ex_cause == 4'd1) ? ex_pc : 32'd0) : ex_exc_tval;
        end
    end

    // EX/MEM
    wire        mem_mem_read, mem_mem_write, mem_halt;
    wire [1:0]  mem_wb_sel;
    wire [31:0] mem_alu_out, mem_rdata2, mem_pc4, mem_imm;
    wire [2:0]  mem_funct3;
    ex_mem_reg u_ex_mem (
        .clk(clk), .rst(rst), .en(en),
        .ex_reg_write(ex_reg_write & ~ex_exc), .ex_mem_read(ex_mem_read & ~ex_exc),
        .ex_mem_write(ex_mem_write & ~ex_exc), .ex_halt(ex_stop),
        .ex_wb_sel(ex_wb_sel), .ex_alu_out(alu_out), .ex_rdata2(fwd_b_val),
        .ex_pc4(ex_pc4), .ex_imm(ex_imm), .ex_rd(ex_rd), .ex_funct3(ex_funct3),
        .mem_reg_write(mem_reg_write), .mem_mem_read(mem_mem_read),
        .mem_mem_write(mem_mem_write), .mem_halt(mem_halt),
        .mem_wb_sel(mem_wb_sel), .mem_alu_out(mem_alu_out), .mem_rdata2(mem_rdata2),
        .mem_pc4(mem_pc4), .mem_imm(mem_imm), .mem_rd(mem_rd), .mem_funct3(mem_funct3)
    );

    // ------------------------------------------------------------------ MEM
    wire [31:0] mem_rdata, dbg_dmem_data;
    dmem #(.DEPTH(DMEM_DEPTH)) u_dmem (
        .clk(clk), .we(mem_mem_write & en & ~rst),   // reset: nothing is written
        .addr(mem_alu_out), .wdata(mem_rdata2),
        .funct3(mem_funct3), .rdata(mem_rdata),
        .dbg_addr(dbg_dmem_idx), .dbg_data(dbg_dmem_data)
    );

    // value this instruction produces (goes to WB)
    reg [31:0] mem_result_r;
    always @(*) begin
        case (mem_wb_sel)
            2'b00:   mem_result_r = mem_alu_out;
            2'b01:   mem_result_r = mem_rdata;
            2'b10:   mem_result_r = mem_pc4;
            default: mem_result_r = mem_imm;      // LUI
        endcase
    end
    assign mem_result = mem_result_r;

    // value forwarded from MEM to EX: the same, except it is never the dmem read data.
    // A load is never in MEM with its consumer in EX: the load-use stall puts a bubble
    // between them, and the load is forwarded from WB. Leaving the dmem out of this mux
    // takes the path dmem -> forwarding -> ALU out of a single cycle (verif/README.md,
    // "Variantes": +40 % fmax, the same cycles).
    assign mem_fwd = (mem_wb_sel == 2'b10) ? mem_pc4 :
                     (mem_wb_sel == 2'b11) ? mem_imm : mem_alu_out;

    mem_wb_reg u_mem_wb (
        .clk(clk), .rst(rst), .en(en),
        .mem_reg_write(mem_reg_write), .mem_halt(mem_halt),
        .mem_result(mem_result), .mem_rd(mem_rd),
        .wb_reg_write(wb_reg_write), .wb_halt(wb_halt),
        .wb_result(wb_result), .wb_rd(wb_rd)
    );

    assign o_halt = wb_halt;

    // ---------------------------------------------------------------- debug
    wire [31:0] dbg_idex_ctrl  = {17'd0, ex_alu_op, ex_wb_sel, ex_alu_src, ex_halt, ex_is_auipc,
                                  ex_is_jalr, ex_jump, ex_branch, ex_mem_write, ex_mem_read,
                                  ex_reg_write};
    wire [31:0] dbg_idex_field = {14'd0, ex_funct3, ex_rd, ex_rs2, ex_rs1};
    wire [31:0] dbg_ex_flags   = {20'd0, forward_b, forward_a, halting, alu_ovf, alu_zero,
                                  branch_taken, redirect, flush_id_ex, flush_if_id, stall};
    wire [31:0] dbg_exmem_ctrl = {26'd0, mem_wb_sel, mem_halt, mem_mem_write, mem_mem_read,
                                  mem_reg_write};
    wire [31:0] dbg_exmem_fld  = {24'd0, mem_funct3, mem_rd};
    wire [31:0] dbg_memwb_ctrl = {30'd0, wb_halt, wb_reg_write};

    always @(*) begin
        case (i_dbg_addr)
            16'd0:   o_dbg_data = pc;
            16'd1:   o_dbg_data = id_pc;
            16'd2:   o_dbg_data = id_inst;
            16'd3:   o_dbg_data = dbg_idex_ctrl;
            16'd4:   o_dbg_data = dbg_idex_field;
            16'd5:   o_dbg_data = ex_pc;
            16'd6:   o_dbg_data = ex_rdata1;
            16'd7:   o_dbg_data = ex_rdata2;
            16'd8:   o_dbg_data = ex_imm;
            16'd9:   o_dbg_data = alu_a;
            16'd10:  o_dbg_data = alu_b;
            16'd11:  o_dbg_data = alu_out;
            16'd12:  o_dbg_data = redirect_target;
            16'd13:  o_dbg_data = dbg_ex_flags;
            16'd14:  o_dbg_data = dbg_exmem_ctrl;
            16'd15:  o_dbg_data = mem_alu_out;
            16'd16:  o_dbg_data = mem_rdata2;
            16'd17:  o_dbg_data = dbg_exmem_fld;
            16'd18:  o_dbg_data = mem_rdata;
            16'd19:  o_dbg_data = dbg_memwb_ctrl;
            16'd20:  o_dbg_data = wb_result;
            16'd21:  o_dbg_data = {27'd0, wb_rd};
            default: begin
                if (i_dbg_addr >= DBG_REGS && i_dbg_addr < DBG_DMEM)
                    o_dbg_data = (dbg_reg_idx == 5'd0) ? 32'd0 : dbg_reg_data;
                else if (i_dbg_addr >= DBG_DMEM && i_dbg_addr < DBG_TRAP)
                    o_dbg_data = dbg_dmem_data;
                else if (i_dbg_addr == DBG_TRAP)
                    o_dbg_data = {28'd0, trap_cause};
                else if (i_dbg_addr == DBG_TRAP + 16'd1)
                    o_dbg_data = trap_pc;
                else if (i_dbg_addr == DBG_TRAP + 16'd2)
                    o_dbg_data = trap_tval;
                else
                    o_dbg_data = 32'd0;
            end
        endcase
    end

    assign o_dbg_count = DBG_COUNT;
`ifdef RISCV_FORMAL
    // ======================================================================
    // RVFI (RISC-V Formal Interface) — SOLO para verificación con riscv-formal.
    // Vivado no define RISCV_FORMAL, así que nunca sintetiza este bloque.
    //
    // Cada instrucción lleva consigo, etapa por etapa, lo que RVFI informa al
    // retirarse en WB: su PC, su codificación, los operandos que REALMENTE
    // usó en EX (después del forwarding) y su acceso a memoria. Estos
    // registros son copias pasivas: no influyen en el funcionamiento del CPU.
    // ======================================================================

    // ---- IF/ID: ¿hay una instrucción real (no un NOP de flush/reset)?
    reg f_id_valid;
    always @(posedge clk) begin
        if (rst)              f_id_valid <= 1'b0;
        else if (en) begin
            if (flush_if_id)  f_id_valid <= 1'b0;
            else if (!stall)  f_id_valid <= 1'b1;
        end
    end

    // ---- ID/EX
    reg        f_ex_valid;
    reg [31:0] f_ex_insn;
    always @(posedge clk) begin
        if (rst || (en && flush_id_ex)) f_ex_valid <= 1'b0;
        else if (en) begin
            f_ex_valid <= f_id_valid;
            f_ex_insn  <= id_inst;
        end
    end

    // ---- EX: próximo PC y si la instrucción detiene la ejecución (trap)
    wire [31:0] f_ex_pc_wdata = redirect ? redirect_target : ex_pc + 32'd4;
    wire        f_ex_trap     = ex_stop;

    // ---- EX/MEM
    reg        f_mem_valid, f_mem_trap;
    reg [31:0] f_mem_insn, f_mem_pc, f_mem_pc_wdata, f_mem_rs1_rdata, f_mem_rs2_rdata;
    reg [4:0]  f_mem_rs1, f_mem_rs2;
    always @(posedge clk) begin
        if (rst) f_mem_valid <= 1'b0;
        else if (en) begin
            f_mem_valid     <= f_ex_valid;
            f_mem_trap      <= f_ex_trap;
            f_mem_insn      <= f_ex_insn;
            f_mem_pc        <= ex_pc;
            f_mem_pc_wdata  <= f_ex_pc_wdata;
            f_mem_rs1       <= ex_rs1;
            f_mem_rs2       <= ex_rs2;
            f_mem_rs1_rdata <= fwd_a_val;
            f_mem_rs2_rdata <= fwd_b_val;
        end
    end

    // ---- MEM: el acceso a memoria, en formato RVFI (dirección alineada a 4,
    //      máscaras y datos en el carril de byte que corresponde)
    wire [1:0]  f_boff  = mem_alu_out[1:0];
    wire [3:0]  f_size  = (mem_funct3[1:0] == 2'd0) ? 4'b0001 :
                          (mem_funct3[1:0] == 2'd1) ? 4'b0011 : 4'b1111;
    wire [3:0]  f_mask  = f_size << f_boff;
    wire [31:0] f_mem_addr  = {mem_alu_out[31:2], 2'b00};
    wire [3:0]  f_mem_rmask = mem_mem_read  ? f_mask : 4'b0000;
    wire [3:0]  f_mem_wmask = mem_mem_write ? f_mask : 4'b0000;
    wire [31:0] f_mem_rdata = mem_rdata  << (8 * f_boff);
    wire [31:0] f_mem_wdata = mem_rdata2 << (8 * f_boff);

    // ---- MEM/WB
    reg        f_wb_valid, f_wb_trap;
    reg [31:0] f_wb_insn, f_wb_pc, f_wb_pc_wdata, f_wb_rs1_rdata, f_wb_rs2_rdata;
    reg [4:0]  f_wb_rs1, f_wb_rs2;
    reg [31:0] f_wb_mem_addr, f_wb_mem_rdata, f_wb_mem_wdata;
    reg [3:0]  f_wb_mem_rmask, f_wb_mem_wmask;
    always @(posedge clk) begin
        if (rst) f_wb_valid <= 1'b0;
        else if (en) begin
            f_wb_valid     <= f_mem_valid;
            f_wb_trap      <= f_mem_trap;
            f_wb_insn      <= f_mem_insn;
            f_wb_pc        <= f_mem_pc;
            f_wb_pc_wdata  <= f_mem_pc_wdata;
            f_wb_rs1       <= f_mem_rs1;
            f_wb_rs2       <= f_mem_rs2;
            f_wb_rs1_rdata <= f_mem_rs1_rdata;
            f_wb_rs2_rdata <= f_mem_rs2_rdata;
            f_wb_mem_addr  <= f_mem_addr;
            f_wb_mem_rmask <= f_mem_rmask;
            f_wb_mem_wmask <= f_mem_wmask;
            f_wb_mem_rdata <= f_mem_rdata;
            f_wb_mem_wdata <= f_mem_wdata;
        end
    end

    // ---- WB: la instrucción se retira (solo en los ciclos en que el CPU avanza)
    reg [63:0] f_order;
    always @(posedge clk) begin
        if (rst)             f_order <= 64'd0;
        else if (rvfi_valid) f_order <= f_order + 64'd1;
    end

    wire [4:0] f_rd = wb_reg_write ? wb_rd : 5'd0;
    assign rvfi_valid     = !rst && en && f_wb_valid;
    assign rvfi_order     = f_order;
    assign rvfi_insn      = f_wb_insn;
    assign rvfi_trap      = f_wb_trap;
    assign rvfi_halt      = wb_halt;
    assign rvfi_intr      = 1'b0;
    assign rvfi_mode      = 2'd3;
    assign rvfi_ixl       = 2'd1;
    assign rvfi_rs1_addr  = f_wb_rs1;
    assign rvfi_rs2_addr  = f_wb_rs2;
    assign rvfi_rs1_rdata = f_wb_rs1_rdata;
    assign rvfi_rs2_rdata = f_wb_rs2_rdata;
    assign rvfi_rd_addr   = f_rd;
    assign rvfi_rd_wdata  = (f_rd != 5'd0) ? wb_result : 32'd0;
    assign rvfi_pc_rdata  = f_wb_pc;
    assign rvfi_pc_wdata  = f_wb_pc_wdata;
    assign rvfi_mem_addr  = f_wb_mem_addr;
    assign rvfi_mem_rmask = f_wb_mem_rmask;
    assign rvfi_mem_wmask = f_wb_mem_wmask;
    assign rvfi_mem_rdata = f_wb_mem_rdata;
    assign rvfi_mem_wdata = f_wb_mem_wdata;
`endif
endmodule
