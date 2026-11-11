`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_top_riscv: testbench autoverificado del sistema completo
//
// Maneja top_riscv desde la linea serie, como lo haria debug_host.py:
// carga de programas, step, run, dump durante la ejecucion, pause, reset,
// recarga con relleno de NOP, carga vacia, programa demasiado grande, halt
// (forzado sobre la senal del CPU), salidas de ID en el dump, JAL que
// redirige IF, EBREAK que frena la ejecucion y comando desconocido.
// - BAUD_RATE de simulacion elegido para que el divisor sea exacto (8):
//   un bit = 128 ciclos de reloj.
// - Receptor UART del host concurrente: guarda en una cola todo lo que llega.
// - Solo para simulacion RTL: lee instru_mem por referencia jerarquica y
//   fuerza cpu_halt, que no existen en el netlist post-implementacion.
//
// Icarus (desde la raiz del proyecto):
//   iverilog -Wall -g2005 -I rtl -s tb_top_riscv -o tb_top sim/tb_top_riscv.v rtl/*.v
//   vvp tb_top            (vvp tb_top +vcd para generar formas de onda)
// XSIM: run -all
// -----------------------------------------------------------------------------
module tb_top_riscv;
    localparam integer CLK_FREQ    = 100_000_000;
    localparam integer BAUD_RATE   = 781_250;
    localparam integer N_TICKS     = 16;
    localparam integer BIT_CLKS    = (CLK_FREQ / (BAUD_RATE * N_TICKS)) * N_TICKS;
    localparam integer IMEM_ADDR_W = 8;
    localparam integer CAP_WORDS   = 1 << (IMEM_ADDR_W - 2);
    localparam integer RX_TIMEOUT  = 40 * 10 * BIT_CLKS;
    localparam [31:0]  NOP         = 32'h0000_0013;
    // Palabras del bus de debug: 9 de IF/ID e ID + 32 registros + 7 de EX.
    // Tiene que coincidir con DBG_COUNT de cpu.v.
    localparam integer DBG_REGS_AT = 9;
    localparam integer DBG_EX_AT   = 41;
    localparam integer DBG_NWORDS  = 48;

    reg        clk = 1'b0;
    reg        rst_btn;
    reg        rx_line;                                // host -> FPGA
    wire       tx_line;                                // FPGA -> host
    wire [2:0] led;

    integer    errors, checks, framing_errors;
    integer    i, n;
    reg [31:0] snap_pc, snap_instr;

    top_riscv #(
        .CLK_FREQ   (CLK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .N_TICKS    (N_TICKS),
        .IMEM_ADDR_W(IMEM_ADDR_W)
    ) dut (
        .i_clk  (clk),
        .i_reset(rst_btn),
        .i_rx   (rx_line),
        .o_tx   (tx_line),
        .o_led  (led)
    );

    always #5 clk = ~clk;

`ifdef __ICARUS__
    initial begin
        if ($test$plusargs("vcd")) begin               // vvp tb_top +vcd (unos 60 MB)
            $dumpfile("tb_top_riscv.vcd");
            $dumpvars(0, tb_top_riscv);
        end
    end
