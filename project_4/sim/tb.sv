// tb.sv: simulación del CPU completo con Verilator.
//
// Corre un programa (imagen binaria en hex, una palabra por línea, desde la dirección 0)
// hasta que el CPU se detiene (o_halt) o se agota el límite de ciclos.
//
//   +hex=<archivo>        imagen del programa: se carga igual en la imem y en la dmem
//   +max-cycles=<n>       límite de ciclos (por defecto 10 000 000)
//   +expect-cause=<n>     (tests de traps) PASS si se detiene con esa causa...
//   +expect-pc=<hex>      ...en esa instrucción
//
// Convención de salida (la misma de rvmodel_macros.h):
//   - un store a CONSOLE escribe un carácter en la salida estándar;
//   - TOHOST = 1 al detenerse: PASS (código de salida 0); cualquier otro caso: FAIL (1).
//   - con +expect-cause, en cambio, decide la causa y el PC del trap.
//
// Las memorias son de 8 MB solo en simulación (en la FPGA son las de siempre).
`timescale 1ns / 1ps
module tb;
    localparam IMEM_ADDR_W = 23;            // 8 MB
    localparam DMEM_DEPTH  = 1 << 21;       // 2M palabras = 8 MB
    localparam [31:0] TOHOST  = 32'h007F_FFF0;
    localparam [31:0] CONSOLE = 32'h007F_FFF4;

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    wire halt;
    riscv_pipeline #(.IMEM_ADDR_W(IMEM_ADDR_W), .DMEM_DEPTH(DMEM_DEPTH)) dut (
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
    integer    k;

    initial begin
        if (!$value$plusargs("hex=%s", hex)) $fatal(1, "tb: falta +hex=<archivo>");
        void'($value$plusargs("max-cycles=%d", max_cycles));
        void'($value$plusargs("expect-cause=%d", expect_cause));
        void'($value$plusargs("expect-pc=%h", expect_pc));
        for (k = 0; k < DMEM_DEPTH; k = k + 1) img[k] = 32'd0;
        $readmemh(hex, img);
        #1;     // después de los initial de imem/dmem (que las llenan con NOP / 0)
        for (k = 0; k < DMEM_DEPTH; k = k + 1) begin
            dut.u_imem.mem[k]   = img[k];
            dut.u_dmem.lane0[k] = img[k][7:0];
            dut.u_dmem.lane1[k] = img[k][15:8];
            dut.u_dmem.lane2[k] = img[k][23:16];
            dut.u_dmem.lane3[k] = img[k][31:24];
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
    wire [31:0] tohost = {dut.u_dmem.lane3[TOHOST[22:2]], dut.u_dmem.lane2[TOHOST[22:2]],
                          dut.u_dmem.lane1[TOHOST[22:2]], dut.u_dmem.lane0[TOHOST[22:2]]};

    always @(posedge clk) if (!rst) begin
        cycles <= cycles + 1;
        if (halt) begin
            $display("tb: halt  ciclos=%0d  causa=%0d  pc=%08h  tval=%08h  tohost=%0d",
                     cycles, dut.trap_cause, dut.trap_pc, dut.trap_tval, tohost);
            if (expect_cause >= 0) begin
                if (dut.trap_cause == expect_cause[3:0] && dut.trap_pc == expect_pc) $finish;
                else $fatal(1, "tb: FAIL, se esperaba causa=%0d pc=%08h", expect_cause, expect_pc);
            end
            else if (tohost == 32'd1) $finish;
            else $fatal(1, "tb: FAIL");
        end
        if (cycles >= max_cycles) $fatal(1, "tb: FAIL, sin halt después de %0d ciclos", cycles);
    end
endmodule
