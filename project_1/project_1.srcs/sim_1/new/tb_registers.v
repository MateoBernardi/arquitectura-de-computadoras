`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_registers - Test unitario del banco de registros (registers.v), en
// AISLAMIENTO de la ALU: los valores de i_alu_result/i_alu_z/i_alu_o se
// inyectan directamente como estimulos, simulando lo que "vería" el modulo
// si estuviera conectado a una ALU real. Esto permite validar la logica de
// timing (op_loaded, congelamiento, reset) sin depender de que alu_tp1 este
// bien o mal - esa parte ya la cubre tb_alu.
//////////////////////////////////////////////////////////////////////////////////

module tb_registers;

    parameter NB_DATA   = 8;
    parameter NB_OP     = 6;
    parameter NB_BUTTON = 3;

    parameter NUM_RANDOM = 100;
    parameter VERBOSE    = 0;

    `include "alu_ops.vh"

    localparam [NB_BUTTON-1:0] BTN_NONE    = 3'b000;
    localparam [NB_BUTTON-1:0] BTN_DATA_A  = 3'b001;
    localparam [NB_BUTTON-1:0] BTN_DATA_B  = 3'b010;
    localparam [NB_BUTTON-1:0] BTN_DATA_OP = 3'b100;

    reg                       i_clk;
    reg                       i_reset;
    reg  [NB_BUTTON-1:0]      i_button;
    reg  [NB_DATA-1:0]        i_switch;
    reg  signed [NB_DATA-1:0] i_alu_result;
    reg                       i_alu_z;
    reg                       i_alu_o;

    wire [NB_DATA-1:0]        o_data_a;
    wire [NB_DATA-1:0]        o_data_b;
    wire [NB_OP-1:0]          o_data_op;
    wire signed [NB_DATA-1:0] o_led;
    wire                      o_f_z;
    wire                      o_f_o;

    registers
    #(
        .NB_DATA   (NB_DATA),
        .NB_OP     (NB_OP),
        .NB_BUTTON (NB_BUTTON)
    )
    uut
    (
        .i_clk        (i_clk),
        .i_reset      (i_reset),
        .i_button     (i_button),
        .i_switch     (i_switch),
        .i_alu_result (i_alu_result),
        .i_alu_z      (i_alu_z),
        .i_alu_o      (i_alu_o),
        .o_data_a     (o_data_a),
        .o_data_b     (o_data_b),
        .o_data_op    (o_data_op),
        .o_led        (o_led),
        .o_f_z        (o_f_z),
        .o_f_o        (o_f_o)
    );

    always begin
        i_clk = 0; #10;
        i_clk = 1; #10;
    end

    integer rnd_seed   = 32'hBEEFCA5;
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // ---------------------------------------------------------------
    // Presiona un boton durante un flanco de clock y lo vuelve a soltar,
    // igual que hace el usuario en la placa.
    // ---------------------------------------------------------------
    task automatic press_button;
        input [NB_BUTTON-1:0] btn;
        input [NB_DATA-1:0]   value;
        begin
            @(negedge i_clk);
            i_switch = value;
            i_button = btn;
            @(posedge i_clk);
            @(negedge i_clk);
            i_button = BTN_NONE;
        end
    endtask

    // ---------------------------------------------------------------
    // Carga A y B, y chequea que se hayan registrado bien.
    // ---------------------------------------------------------------
    task automatic run_load_test;
        input [NB_DATA-1:0] a;
        input [NB_DATA-1:0] b;
        begin
            press_button(BTN_DATA_A, a);
            test_count = test_count + 1;
            if (o_data_a !== a) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d o_data_a=%0d (esp %0d)", test_count, o_data_a, a);
            end else pass_count = pass_count + 1;

            press_button(BTN_DATA_B, b);
            test_count = test_count + 1;
            if (o_data_b !== b) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d o_data_b=%0d (esp %0d)", test_count, o_data_b, b);
            end else pass_count = pass_count + 1;
        end
    endtask

    // ---------------------------------------------------------------
    // Caso completo: carga A/B, presiona OP con un "resultado de ALU"
    // simulado, y valida:
    //   1) que o_led/o_f_z/o_f_o NO cambien en el mismo flanco de OP
    //   2) que SI se actualicen un ciclo despues (latencia de op_loaded)
    //   3) que si la ALU "cambia de idea" despues sin volver a apretar OP,
    //      la salida quede congelada con el valor ya capturado
    // ---------------------------------------------------------------
    task automatic run_capture_test;
        input [NB_DATA-1:0]        a;
        input [NB_DATA-1:0]        b;
        input [NB_OP-1:0]          op;
        input signed [NB_DATA-1:0] alu_result;
        input                      alu_z;
        input                      alu_o;
        input signed [NB_DATA-1:0] alu_result2; // "otro" valor combinacional posterior
        input                      alu_z2;
        input                      alu_o2;
        reg signed [NB_DATA-1:0] prev_led;
        reg                      prev_f_z;
        reg                      prev_f_o;
        begin
            prev_led = o_led;
            prev_f_z = o_f_z;
            prev_f_o = o_f_o;

            run_load_test(a, b);

            // Lo que "vería" la ALU combinacional con este A/B/op
            i_alu_result = alu_result;
            i_alu_z      = alu_z;
            i_alu_o      = alu_o;

            press_button(BTN_DATA_OP, {{(NB_DATA-NB_OP){1'b0}}, op});

            // (1) o_data_op ya se cargo...
            test_count = test_count + 1;
            if (o_data_op !== op) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d o_data_op=%b (esp %b)", test_count, o_data_op, op);
            end else pass_count = pass_count + 1;

            // ...pero la salida registrada todavia NO debe haberse tocado
            test_count = test_count + 1;
            if (o_led !== prev_led || o_f_z !== prev_f_z || o_f_o !== prev_f_o) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d o_led/f_z/f_o cambiaron en el mismo flanco que BTN_DATA_OP", test_count);
            end else pass_count = pass_count + 1;

            // (2) Un flanco despues, ahora si debe verse el resultado
            @(posedge i_clk);
            #1;

            test_count = test_count + 1;
            if (o_led !== alu_result || o_f_z !== alu_z || o_f_o !== alu_o) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d captura tardia: o_led=%0d (esp %0d) o_f_z=%b (esp %b) o_f_o=%b (esp %b)",
                          test_count, o_led, alu_result, o_f_z, alu_z, o_f_o, alu_o);
            end else begin
                pass_count = pass_count + 1;
                if (VERBOSE)
                    $display("[ OK ] #%0d capturado o_led=%0d o_f_z=%b o_f_o=%b", test_count, o_led, o_f_z, o_f_o);
            end

            // (3) La ALU "cambia de opinion" (ej: A/B nuevos para la proxima
            // cuenta) pero sin BTN_DATA_OP -> la salida debe seguir congelada
            i_alu_result = alu_result2;
            i_alu_z      = alu_z2;
            i_alu_o      = alu_o2;
            @(posedge i_clk);
            #1;

            test_count = test_count + 1;
            if (o_led !== alu_result || o_f_z !== alu_z || o_f_o !== alu_o) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d la salida no quedo congelada sin nuevo BTN_DATA_OP", test_count);
            end else pass_count = pass_count + 1;
        end
    endtask

    // ---------------------------------------------------------------
    // Reset sincronico: todo debe volver a 0, sin importar el estado previo.
    // ---------------------------------------------------------------
    task automatic run_reset_test;
        begin
            @(negedge i_clk);
            i_reset = 1;
            @(posedge i_clk);
            #1;
            test_count = test_count + 1;
            if (o_data_a !== 0 || o_data_b !== 0 || o_data_op !== 0 ||
                o_led !== 0 || o_f_z !== 0 || o_f_o !== 0) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d el reset no limpio todos los registros (a=%0d b=%0d op=%b led=%0d f_z=%b f_o=%b)",
                          test_count, o_data_a, o_data_b, o_data_op, o_led, o_f_z, o_f_o);
            end else pass_count = pass_count + 1;
            @(negedge i_clk);
            i_reset = 0;
        end
    endtask

    integer i;

    initial begin
        i_reset      = 1;
        i_button     = BTN_NONE;
        i_switch     = 0;
        i_alu_result = 0;
        i_alu_z      = 0;
        i_alu_o      = 0;

        @(negedge i_clk);
        i_reset = 0;

        $display("==========================================================");
        $display(" TB_REGISTERS - probando el modulo registers (NB_DATA=%0d, NB_OP=%0d)", NB_DATA, NB_OP);
        $display("==========================================================");

        // --- Casos dirigidos ---
        run_capture_test(10, 20, OP_ADD, 30, 1'b0, 1'b0, -5, 1'b0, 1'b0);
        run_capture_test(8'sd127, 1, OP_ADD, -8'sd128, 1'b0, 1'b1, 0, 1'b1, 1'b0); // "overflow" simulado
        run_capture_test(0, 0, OP_NOR, -1, 1'b0, 1'b0, 0, 1'b1, 1'b0);

        // --- Reset a mitad de actividad, con registros en valores no nulos ---
        run_reset_test();

        // --- Vectores aleatorios ---
        for (i = 0; i < NUM_RANDOM; i = i + 1) begin
            run_capture_test($random(rnd_seed), $random(rnd_seed), $random(rnd_seed),
                              $random(rnd_seed), $random(rnd_seed) & 1'b1, $random(rnd_seed) & 1'b1,
                              $random(rnd_seed), $random(rnd_seed) & 1'b1, $random(rnd_seed) & 1'b1);
        end

        // --- Reset final, tras actividad random, para confirmar que sigue limpiando bien ---
        run_reset_test();

        // ------------------- Resumen -------------------
        $display("==========================================================");
        $display(" %0d tests | %0d OK | %0d FALLADOS", test_count, pass_count, fail_count);
        if (fail_count == 0)
            $display(" RESULTADO: PASS");
        else
            $display(" RESULTADO: FAIL");
        $display("==========================================================");

        $finish;
    end

endmodule