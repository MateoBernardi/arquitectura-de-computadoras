`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_instruction_fetch: testbench autoverificado de la etapa IF + registro IF/ID
//
// - Programa de prueba: la palabra en la direccion A vale SIG | A, asi cada
//   instruccion leida identifica su propia direccion.
// - El programa se carga por el puerto de escritura (camino de la debug unit),
//   con el procesador detenido.
// - Estimulos y chequeos en negedge (sirve tambien para post-implementacion).
//
// Icarus:
//   iverilog -Wall -g2005 -I rtl -s tb_instruction_fetch -o tb_if sim/tb_instruction_fetch.v rtl/*.v
//   vvp tb_if
// XSIM: run -all
// -----------------------------------------------------------------------------
module tb_instruction_fetch;
    localparam [31:0] NOP = 32'h0000_0013;
    localparam [31:0] SIG = 32'hCAFE_0000;

    reg         i_clock;
    reg         i_pc_reset;
    reg         i_pc_enable;
    reg         i_pc_stall;
    reg         i_j_jal;
    reg  [31:0] i_jump_addr;
    reg         i_ex_redirect;
    reg  [31:0] i_ex_target;
    reg         i_instru_mem_enable;
    reg         i_write_enable;
    reg  [7:0]  i_write_addr;
    reg  [7:0]  i_write_data;
    wire [31:0] o_instruction;
    wire [31:0] o_adder_result;
    wire [31:0] o_pc_inst;

    integer errors;
    integer checks;
    integer a;

    wire [31:0] if_imem_data, if_pc, if_pc4;

    instruction_fetch #(
        .IMEM_ADDR_W(8)
    ) u_if (
        .i_clock            (i_clock),
        .i_pc_reset         (i_pc_reset),
        .i_pc_enable        (i_pc_enable),
        .i_pc_stall         (i_pc_stall),
        .i_j_jal            (i_j_jal),
        .i_jump_addr        (i_jump_addr),
        .i_ex_redirect      (i_ex_redirect),
        .i_ex_target        (i_ex_target),
        .i_instru_mem_enable(i_instru_mem_enable),
        .i_write_enable     (i_write_enable),
        .i_write_addr       (i_write_addr),
        .i_write_data       (i_write_data),
        .o_imem_data        (if_imem_data),
        .o_pc               (if_pc),
        .o_pc4              (if_pc4)
    );

    if_id_reg u_if_id (
        .i_clock          (i_clock),
        .i_reset          (i_pc_reset),
        .i_pipeline_enable(i_pc_enable),
        .i_stall          (i_pc_stall),
        .i_flush_id       (i_j_jal),
        .i_flush_ex       (i_ex_redirect),
        .i_instruction    (if_imem_data),
        .i_pc             (if_pc),
        .i_pc4            (if_pc4),
        .o_instruction    (o_instruction),
        .o_pc             (o_pc_inst),
        .o_pc4            (o_adder_result)
    );

    always #5 i_clock = ~i_clock;

`ifdef __ICARUS__
    initial begin
        $dumpfile("tb_instruction_fetch.vcd");
        $dumpvars(0, tb_instruction_fetch);
    end
