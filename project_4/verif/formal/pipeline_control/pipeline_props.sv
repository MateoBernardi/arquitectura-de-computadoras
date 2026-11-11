// pipeline_control — propiedades temporales del control del pipeline completo.
//
// Características:
//   * Hay reloj y estado: las propiedades hablan de "el ciclo anterior"
//     con $past(x), que vale lo que valía x en el flanco anterior.
//   * El DUT es riscv_pipeline entero, sin modificar. Las señales internas
//     se observan con cables fv_* que el script de Yosys conecta (ver .sby).
//   * El programa es libre: imem_formal.v reemplaza a la imem y su contenido
//     es (* anyconst *): el solver elige 8 instrucciones cualesquiera.
//   * i_enable e i_rst también son libres: la debug unit puede congelar y
//     resetear el CPU en cualquier ciclo.

module pipeline_props (
    input        clk,
    input        i_rst,
    input        i_enable,
    input [15:0] i_dbg_addr
);
    localparam [31:0] NOP = 32'h00000013;

    // ------------------------------------------------------------ programa
    (* anyconst *) reg [32*8-1:0] prog;      // 8 palabras = 32 bytes de imem

    // ---------------------------------------------------------------- DUT
    wire        o_halt;
    wire [31:0] o_dbg_data;
    wire [15:0] o_dbg_count;
    riscv_pipeline #(.IMEM_ADDR_W(5)) dut (
        .clk(clk), .i_rst(i_rst), .i_enable(i_enable), .o_halt(o_halt),
        .i_imem_we(1'b0), .i_imem_waddr(5'd0), .i_imem_wdata(8'd0),
        .i_dbg_addr(i_dbg_addr), .o_dbg_data(o_dbg_data), .o_dbg_count(o_dbg_count)
    );

    // ------------------------------------- señales internas (ver el .sby)
    // Cada fv_X queda conectado a dut.X por el comando `connect` de Yosys.
    (* keep *) wire [31:0] fv_pc, fv_if_inst, fv_id_inst, fv_redirect_target;
    (* keep *) wire        fv_stall, fv_redirect, fv_stop_fetch, fv_halting;
    (* keep *) wire        fv_ex_reg_write, fv_ex_mem_read, fv_ex_mem_write;
    (* keep *) wire        fv_ex_branch, fv_ex_jump, fv_ex_halt, fv_dmem_we;

    wire [4:0] idex_class = {fv_ex_branch, fv_ex_jump, fv_ex_halt,
                             fv_ex_mem_read, fv_ex_mem_write};
    wire ex_bubble = !fv_ex_reg_write && !fv_ex_mem_read && !fv_ex_mem_write &&
                     !fv_ex_branch && !fv_ex_jump && !fv_ex_halt;

    // ---------------------------------------------------- reset inicial
    // f_past_valid = 0 solo en el primer ciclo: ahí $past() no tiene sentido.
    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;

    always @(*) begin
        // El CPU arranca reseteado (como lo hace reset_gen en la placa).
        if (!f_past_valid) assume (i_rst);

        // ---- INVARIANTES: propiedades del ESTADO, válidas en todo ciclo ----
        // Sin ellas la inducción arranca en estados inalcanzables (ver README).
        // Solo desde el primer reset: antes, los registros tienen valores
        // arbitrarios (en formal, un registro sin valor inicial arranca con
        // cualquier cosa).
        if (f_past_valid) begin
            // I1: ID/EX contiene UNA instrucción real: a lo sumo una de las
            //     clases branch / jump / halt / load / store está activa.
            //     (Es lo único que control.v puede generar, y una burbuja
            //      no tiene ninguna.)
            i1_idex_one_class: assert ($onehot0(idex_class));
            // I2: desde que hay un halt en curso, EX solo contiene burbujas.
            i2_halting_bubble:  assert (!fv_halting || ex_bubble);
            // T8: durante el reset la dmem no se escribe (aunque i_enable = 1 y
            //     EX/MEM tenga un store de antes del reset).
            t8_reset_no_store:  assert (!i_rst || !fv_dmem_we);
        end
    end

    // ------------------------------------------- propiedades temporales
    // "En el ciclo anterior el CPU corrió": habilitado y sin reset.
    // (Es lo mismo que $past(i_enable && !i_rst), pero $past solo se puede
    //  usar dentro de bloques con reloj, así que lo registramos a mano.)
    reg r_ran = 1'b0;
    always @(posedge clk) r_ran <= i_enable && !i_rst;
    wire past_run = f_past_valid && r_ran;

    always @(posedge clk) if (f_past_valid) begin
        // T0 — reset: PC = 0, IF/ID = NOP, ID/EX = burbuja.
        if ($past(i_rst)) begin
            t0_reset_pc:   assert (fv_pc == 32'd0);
            t0_reset_ifid: assert (fv_id_inst == NOP);
            t0_reset_idex: assert (ex_bubble);
        end

        // T1 — congelado: con i_enable = 0 no cambia nada visible.
        if (!$past(i_enable) && !$past(i_rst)) begin
            t1_freeze_pc:   assert (fv_pc == $past(fv_pc));
            t1_freeze_ifid: assert (fv_id_inst == $past(fv_id_inst));
        end

        // T2 — avance normal: PC+4 y la instrucción leída pasa a ID.
        if (past_run && !$past(fv_stall) && !$past(fv_redirect) && !$past(fv_stop_fetch)) begin
            t2_advance_pc:   assert (fv_pc == $past(fv_pc) + 32'd4);
            t2_advance_ifid: assert (fv_id_inst == $past(fv_if_inst));
        end

        // T3 — stall (load-use): PC e IF/ID quietos, burbuja en ID/EX.
        //      (Si a la vez la instrucción de EX se detiene, manda T7.)
        if (past_run && $past(fv_stall) && !$past(fv_stop_fetch)) begin
            t3_stall_pc:   assert (fv_pc == $past(fv_pc));
            t3_stall_ifid: assert (fv_id_inst == $past(fv_id_inst));
            t3_stall_idex: assert (ex_bubble);
        end

        // T4 — salto tomado en EX: PC = destino, y las DOS instrucciones
        //      que venían detrás se descartan (IF/ID = NOP, ID/EX = burbuja).
        //      (Un salto a una dirección no alineada es un trap: manda T7.)
        if (past_run && $past(fv_redirect) && !$past(fv_stop_fetch)) begin
            t4_redirect_pc:   assert (fv_pc == $past(fv_redirect_target));
            t4_redirect_ifid: assert (fv_id_inst == NOP);
            t4_redirect_idex: assert (ex_bubble);
        end

        // T5 — halt: una vez en curso, el PC no se mueve más (hasta un reset).
        if (past_run && $past(fv_halting)) begin
            t5_halt_pc: assert (fv_pc == $past(fv_pc));
        end

        // T7 — la instrucción de EX detiene la ejecución (ecall/ebreak o un
        //      trap): el PC no avanza y lo más joven se descarta.
        if (past_run && $past(fv_stop_fetch)) begin
            t7_stop_pc:   assert (fv_pc == $past(fv_pc));
            t7_stop_ifid: assert (fv_id_inst == NOP);
            t7_stop_idex: assert (ex_bubble);
        end

        // T6 — nunca hay stall en el ciclo siguiente a un salto tomado
        //      (EX tiene una burbuja, y una burbuja no es un load).
        //      Empezó como un cover que el solver demostró inalcanzable.
        if (past_run && $past(fv_redirect)) begin
            t6_no_stall_after_redirect: assert (!fv_stall);
        end
    end

    // ------------------------------------------------------- cobertura
    always @(posedge clk) if (f_past_valid) begin
        c1_stall:          cover (past_run && $past(fv_stall));
        c2_redirect:       cover (past_run && $past(fv_redirect));
        c3_halt:           cover (o_halt);
        // Un load-use lo antes posible después de un salto tomado: el load es
        // la instrucción destino, y su consumidora la sigue (3 ciclos después).
        c4_redirect_stall: cover ($past(f_past_valid && fv_redirect, 3) && fv_stall);
        // Un congelamiento en medio de un stall (debug unit pausando):
        c5_freeze_stall:   cover (!$past(i_enable) && $past(fv_stall) && !$past(i_rst));
        // Un load que hace trap mientras su consumidora espera en ID (stall + trap):
        c6_trap_stall:     cover (past_run && $past(fv_stall) && $past(fv_stop_fetch) && !$past(fv_halting));
    end
endmodule
