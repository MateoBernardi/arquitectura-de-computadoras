// tb.sv: simulación del CPU completo con Verilator.
//
// Corre un programa (imagen binaria en hex, una palabra por línea, desde la dirección 0)
// hasta que el CPU se detiene (o_halt) o se agota el límite de ciclos.
//
//   +hex=<archivo>        imagen del programa: se carga igual en la imem y en la dmem
//   +max-cycles=<n>       límite de ciclos (por defecto 10 000 000)
//   +expect-cause=<n>     (tests de traps) PASS si se detiene con esa causa...
//   +expect-pc=<hex>      ...en esa instrucción (opcional)
//   +estado               al detenerse imprime x1..x31, las palabras 0..31 de la dmem y el
//                         trap, y termina sin juzgar (lo usa verif/placa para comparar)
//   +dmem-en-cero         no carga la imagen en la dmem (como la placa: 'L' carga la imem)
//   +perfil               al detenerse imprime, por categoría de instrucción, cuántas se
//                         retiraron y cuántos ciclos de penalización causaron (lo usa
//                         perfil.py para el desglose del CPI)
//
// Al detenerse informa ciclos, instrucciones retiradas (rvfi_valid, la misma
// interfaz que usa riscv-formal) y una firma del estado final (x1..x31 y las 256
// palabras de la dmem real): dos variantes correctas del CPU terminan con la misma.
//
// Convención de salida (la misma de rvmodel_macros.h):
//   - un store a CONSOLE escribe un carácter en la salida estándar;
//   - TOHOST = 1 al detenerse: PASS (código de salida 0); cualquier otro caso: FAIL (1).
//   - con +expect-cause, en cambio, decide la causa y el PC del trap.
//
// Las memorias son de 8 MB por defecto; `build.sh placa` las compila con el tamaño de la
// placa (1 KB) para comparar contra el hardware.
`timescale 1ns / 1ps
module tb #(
    parameter IMEM_ADDR_W = 23,             // 8 MB
    parameter DMEM_DEPTH  = 1 << 21         // 2M palabras = 8 MB
);
    localparam [31:0] TOHOST  = 32'h007F_FFF0;
    localparam [31:0] CONSOLE = 32'h007F_FFF4;

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    wire halt;
    `RVFI_WIRES
    riscv_pipeline #(.IMEM_ADDR_W(IMEM_ADDR_W), .DMEM_DEPTH(DMEM_DEPTH)) dut (
        `RVFI_CONN,
        .clk(clk), .i_rst(rst), .i_enable(!rst), .o_halt(halt),
        .i_imem_we(1'b0), .i_imem_waddr({IMEM_ADDR_W{1'b0}}), .i_imem_wdata(8'd0),
        .i_dbg_addr(16'd0), .o_dbg_data(), .o_dbg_count()
    );

    // ------------------------------------------------------------- carga
    reg [31:0] img [0:DMEM_DEPTH-1];
    string     hex;
    longint    max_cycles = 10_000_000;
    int        expect_cause = -1;
    reg [31:0] expect_pc = 0;
    bit        check_pc = 0;
    integer    k;
    bit        estado, dmem_cero;

    initial begin
        if (!$value$plusargs("hex=%s", hex)) $fatal(1, "tb: falta +hex=<archivo>");
        void'($value$plusargs("max-cycles=%d", max_cycles));
        void'($value$plusargs("expect-cause=%d", expect_cause));
        check_pc = $value$plusargs("expect-pc=%h", expect_pc);
        estado = $test$plusargs("estado");
        dmem_cero = $test$plusargs("dmem-en-cero");
        for (k = 0; k < DMEM_DEPTH; k = k + 1) img[k] = 32'd0;
        $readmemh(hex, img);
        #1;     // después de los initial de imem/dmem (que las llenan con NOP / 0)
        for (k = 0; k < DMEM_DEPTH; k = k + 1) begin
            dut.u_imem.mem[k]   = img[k];
            dut.u_dmem.lane0[k] = dmem_cero ? 8'd0 : img[k][7:0];
            dut.u_dmem.lane1[k] = dmem_cero ? 8'd0 : img[k][15:8];
            dut.u_dmem.lane2[k] = dmem_cero ? 8'd0 : img[k][23:16];
            dut.u_dmem.lane3[k] = dmem_cero ? 8'd0 : img[k][31:24];
        end
        repeat (3) @(posedge clk);
        rst = 0;
    end

    // ------------------------------------------------------------- consola
    always @(posedge clk)
        if (!rst && dut.u_dmem.we && dut.u_dmem.addr == CONSOLE)
            $write("%c", dut.u_dmem.wdata[7:0]);

    // ------------------------------------------------------------- fin
    longint cycles = 0;
    longint instret = 0;
    always @(posedge clk) if (rvfi_valid) instret <= instret + 1;

    // ------------------------------------------------------------- perfil
    // Cada instrucción retirada cuenta en su categoría (por el opcode de rvfi_insn). Los
    // ciclos perdidos se cargan a la instrucción que los causa, mirando las señales del
    // pipeline en cada ciclo:
    //   - stall de load-use: 1 ciclo, al load que está en EX;
    //   - redirect (branch tomado, jal, jalr resuelto en EX): 2 ciclos, las dos
    //     instrucciones del camino equivocado que se descartan.
    // Lo que sobra (ciclos - instrucciones - penalizaciones) es el llenado y vaciado del
    // pipeline al principio y al final.
    localparam int NCAT = 10;
    localparam int C_ALU_R = 0, C_ALU_I = 1, C_LUI_AUIPC = 2, C_LOAD = 3, C_STORE = 4,
                   C_BR_T = 5, C_BR_NT = 6, C_JAL = 7, C_JALR = 8, C_SYSTEM = 9;
    longint cat_n   [NCAT];
    longint cat_pen [NCAT];
    bit     perfil;
    initial begin
        perfil = $test$plusargs("perfil");
        for (int c = 0; c < NCAT; c++) begin cat_n[c] = 0; cat_pen[c] = 0; end
    end
    function automatic int categoria(input [31:0] insn, input bit tomado);
        case (insn[6:0])
            7'b0110011: return C_ALU_R;
            7'b0010011: return C_ALU_I;
            7'b0110111, 7'b0010111: return C_LUI_AUIPC;
            7'b0000011: return C_LOAD;
            7'b0100011: return C_STORE;
            7'b1100011: return tomado ? C_BR_T : C_BR_NT;
            7'b1101111: return C_JAL;
            7'b1100111: return C_JALR;
            default:    return C_SYSTEM;
        endcase
    endfunction
    always @(posedge clk) if (!rst && !halt) begin
        if (rvfi_valid)
            cat_n[categoria(rvfi_insn, rvfi_pc_wdata != rvfi_pc_rdata + 4)] += 1;
        if (dut.stall) cat_pen[C_LOAD] += 1;
        if (dut.redirect)
            cat_pen[dut.ex_is_jalr ? C_JALR : dut.ex_jump ? C_JAL : C_BR_T] += 2;
    end
    task automatic imprimir_perfil();
        string nom [NCAT] = '{"alu_r", "alu_i", "lui_auipc", "load", "store",
                              "branch_tomado", "branch_no_tomado", "jal", "jalr", "system"};
        for (int c = 0; c < NCAT; c++)
            $display("tb: perfil %s n=%0d penal=%0d", nom[c], cat_n[c], cat_pen[c]);
    endtask

    // firma FNV-1a del estado final
    function automatic [31:0] signature();
        reg [31:0] h;
        integer r;
        h = 32'h811c_9dc5;
        for (r = 1; r < 32; r = r + 1) h = (h ^ dut.u_rf.regs[r]) * 32'h0100_0193;
        for (r = 0; r < 256; r = r + 1)
            h = (h ^ {dut.u_dmem.lane3[r], dut.u_dmem.lane2[r],
                      dut.u_dmem.lane1[r], dut.u_dmem.lane0[r]}) * 32'h0100_0193;
        return h;
    endfunction
    // con la dmem de la placa, TOHOST queda fuera de rango (y no se usa: ver +estado)
    localparam integer TOHOST_IDX = TOHOST[22:2] % DMEM_DEPTH;
    wire [31:0] tohost = {dut.u_dmem.lane3[TOHOST_IDX], dut.u_dmem.lane2[TOHOST_IDX],
                          dut.u_dmem.lane1[TOHOST_IDX], dut.u_dmem.lane0[TOHOST_IDX]};
    integer r;

    always @(posedge clk) if (!rst) begin
        cycles <= cycles + 1;
        if (halt) begin
            // ciclos: los que el CPU avanzó (como los cuenta la debug unit en la placa,
            // que baja i_enable apenas ve o_halt). instrucciones: incluye la que lo
            // detuvo, que está en WB en este ciclo.
            $display("tb: halt  ciclos=%0d  instrucciones=%0d  causa=%0d  pc=%08h  tval=%08h  tohost=%0d  firma=%08h",
                     cycles, instret + 1, dut.trap_cause, dut.trap_pc, dut.trap_tval, tohost,
                     signature());
            if (perfil) begin
                // la que detuvo el CPU está en WB en este ciclo (rvfi_valid no la marca)
                cat_n[C_SYSTEM] += 1;
                imprimir_perfil();
            end
            if (estado) begin
                for (r = 1; r < 32; r = r + 1) $display("tb: x%0d = %08h", r, dut.u_rf.regs[r]);
                for (r = 0; r < 32; r = r + 1)
                    $display("tb: dmem %0d = %08h", r, {dut.u_dmem.lane3[r], dut.u_dmem.lane2[r],
                                                        dut.u_dmem.lane1[r], dut.u_dmem.lane0[r]});
                $finish;
            end
            else if (expect_cause >= 0) begin
                if (dut.trap_cause == expect_cause[3:0] && (!check_pc || dut.trap_pc == expect_pc)) $finish;
                else $fatal(1, "tb: FAIL, se esperaba causa=%0d pc=%08h", expect_cause, expect_pc);
            end
            else if (tohost == 32'd1) $finish;
            else $fatal(1, "tb: FAIL");
        end
        if (cycles >= max_cycles) $fatal(1, "tb: FAIL, sin halt después de %0d ciclos", cycles);
    end
endmodule