`endif

    // ---------------------------------------------------------------- UART host
    task uart_send(input [7:0] b);
        integer k;
        begin
            @(negedge clk);
            rx_line = 1'b0;
            repeat (BIT_CLKS) @(negedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                rx_line = b[k];
                repeat (BIT_CLKS) @(negedge clk);
            end
            rx_line = 1'b1;
            repeat (BIT_CLKS) @(negedge clk);
        end
    endtask

    reg [7:0] rxq [0:4095];
    integer   rxq_wr, rxq_rd, kr;
    reg [7:0] rx_shift;

    initial begin
        rxq_wr         = 0;
        framing_errors = 0;
        forever begin
            @(negedge tx_line);
            repeat (BIT_CLKS / 2) @(posedge clk);
            if (tx_line !== 1'b0) framing_errors = framing_errors + 1;
            for (kr = 0; kr < 8; kr = kr + 1) begin
                repeat (BIT_CLKS) @(posedge clk);
                rx_shift[kr] = tx_line;
            end
            repeat (BIT_CLKS) @(posedge clk);
            if (tx_line !== 1'b1) framing_errors = framing_errors + 1;
            rxq[rxq_wr % 4096] = rx_shift;
            rxq_wr = rxq_wr + 1;
        end
    end

    task uart_recv(output [7:0] b);
        integer t;
        begin
            t = 0;
            while (rxq_rd >= rxq_wr && t < RX_TIMEOUT) begin
                @(posedge clk);
                t = t + 1;
            end
            if (rxq_rd >= rxq_wr) begin
                errors = errors + 1;
                $display("FAIL t=%0t: no llego ningun byte", $time);
                b = 8'hxx;
            end
            else begin
                b      = rxq[rxq_rd % 4096];
                rxq_rd = rxq_rd + 1;
            end
        end
    endtask

    task expect_reply(input [7:0] exp);
        reg [7:0] b;
        begin
            uart_recv(b);
            checks = checks + 1;
            if (b !== exp) begin
                errors = errors + 1;
                $display("FAIL t=%0t: respuesta %h, esperada '%c'", $time, b, exp);
            end
            else begin
                $display("OK   respuesta '%c'", b);
            end
        end
    endtask

    // ---------------------------------------------------------------- programa
    reg [31:0] prog    [0:127];
    reg [31:0] mem_exp [0:CAP_WORDS-1];

    // Envia 'L', n y n palabras de prog[]; actualiza el modelo de la memoria
    task load_program(input integer n_words, input [7:0] exp_reply);
        integer    w, b;
        reg [31:0] word;
        reg [15:0] n16;
        begin
            n16 = n_words;
            uart_send("L");
            uart_send(n16[7:0]);
            uart_send(n16[15:8]);
            checks = checks + 1;
            if (led[1] !== 1'b1) begin                 // CPU en reset durante la carga
                errors = errors + 1;
                $display("FAIL t=%0t: LED de carga apagado durante la carga", $time);
            end
            for (w = 0; w < n_words; w = w + 1) begin
                word = prog[w];
                for (b = 0; b < 4; b = b + 1)
                    uart_send(word[b*8 +: 8]);
            end
            expect_reply(exp_reply);
            for (w = 0; w < CAP_WORDS; w = w + 1)
                mem_exp[w] = (w < n_words) ? prog[w] : NOP;
        end
    endtask

    // Compara instru_mem contra el modelo
    task check_imem;
        integer w, bad;
        begin
            bad = 0;
            for (w = 0; w < CAP_WORDS; w = w + 1)
                if (dut.u_cpu.u_if.u_instru_mem.mem[w] !== mem_exp[w]) begin
                    if (bad < 4)
                        $display("FAIL imem[%0d] = %h, esperado %h", w,
                                 dut.u_cpu.u_if.u_instru_mem.mem[w], mem_exp[w]);
                    bad = bad + 1;
                end
            checks = checks + 1;
            if (bad != 0) errors = errors + 1;
            else          $display("OK   instru_mem = modelo (%0d palabras)", CAP_WORDS);
        end
    endtask

    // ---------------------------------------------------------------- comandos
    reg [31:0] dw [0:63];
    integer    dcount;

    task dump;
        reg [7:0]  b;
        reg [15:0] c;
        reg [31:0] word;
        integer    w, k;
        begin
            uart_send("D");
            uart_recv(b);
            c[7:0] = b;
            uart_recv(b);
            c[15:8] = b;
            dcount = c;
            for (w = 0; w < dcount; w = w + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    uart_recv(b);
                    word[k*8 +: 8] = b;
                end
                if (w < 64) dw[w] = word;
            end
        end
    endtask

    // Dump y comparacion exacta de IF/ID
    task expect_if(input [31:0] pc, input [31:0] instr, input [31:0] pc4);
        begin
            dump;
            checks = checks + 1;
            if (dcount < 3 || dw[0] !== pc || dw[1] !== instr || dw[2] !== pc4) begin
                errors = errors + 1;
                $display("FAIL t=%0t: dump n=%0d pc=%h instr=%h pc4=%h | esperado pc=%h instr=%h pc4=%h",
                         $time, dcount, dw[0], dw[1], dw[2], pc, instr, pc4);
            end
            else begin
                $display("OK   dump pc=%h instr=%h pc4=%h", dw[0], dw[1], dw[2]);
            end
        end
    endtask

    // Dump y chequeo de coherencia: la instruccion corresponde a su PC
    task expect_if_coherent;
        begin
            dump;
            checks = checks + 1;
            if (dcount < 3 || dw[1] !== mem_exp[dw[0][IMEM_ADDR_W-1:2]] || dw[2] !== dw[0] + 32'd4) begin
                errors = errors + 1;
                $display("FAIL t=%0t: dump incoherente pc=%h instr=%h pc4=%h", $time, dw[0], dw[1], dw[2]);
            end
            else begin
                $display("OK   dump coherente pc=%h instr=%h pc4=%h", dw[0], dw[1], dw[2]);
            end
        end
    endtask

    // Dump y chequeo de IF/ID y de las salidas de ID (control, campos, imm, destino JAL)
    task expect_id(input [31:0] pc, input [31:0] instr, input [31:0] ctrl, input [31:0] fields,
                   input [31:0] imm, input [31:0] jal_target);
        integer r, regs_ok;
        begin
            dump;
            regs_ok = 1;
            for (r = DBG_REGS_AT; r < DBG_EX_AT; r = r + 1)
                if (dw[r] !== 32'd0) regs_ok = 0;      // sin WB todavia: registros en 0
            checks = checks + 1;
            if (dcount !== DBG_NWORDS || dw[0] !== pc || dw[1] !== instr || dw[3] !== ctrl || dw[4] !== fields ||
                dw[5] !== 32'd0 || dw[6] !== 32'd0 || dw[7] !== imm || dw[8] !== jal_target || !regs_ok) begin
                errors = errors + 1;
                $display("FAIL t=%0t: ID pc=%h instr=%h ctrl=%h campos=%h imm=%h jal=%h n=%0d",
                         $time, dw[0], dw[1], dw[3], dw[4], dw[7], dw[8], dcount);
            end
            else begin
                $display("OK   ID pc=%h instr=%h ctrl=%h campos=%h imm=%h destino_jal=%h",
                         dw[0], dw[1], dw[3], dw[4], dw[7], dw[8]);
            end
        end
    endtask

// Dump y chequeo de las salidas de EX (resultado, operandos, destino, flags)
    task expect_ex(input [31:0] alu_result, input [31:0] alu_a, input [31:0] alu_b,
                   input [31:0] target, input [31:0] pc4, input [31:0] ctrl);
        begin
            dump;
            checks = checks + 1;
            if (dcount !== DBG_NWORDS || dw[DBG_EX_AT] !== alu_result ||
                dw[DBG_EX_AT+1] !== alu_a || dw[DBG_EX_AT+2] !== alu_b ||
                dw[DBG_EX_AT+3] !== target || dw[DBG_EX_AT+4] !== pc4 ||
                dw[DBG_EX_AT+5] !== ctrl) begin
                errors = errors + 1;
                $display("FAIL t=%0t: EX r=%h a=%h b=%h tgt=%h pc4=%h ctrl=%h n=%0d",
                         $time, dw[DBG_EX_AT], dw[DBG_EX_AT+1], dw[DBG_EX_AT+2],
                         dw[DBG_EX_AT+3], dw[DBG_EX_AT+4], dw[DBG_EX_AT+5], dcount);
            end
            else begin
                $display("OK   EX r=%h a=%h b=%h tgt=%h pc4=%h ctrl=%h",
                         dw[DBG_EX_AT], dw[DBG_EX_AT+1], dw[DBG_EX_AT+2],
                         dw[DBG_EX_AT+3], dw[DBG_EX_AT+4], dw[DBG_EX_AT+5]);
            end
        end
    endtask

    task step_n(input integer n_steps);
        integer s;
        begin
            for (s = 0; s < n_steps; s = s + 1) begin
                uart_send("S");
                expect_reply("K");
            end
        end
    endtask

    task expect_led(input integer idx, input value);
        begin
            checks = checks + 1;
            if (led[idx] !== value) begin
                errors = errors + 1;
                $display("FAIL t=%0t: LED%0d = %b, esperado %b", $time, idx, led[idx], value);
            end
        end
    endtask

    // ---------------------------------------------------------------- secuencia
    initial begin
        errors  = 0;
        checks  = 0;
        rxq_rd  = 0;
        rst_btn = 1'b0;
        rx_line = 1'b1;

        #100;                                          // GSR de XSIM
        repeat (20) @(posedge clk);

        $display("-- Carga de la memoria completa (cada palabra codifica su direccion)");
        for (i = 0; i < 128; i = i + 1)
            prog[i] = 32'hCAFE_0000 | (i * 4);
        load_program(CAP_WORDS, "K");
        check_imem;
        expect_if(32'h0, NOP, 32'h0);                  // CPU recien reseteado

        $display("-- Step");
        step_n(1);
        expect_if(32'h00, prog[0], 32'h04);
        step_n(1);
        expect_if(32'h04, prog[1], 32'h08);
        step_n(3);
        expect_if(32'h10, prog[4], 32'h14);

        $display("-- Run y dump durante la ejecucion");
        uart_send("R");
        expect_reply("K");
        expect_led(0, 1'b1);
        repeat (500) @(posedge clk);
        expect_if_coherent;
        snap_pc = dw[0];
        expect_if_coherent;
        checks = checks + 1;
        if (dw[0] === snap_pc) begin
            errors = errors + 1;
            $display("FAIL: el PC no avanzo entre dumps durante la ejecucion");
        end

        $display("-- Pause: el estado queda congelado");
        uart_send("P");
        expect_reply("K");
        expect_led(0, 1'b0);
        expect_if_coherent;
        snap_pc    = dw[0];
        snap_instr = dw[1];
        repeat (1000) @(posedge clk);
        expect_if(snap_pc, snap_instr, snap_pc + 32'd4);

        $display("-- Reset del CPU");
        uart_send("X");
        expect_reply("K");
        expect_if(32'h0, NOP, 32'h0);
        step_n(1);
        expect_if(32'h00, prog[0], 32'h04);

        $display("-- Recarga con un programa mas corto: el resto queda en NOP");
        for (i = 0; i < 128; i = i + 1)
            prog[i] = 32'hBEEF_0000 | (i * 4);
        load_program(5, "K");
        check_imem;
        expect_if(32'h0, NOP, 32'h0);
        step_n(6);
        expect_if(32'h14, NOP, 32'h18);                // posicion 5: relleno

        $display("-- Halt (forzado sobre la senal del CPU)");
        force dut.cpu_halt = 1'b1;
        uart_send("S");
        expect_reply("H");
        uart_send("R");
        expect_reply("H");
        expect_led(2, 1'b1);
        release dut.cpu_halt;
        step_n(1);
        expect_if(32'h18, NOP, 32'h1C);
        uart_send("R");
        expect_reply("K");
        repeat (200) @(posedge clk);
        force dut.cpu_halt = 1'b1;
        expect_reply("H");                             // aviso espontaneo
        expect_led(0, 1'b0);
        release dut.cpu_halt;
        uart_send("P");
        expect_reply("K");

        $display("-- Carga vacia: toda la memoria en NOP");
        load_program(0, "K");
        check_imem;

        $display("-- Programa demasiado grande");
        for (i = 0; i < 128; i = i + 1)
            prog[i] = 32'hD00D_0000 | (i * 4);
        n = CAP_WORDS + 2;
        load_program(n, "E");
        for (i = 0; i < CAP_WORDS; i = i + 1)
            mem_exp[i] = prog[i];
        check_imem;
        expect_if(32'h0, NOP, 32'h0);                  // sigue sincronizado

        $display("-- Salidas de ID en el dump, JAL y EBREAK");
        prog[0] = 32'h00500093;                        // 0x00 addi x1,x0,5
        prog[1] = 32'h00c000ef;                        // 0x04 jal  x1,0x10
        prog[2] = 32'h00100093;                        // 0x08 (salteada por el jal)
        prog[3] = 32'h00200093;                        // 0x0c (salteada por el jal)
        prog[4] = 32'h00100073;                        // 0x10 ebreak
        load_program(5, "K");
        dump;
        checks = checks + 1;
        if (dcount !== DBG_NWORDS) begin
            errors = errors + 1;
            $display("FAIL: el dump tiene %0d palabras, esperadas %0d", dcount, DBG_NWORDS);
        end
        step_n(1);
        expect_id(32'h00, 32'h00500093, 32'h0000_0101, 32'h0000_0400, 32'h5, 32'h5);
        step_n(1);
        expect_id(32'h04, 32'h00c000ef, 32'h0000_1311, 32'h0000_0400, 32'hc, 32'h10);
        uart_send("R");
        expect_reply("K");
        expect_reply("H");                             // frena con el ebreak en EX
        // El halt sale de EX (ID/EX), asi que cuando el pipeline se congela el
        // ebreak ya no esta en ID: quedo una instruccion mas en ID. Se chequea
        // la etapa EX, que es donde tiene que estar el ebreak.
        // ebreak: alu 0+0 con op=add -> 0, zero=1; sin branch ni jalr no redirige.
        // target = pc + imm = 0x10 + 1 = 0x11 (se muestra aunque no se use).
        expect_ex(32'h0000_0000, 32'h0000_0000, 32'h0000_0000,
                  32'h0000_11, 32'h0000_14, 32'h0000_10);
        expect_id(32'h14, 32'h0000_0013, 32'h0000_0100, 32'h0000_0000, 32'h0, 32'h14);
        uart_send("S");
        expect_reply("H");

        $display("-- Comando desconocido");
        uart_send("Z");
        expect_reply("?");

        checks = checks + 1;
        if (framing_errors != 0) begin
            errors = errors + 1;
            $display("FAIL: %0d errores de framing en TX", framing_errors);
        end
        checks = checks + 1;
        if (rxq_rd != rxq_wr) begin
            errors = errors + 1;
            $display("FAIL: %0d bytes de mas recibidos", rxq_wr - rxq_rd);
        end

        if (errors == 0)
            $display("PASS: %0d chequeos OK", checks);
        else
            $display("FAIL: %0d errores en %0d chequeos", errors, checks);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
