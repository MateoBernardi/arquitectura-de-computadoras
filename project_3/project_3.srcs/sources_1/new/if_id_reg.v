`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// if_id_reg: registro de pipeline IF/ID
//
// - La instruccion ya llega registrada: el registro de salida de la BRAM
//   (instru_mem) es el campo "instruccion" de IF/ID, porque la lectura es
//   sincronica y no se puede sacar de adentro de la memoria. Este modulo
//   guarda PC y PC+4 en el mismo flanco en que la memoria lee, asi los tres
//   campos quedan alineados, y aplica el flush.
// - i_pipeline_enable (debug unit): 0 congela todo.
// - i_stall (unidad de riesgos): 1 congela el registro (misma condicion que
//   usa instruction_fetch para la lectura de la memoria).
// - i_flush_id (JAL en ID) / i_flush_ex (branch tomado o JALR en EX): la
//   instruccion que se lee en ese flanco es camino equivocado; en el ciclo
//   siguiente o_instruction sale como NOP (0x00000013). Un flush de EX le gana
//   al stall.
// - Reset: PC = PC+4 = 0 e instruccion = NOP.
// -----------------------------------------------------------------------------
module if_id_reg (
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire        i_pipeline_enable,
    input  wire        i_stall,
    input  wire        i_flush_id,
    input  wire        i_flush_ex,
    input  wire [31:0] i_instruction,                  // salida de instru_mem (ya registrada)
    input  wire [31:0] i_pc,                           // PC que se esta leyendo
    input  wire [31:0] i_pc4,                          // PC + 4 que se esta leyendo
    output wire [31:0] o_instruction,
    output wire [31:0] o_pc,
    output wire [31:0] o_pc4
);
    localparam [31:0] NOP = 32'h0000_0013;             // addi x0, x0, 0

    wire flush_q;

    wire load_en  = i_pipeline_enable & ~i_stall;
    wire flush_en = i_pipeline_enable & (~i_stall | i_flush_ex);
    wire flush_d  = i_flush_id | i_flush_ex;

    latch #(.WIDTH(32)) u_pc (
        .i_clock (i_clock),
        .i_reset (i_reset),
        .i_enable(load_en),
        .i_data  (i_pc),
        .o_data  (o_pc)
    );

    latch #(.WIDTH(32)) u_pc4 (
        .i_clock (i_clock),
        .i_reset (i_reset),
        .i_enable(load_en),
        .i_data  (i_pc4),
        .o_data  (o_pc4)
    );

    latch #(
        .WIDTH      (1),
        .RESET_VALUE(1'b1)
    ) u_flush (
        .i_clock (i_clock),
        .i_reset (i_reset),
        .i_enable(flush_en),
        .i_data  (flush_d),
        .o_data  (flush_q)
    );

    mux2 #(.WIDTH(32)) u_mux_nop (
        .i_A   (i_instruction),
        .i_B   (NOP),
        .i_SEL (flush_q),
        .o_data(o_instruction)
    );
endmodule
