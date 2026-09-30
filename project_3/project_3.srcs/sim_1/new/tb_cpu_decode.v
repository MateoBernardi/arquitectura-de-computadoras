`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_cpu_decode: demostracion de IF -> IF/ID -> ID sobre cpu (sin UART)
//
// Carga decode_demo.hex en instru_mem, habilita el CPU como lo haria la debug
// unit (enable = run & ~halt) y en cada ciclo id_monitor imprime lo que sale
// de ID. Se chequea la secuencia que tiene que llegar a ID:
//   NOP de reset, 0x00 .. 0x28, NOP (instruccion salteada por el JAL), 0x34,
//   0x38 (ebreak: halt).
// Los branches y JALR se resuelven en EX (todavia no existe): no redirigen.
//
// Icarus (desde la raiz del proyecto):
//   iverilog -Wall -g2005 -I rtl -s tb_cpu_decode -o tb_cpu \
//            sim/tb_cpu_decode.v sim/id_monitor.v rtl/*.v
//   vvp tb_cpu +prog=host/decode_demo.hex
// XSIM: agregar decode_demo.hex a las fuentes de simulacion y run -all
// -----------------------------------------------------------------------------
module tb_cpu_decode;
    `include "riscv_defs.vh"

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg         rst, run;
    wire        halt;
    wire [31:0] dbg_data;
    wire [15:0] dbg_count;

    cpu #(
        .IMEM_ADDR_W(8)
    ) dut (
        .i_clk              (clk),
        .i_reset            (rst),
        .i_enable           (run & ~halt),
        .o_halt             (halt),
        .i_imem_write_enable(1'b0),
        .i_imem_write_addr  (8'd0),
        .i_imem_write_data  (8'd0),
        .i_dbg_addr         (16'd0),
        .o_dbg_data         (dbg_data),
        .o_dbg_count        (dbg_count)
    );

    // Salidas de ID (tal como las va a recibir ID/EX)
    wire [31:0] m_instr    = dut.ifid_instruction;
    wire [31:0] m_pc       = dut.id_pc;
    wire [31:0] m_rs1_data = dut.id_rs1_data;
    wire [31:0] m_rs2_data = dut.id_rs2_data;
    wire [31:0] m_imm      = dut.id_imm;
    wire [4:0]  m_rs1      = dut.id_rs1;
    wire [4:0]  m_rs2      = dut.id_rs2;
    wire [4:0]  m_rd       = dut.id_rd;
    wire [2:0]  m_funct3   = dut.id_funct3;
    wire [1:0]  m_alu_a    = dut.id_alu_src_a;
    wire        m_alu_b    = dut.id_alu_src_b;
    wire [3:0]  m_alu_op   = dut.id_alu_op;
    wire        m_wr       = dut.id_reg_write;
    wire [1:0]  m_res      = dut.id_result_src;
    wire        m_mr       = dut.id_mem_read;
    wire        m_mw       = dut.id_mem_write;
    wire        m_br       = dut.id_branch;
    wire        m_jal      = dut.id_jal;
    wire        m_jalr     = dut.id_jalr;
    wire        m_halt     = dut.id_halt;
    wire        m_illegal  = dut.id_illegal;
    wire [31:0] rebuilt;

    id_monitor #(.DETAIL(1)) mon (
        .i_clock      (clk),
        .i_sample     (run),
        .i_instruction(m_instr),
        .i_pc         (m_pc),
        .i_rs1_data   (m_rs1_data),
        .i_rs2_data   (m_rs2_data),
        .i_imm        (m_imm),
        .i_rs1        (m_rs1),
        .i_rs2        (m_rs2),
        .i_rd         (m_rd),
        .i_funct3     (m_funct3),
        .i_alu_src_a  (m_alu_a),
        .i_alu_src_b  (m_alu_b),
        .i_alu_op     (m_alu_op),
        .i_reg_write  (m_wr),
        .i_result_src (m_res),
        .i_mem_read   (m_mr),
        .i_mem_write  (m_mw),
        .i_branch     (m_br),
        .i_jal        (m_jal),
        .i_jalr       (m_jalr),
        .i_halt       (m_halt),
        .i_illegal    (m_illegal),
        .o_rebuilt    (rebuilt)
    );

    // Secuencia esperada en ID
    localparam integer N_EXP = 16;
    reg [31:0] exp_pc    [0:N_EXP-1];
    reg [31:0] exp_instr [0:N_EXP-1];
    reg [31:0] prog      [0:63];
    reg [8*256-1:0] prog_file;
    integer i, k, errors;

    initial begin
        errors = 0;
        rst = 1'b1;
        run = 1'b0;
        for (i = 0; i < 64; i = i + 1) prog[i] = INSTR_NOP;
        if (!$value$plusargs("prog=%s", prog_file)) prog_file = "decode_demo.hex";
        #1;                                            // despues del relleno con NOP de instru_mem
        $readmemh(prog_file, prog);
        for (i = 0; i < 64; i = i + 1) dut.u_if.u_instru_mem.mem[i] = prog[i];

        exp_pc[0] = 32'h00; exp_instr[0] = INSTR_NOP;  // estado de reset
        for (i = 0; i <= 10; i = i + 1) begin          // 0x00 .. 0x28
            exp_pc[i + 1]    = 4 * i;
            exp_instr[i + 1] = prog[i];
        end
        exp_pc[12] = 32'h2c; exp_instr[12] = INSTR_NOP; // salteada por el JAL
        exp_pc[13] = 32'h34; exp_instr[13] = prog[13];
        exp_pc[14] = 32'h38; exp_instr[14] = prog[14];  // ebreak

        #100;                                          // GSR de XSIM
        @(negedge clk);
        rst = 1'b0;
        run = 1'b1;
        k = 0;
        while (!(halt && k > 0) && k < N_EXP) begin
            @(posedge clk);
            if (k < 15 && (m_pc !== exp_pc[k] || m_instr !== exp_instr[k] || m_illegal ||
                           rebuilt !== exp_instr[k])) begin
                errors = errors + 1;
                $display("FAIL paso %0d: ID pc=%h instr=%h reconstruida=%h, esperado pc=%h instr=%h",
                         k, m_pc, m_instr, rebuilt, exp_pc[k], exp_instr[k]);
            end
            k = k + 1;
        end
        @(negedge clk);
        run = 1'b0;

        if (k != 15 || !halt) begin
            errors = errors + 1;
            $display("FAIL: se esperaba halt en el paso 14 (llegaron %0d pasos, halt=%b)", k, halt);
        end
        if (errors == 0)
            $display("PASS: %0d instrucciones por ID, JAL redirige y EBREAK frena", k);
        else
            $display("FAIL: %0d errores", errors);
        $finish;
    end
endmodule
