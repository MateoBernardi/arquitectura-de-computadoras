// tb_potencia.v — actividad del sistema para estimar la potencia (potencia.sh).
//
// top_riscv con sus parámetros de la placa (MMCM a 70 MHz, UART a 19200). El programa se
// escribe directo en la imem (cargarlo por la UART a 19200 baudios serían 60 ms de
// simulación solo de carga); después se manda 'R' por la línea serie, como el host, y el
// CPU corre la carga en bucle. potencia.sh registra la conmutación de cada señal
// (SAIF) durante VENTANA_US microsegundos de CPU corriendo.
`timescale 1ns / 1ps
module tb_potencia;
    parameter  integer VENTANA_US = 2000;
    localparam real    BIT_NS     = 1.0e9 / 19200;

    reg clk = 0, rx = 1, rst = 0;
    always #5 clk = ~clk;                 // 100 MHz, el oscilador de la placa
    wire       tx;
    wire [15:0] led;
    top_riscv dut (.i_clk(clk), .i_reset(rst), .i_rx(rx), .o_tx(tx), .i_sw(1'b1), .o_led(led),
                   .o_an(), .o_seg());

    reg [31:0] prog [0:255];
    integer k;
    task uart_send(input [7:0] b);
        integer i;
        begin
            rx = 0; #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin rx = b[i]; #(BIT_NS); end
            rx = 1; #(BIT_NS);
        end
    endtask

    initial begin
        for (k = 0; k < 256; k = k + 1) prog[k] = 32'h0000_0013;
        $readmemh("carga.hex", prog);
        #1 for (k = 0; k < 256; k = k + 1) dut.u_cpu.u_imem.mem[k] = prog[k];
        wait (dut.locked);
        #(20_000);                        // reset_gen y la UART se asientan
        uart_send("R");
        wait (led[0]);                    // CPU habilitado
        $display("tb_potencia: CPU corriendo en t = %0t ns", $time);
        $stop;                            // potencia.sh empieza a registrar el SAIF acá
        #(VENTANA_US * 1000);
        if (led[2]) $fatal(1, "tb_potencia: el CPU se detuvo (la carga tiene que ser un bucle)");
        $display("tb_potencia: fin de la ventana en t = %0t ns", $time);
        $finish;
    end
endmodule