`endif

    // Avanza un ciclo: flanco de subida y vuelta a negedge
    task tick;
        begin
            @(posedge i_clock);
            @(negedge i_clock);
        end
    endtask

    // Escribe una palabra de a un byte, little-endian
    task write_word(input [7:0] addr, input [31:0] data);
        integer b;
        begin
            for (b = 0; b < 4; b = b + 1) begin
                i_write_addr   = addr + b;
                i_write_data   = data[b*8 +: 8];
                i_write_enable = 1'b1;
                tick;
            end
            i_write_enable = 1'b0;
        end
    endtask

    // La instruccion, su PC y su PC+4 tienen que salir alineados
    task expect_fetch(input [31:0] exp_pc);
        begin
            checks = checks + 1;
            if (o_instruction  !== (SIG | exp_pc) ||
                o_pc_inst      !== exp_pc         ||
                o_adder_result !== exp_pc + 32'd4) begin
                errors = errors + 1;
                $display("FAIL t=%0t esperado pc=%h instr=%h pc4=%h | obtenido pc=%h instr=%h pc4=%h",
                         $time, exp_pc, SIG | exp_pc, exp_pc + 32'd4,
                         o_pc_inst, o_instruction, o_adder_result);
            end else begin
                $display("OK   t=%0t pc=%h instr=%h pc4=%h",
                         $time, o_pc_inst, o_instruction, o_adder_result);
            end
        end
    endtask

    task expect_nop;
        begin
            checks = checks + 1;
            if (o_instruction !== NOP) begin
                errors = errors + 1;
                $display("FAIL t=%0t esperado NOP, obtenido instr=%h", $time, o_instruction);
            end else begin
                $display("OK   t=%0t NOP", $time);
            end
        end
    endtask

    initial begin
        errors              = 0;
        checks              = 0;
        i_clock             = 1'b0;
        i_pc_reset          = 1'b1;
        i_pc_enable         = 1'b0;
        i_pc_stall          = 1'b0;
        i_j_jal             = 1'b0;
        i_jump_addr         = 32'd0;
        i_ex_redirect       = 1'b0;
        i_ex_target         = 32'd0;
        i_instru_mem_enable = 1'b1;
        i_write_enable      = 1'b0;
        i_write_addr        = 8'd0;
        i_write_data        = 8'd0;

        #100;                                          // GSR de XSIM
        @(negedge i_clock);

        $display("-- Carga del programa por el puerto de escritura");
        for (a = 0; a < 256; a = a + 4)
            write_word(a[7:0], SIG | a);

        $display("-- Reset activo");
        tick; expect_nop;

        $display("-- Ejecucion secuencial");
        i_pc_reset  = 1'b0;
        i_pc_enable = 1'b1;
        tick; expect_fetch(32'h00);
        tick; expect_fetch(32'h04);
        tick; expect_fetch(32'h08);

        $display("-- Stall de un ciclo: todo se mantiene");
        i_pc_stall = 1'b1;
        tick; expect_fetch(32'h08);
        i_pc_stall = 1'b0;
        tick; expect_fetch(32'h0C);
        tick; expect_fetch(32'h10);

        $display("-- JAL desde ID a 0x40: un NOP y despues el destino");
        i_j_jal     = 1'b1;
        i_jump_addr = 32'h40;
        tick; expect_nop;
        i_j_jal     = 1'b0;
        tick; expect_fetch(32'h40);
        tick; expect_fetch(32'h44);

        $display("-- Redirect desde EX a 0x80");
        i_ex_redirect = 1'b1;
        i_ex_target   = 32'h80;
        tick; expect_nop;
        i_ex_redirect = 1'b0;
        tick; expect_fetch(32'h80);

        $display("-- Prioridad: EX (0xC0) le gana a JAL (0x20)");
        i_j_jal       = 1'b1;
        i_jump_addr   = 32'h20;
        i_ex_redirect = 1'b1;
        i_ex_target   = 32'hC0;
        tick; expect_nop;
        i_j_jal       = 1'b0;
        i_ex_redirect = 1'b0;
        tick; expect_fetch(32'hC0);

        $display("-- Redirect de EX (0x30) durante un stall: el redirect gana");
        i_pc_stall    = 1'b1;
        i_ex_redirect = 1'b1;
        i_ex_target   = 32'h30;
        tick; expect_nop;
        i_pc_stall    = 1'b0;
        i_ex_redirect = 1'b0;
        tick; expect_fetch(32'h30);

        $display("-- Debug unit detiene la etapa dos ciclos");
        i_pc_enable = 1'b0;
        tick; expect_fetch(32'h30);
        tick; expect_fetch(32'h30);
        i_pc_enable = 1'b1;
        tick; expect_fetch(32'h34);

        $display("-- Reset en plena ejecucion");
        i_pc_reset = 1'b1;
        tick; expect_nop;
        i_pc_reset = 1'b0;
        tick; expect_fetch(32'h00);
        tick; expect_fetch(32'h04);

        if (errors == 0)
            $display("PASS: %0d chequeos OK", checks);
        else
            $display("FAIL: %0d errores en %0d chequeos", errors, checks);
        $finish;
    end

    // Watchdog
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
