`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// cpu: pipeline RV32I
//
// Estado actual: IF -> IF/ID -> ID. Las senales que van a llegar desde etapas
// que todavia no existen estan como constantes; al agregar cada etapa se
// instancia aca y se reemplazan. top_riscv, debug_unit y uart_core no cambian.
//
// - i_reset, i_enable: vienen de la debug unit. Todos los registros del
//   pipeline (y la escritura del banco de registros) usan el mismo reset y el
//   mismo enable.
// - o_halt: nivel; mientras vale 1 la debug unit no habilita el CPU.
//   PROVISORIO: sale de ID (ECALL/EBREAK en ID). Cuando exista WB, tiene que
//   salir de MEM/WB para que las instrucciones anteriores terminen.
// - Bus de debug: o_dbg_data = palabra i_dbg_addr del mapa de abajo.
//   o_dbg_count = cantidad de palabras. Puede ser combinacional o con un
//   ciclo de latencia (la debug unit espera un ciclo).
//   Al agregar etapas: sumar entradas al final, actualizar DBG_COUNT y
//   print_dump() en debug_host.py.
// -----------------------------------------------------------------------------
module cpu #(
    parameter IMEM_ADDR_W    = 8,
    parameter IMEM_INIT_FILE = ""
) (
    input  wire                   i_clk,
    input  wire                   i_reset,
    input  wire                   i_enable,
    output wire                   o_halt,
    // escritura de instru_mem (debug unit)
    input  wire                   i_imem_write_enable,
    input  wire [IMEM_ADDR_W-1:0] i_imem_write_addr,
    input  wire [7:0]             i_imem_write_data,
    // bus de debug
    input  wire [15:0]            i_dbg_addr,
    output reg  [31:0]            o_dbg_data,
    output wire [15:0]            o_dbg_count
);
    // IF -> IF/ID
    wire [31:0] if_imem_data;
    wire [31:0] if_pc;
    wire [31:0] if_pc4;

    // IF/ID -> ID
    wire [31:0] ifid_instruction;
    wire [31:0] ifid_pc;
    wire [31:0] ifid_pc4;

    // ID -> IF
    wire        id_jal;
    wire [31:0] id_jal_target;

    // ID -> ID/EX
    wire [31:0] id_pc, id_pc4, id_rs1_data, id_rs2_data, id_imm;
    wire [4:0]  id_rs1, id_rs2, id_rd;
    wire [2:0]  id_funct3;
    wire [1:0]  id_alu_src_a, id_result_src;
    wire        id_alu_src_b;
    wire [3:0]  id_alu_op;
    wire        id_reg_write, id_mem_read, id_mem_write, id_branch, id_jalr, id_halt, id_illegal;

    // Pendientes de las etapas siguientes
    wire        id_pc_stall  = 1'b0;                   // unidad de riesgos (con ID/EX)
    wire        ex_redirect  = 1'b0;                   // branch tomado o JALR en EX
    wire [31:0] ex_target    = 32'd0;
    wire        wb_reg_write = 1'b0;                   // escritura del banco de registros (WB)
    wire [4:0]  wb_rd        = 5'd0;
    wire [31:0] wb_data      = 32'd0;

    // Debug: registros x0..x31 en las direcciones DBG_REGS .. DBG_REGS + 31
    localparam [15:0] DBG_REGS  = 16'd9;
    localparam [15:0] DBG_COUNT = DBG_REGS + 16'd32;
    wire [15:0] dbg_reg_index = i_dbg_addr - DBG_REGS;
    wire [31:0] dbg_reg_data;

    instruction_fetch #(
        .IMEM_ADDR_W   (IMEM_ADDR_W),
        .IMEM_INIT_FILE(IMEM_INIT_FILE)
    ) u_if (
        .i_clock            (i_clk),
        .i_pc_reset         (i_reset),
        .i_pc_enable        (i_enable),
        .i_pc_stall         (id_pc_stall),
        .i_j_jal            (id_jal),
        .i_jump_addr        (id_jal_target),
        .i_ex_redirect      (ex_redirect),
        .i_ex_target        (ex_target),
        .i_instru_mem_enable(1'b1),
        .i_write_enable     (i_imem_write_enable),
        .i_write_addr       (i_imem_write_addr),
        .i_write_data       (i_imem_write_data),
        .o_imem_data        (if_imem_data),
        .o_pc               (if_pc),
        .o_pc4              (if_pc4)
    );

    if_id_reg u_if_id (
        .i_clock          (i_clk),
        .i_reset          (i_reset),
        .i_pipeline_enable(i_enable),
        .i_stall          (id_pc_stall),
        .i_flush_id       (id_jal),
        .i_flush_ex       (ex_redirect),
        .i_instruction    (if_imem_data),
        .i_pc             (if_pc),
        .i_pc4            (if_pc4),
        .o_instruction    (ifid_instruction),
        .o_pc             (ifid_pc),
        .o_pc4            (ifid_pc4)
    );

    instruction_decode u_id (
        .i_clock       (i_clk),
        .i_reset       (i_reset),
        .i_enable      (i_enable),
        .i_instruction (ifid_instruction),
        .i_pc          (ifid_pc),
        .i_pc4         (ifid_pc4),
        .i_wb_reg_write(wb_reg_write),
        .i_wb_rd       (wb_rd),
        .i_wb_data     (wb_data),
        .i_dbg_reg_addr(dbg_reg_index[4:0]),
        .o_dbg_reg_data(dbg_reg_data),
        .o_jal         (id_jal),
        .o_jal_target  (id_jal_target),
        .o_pc          (id_pc),
        .o_pc4         (id_pc4),
        .o_rs1_data    (id_rs1_data),
        .o_rs2_data    (id_rs2_data),
        .o_imm         (id_imm),
        .o_rs1         (id_rs1),
        .o_rs2         (id_rs2),
        .o_rd          (id_rd),
        .o_funct3      (id_funct3),
        .o_alu_src_a   (id_alu_src_a),
        .o_alu_src_b   (id_alu_src_b),
        .o_alu_op      (id_alu_op),
        .o_reg_write   (id_reg_write),
        .o_result_src  (id_result_src),
        .o_mem_read    (id_mem_read),
        .o_mem_write   (id_mem_write),
        .o_branch      (id_branch),
        .o_jalr        (id_jalr),
        .o_halt        (id_halt),
        .o_illegal     (id_illegal)
    );

    assign o_halt = id_halt;                           // PROVISORIO (ver encabezado)

    // Mapa de debug
    //   0  IF/ID pc              3  ID control (ver abajo)   6  ID rs2_data
    //   1  IF/ID instruccion     4  ID {funct3, rd, rs2, rs1} 7  ID imm
    //   2  IF/ID pc + 4          5  ID rs1_data               8  ID destino de JAL
    //   9 .. 40  x0 .. x31
    // Control: [0] reg_write [1] mem_read [2] mem_write [3] branch [4] jal
    //          [5] jalr [6] halt [7] illegal [8] alu_src_b [10:9] alu_src_a
    //          [12:11] result_src [16:13] alu_op
    wire [31:0] dbg_id_ctrl   = {15'd0, id_alu_op, id_result_src, id_alu_src_a, id_alu_src_b,
                                 id_illegal, id_halt, id_jalr, id_jal, id_branch,
                                 id_mem_write, id_mem_read, id_reg_write};
    wire [31:0] dbg_id_fields = {14'd0, id_funct3, id_rd, id_rs2, id_rs1};

    assign o_dbg_count = DBG_COUNT;

    always @(*) begin
        case (i_dbg_addr)
            16'd0:   o_dbg_data = ifid_pc;
            16'd1:   o_dbg_data = ifid_instruction;
            16'd2:   o_dbg_data = ifid_pc4;
            16'd3:   o_dbg_data = dbg_id_ctrl;
            16'd4:   o_dbg_data = dbg_id_fields;
            16'd5:   o_dbg_data = id_rs1_data;
            16'd6:   o_dbg_data = id_rs2_data;
            16'd7:   o_dbg_data = id_imm;
            16'd8:   o_dbg_data = id_jal_target;
            default: o_dbg_data = (i_dbg_addr < DBG_COUNT) ? dbg_reg_data : 32'd0;
        endcase
    end
endmodule
