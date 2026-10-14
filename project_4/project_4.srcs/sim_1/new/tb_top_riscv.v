`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_top_riscv: testbench autoverificado del sistema completo (top_riscv)
//
// Maneja top_riscv desde la linea serie, como lo haria el host Python: carga
// del programa de pipeline_prog.hex, step, run hasta el halt (ebreak), dump y
// comparacion de registros y dmem contra pipeline_exp.hex, pause, reset,
// recarga con relleno de NOP, programa demasiado grande y comando desconocido.
// - BAUD_RATE de simulacion alto para que corra rapido (un bit = 128 clk).
// - Receptor UART del host concurrente: guarda en una cola todo lo que llega.
// XSIM: run -all (los .hex tienen que estar en el directorio de simulacion)
// -----------------------------------------------------------------------------
module tb_top_riscv;
    localparam integer CLK_FREQ    = 100_000_000;
    localparam integer BAUD_RATE   = 781_250;
    localparam integer N_TICKS     = 16;
    localparam integer BIT_CLKS    = (CLK_FREQ / (BAUD_RATE * N_TICKS)) * N_TICKS;
    localparam integer IMEM_ADDR_W = 10;
    localparam integer CAP_WORDS   = 1 << (IMEM_ADDR_W - 2);
    localparam integer RX_TIMEOUT  = 40 * 10 * BIT_CLKS;
    localparam [31:0]  NOP         = 32'h0000_0013;
    // Bus de debug de riscv_pipeline (ver encabezado): 22 palabras de etapas, 32 registros, 32 de dmem
    localparam integer DBG_REGS_AT = 22;
    localparam integer DBG_DMEM_AT = 54;
    localparam integer DBG_NWORDS  = 86;

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
        .USE_MMCM   (0),
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
    reg [31:0] prog    [0:255];
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
                if (dut.u_cpu.u_imem.mem[w] !== mem_exp[w]) begin
                    if (bad < 4)
                        $display("FAIL imem[%0d] = %h, esperado %h", w,
                                 dut.u_cpu.u_imem.mem[w], mem_exp[w]);
                    bad = bad + 1;
                end
            checks = checks + 1;
            if (bad != 0) errors = errors + 1;
            else          $display("OK   instru_mem = modelo (%0d palabras)", CAP_WORDS);
        end
    endtask

    // ---------------------------------------------------------------- comandos
    reg [31:0] dw [0:127];
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
                if (w < 128) dw[w] = word;
            end
        end
    endtask

    // ---------------------------------------------------------------- comandos
    task dump_expect_pc(input [31:0] pc);
        begin
            dump;
            checks = checks + 1;
            if (dcount !== DBG_NWORDS || dw[0] !== pc) begin
                errors = errors + 1;
                $display("FAIL t=%0t: dump n=%0d pc=%h, esperado pc=%h", $time, dcount, dw[0], pc);
            end
            else $display("OK   dump pc=%h", dw[0]);
        end
    endtask

    // Compara x0..x31 y las primeras 16 palabras de dmem con pipeline_exp.hex
    reg [31:0] exp [0:47];
    task check_state;
        integer r, bad;
        begin
            dump;
            bad = 0;
            if (dcount !== DBG_NWORDS) bad = bad + 1;
            for (r = 0; r < 32; r = r + 1)
                if (dw[DBG_REGS_AT + r] !== exp[r]) begin
                    bad = bad + 1;
                    $display("FAIL x%0d = %h, esperado %h", r, dw[DBG_REGS_AT + r], exp[r]);
                end
            for (r = 0; r < 16; r = r + 1)
                if (dw[DBG_DMEM_AT + r] !== exp[32 + r]) begin
                    bad = bad + 1;
                    $display("FAIL dmem[%0d] = %h, esperado %h", r, dw[DBG_DMEM_AT + r], exp[32 + r]);
                end
            checks = checks + 1;
            if (bad != 0) errors = errors + 1;
            else          $display("OK   registros y dmem = modelo");
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
    integer prog_len;
    initial begin
        errors  = 0;
        checks  = 0;
        rxq_rd  = 0;
        rst_btn = 1'b0;
        rx_line = 1'b1;
        $readmemh("pipeline_exp.hex", exp);
        $readmemh("pipeline_prog.hex", prog);
        prog_len = 0;
        while (prog_len < 256 && ^prog[prog_len] !== 1'bx) prog_len = prog_len + 1;

        #100;                                          // GSR de XSIM
        repeat (20) @(posedge clk);

        $display("-- Carga del programa de prueba (%0d instrucciones)", prog_len);
        load_program(prog_len, "K");
        check_imem;
        dump_expect_pc(32'h0);

        $display("-- Step");
        step_n(1);
        dump_expect_pc(32'h4);
        step_n(2);
        dump_expect_pc(32'hC);

        $display("-- Run hasta el halt (ebreak)");
        uart_send("R");
        expect_reply("K");
        expect_reply("H");                             // aviso espontaneo
        expect_led(2, 1'b1);
        expect_led(0, 1'b0);
        check_state;
        uart_send("S");
        expect_reply("H");                             // sigue en halt

        $display("-- Reset del CPU: registros limpios, programa conservado");
        uart_send("X");
        expect_reply("K");
        dump_expect_pc(32'h0);
        check_imem;
        uart_send("R");
        expect_reply("K");
        expect_reply("H");
        check_state;

        $display("-- Pause en ejecucion continua (lazo infinito)");
        prog[0] = 32'h0000006f;                        // jal x0,0
        load_program(1, "K");
        check_imem;
        uart_send("R");
        expect_reply("K");
        expect_led(0, 1'b1);
        repeat (300) @(posedge clk);
        uart_send("P");
        expect_reply("K");
        expect_led(0, 1'b0);
        dump;
        snap_pc = dw[0];
        repeat (500) @(posedge clk);
        dump_expect_pc(snap_pc);

        $display("-- Recarga con un programa mas corto: el resto queda en NOP");
        for (i = 0; i < 256; i = i + 1)
            prog[i] = 32'hBEEF_0000 | (i * 4);
        load_program(5, "K");
        check_imem;

        $display("-- Programa demasiado grande");
        n = CAP_WORDS + 2;
        for (i = 0; i < 256; i = i + 1)
            prog[i] = 32'hD00D_0000 | (i * 4);
        load_program(n, "E");
        for (i = 0; i < CAP_WORDS; i = i + 1)
            mem_exp[i] = prog[i];
        check_imem;
        dump_expect_pc(32'h0);                         // sigue sincronizado

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
        #400_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
