`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_top - Test de integracion: top + registers + alu_tp1 juntos, manejados
// por los pines externos (switch/button/i_reset) como lo haria la placa.
//
// Nota: no se usa $dumpfile/$dumpvars (cuelga XSIM); para ver formas de onda
// usar el waveform viewer nativo de Vivado.
//////////////////////////////////////////////////////////////////////////////////

module tb_top;

    parameter NB_DATA   = 8;
    parameter NB_OP     = 6;
    parameter NB_BITS   = 8;
    parameter NB_BUTTON = 3;

    parameter NUM_RANDOM_PER_OP = 20;
    parameter VERBOSE           = 0;

    `include "alu_ops.vh"
    `include "model.vh"

    localparam [NB_BUTTON-1:0] BTN_NONE    = 3'b000;
    localparam [NB_BUTTON-1:0] BTN_DATA_A  = 3'b001;
    localparam [NB_BUTTON-1:0] BTN_DATA_B  = 3'b010;
    localparam [NB_BUTTON-1:0] BTN_DATA_OP = 3'b100;

    reg  [NB_BITS-1:0]        switch;
    reg  [NB_BUTTON-1:0]      button;
    reg                       i_clk;
    reg                       i_reset;
    wire signed [NB_DATA-1:0] led;
    wire                      f_o;
    wire                      f_z;

    top
    #(
        .NB_DATA   (NB_DATA),
        .NB_BITS   (NB_BITS),
        .NB_OP     (NB_OP),
        .NB_BUTTON (NB_BUTTON)
    )
    uut (
        .switch  (switch),
        .button  (button),
        .i_clk   (i_clk),
        .i_reset (i_reset),
        .led     (led),
        .f_o     (f_o),
        .f_z     (f_z)
    );

    always begin
        i_clk = 0; #10;
        i_clk = 1; #10;
    end

    integer rnd_seed   = 32'hFACADA;
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    reg [NB_OP-1:0] op_list [0:7];

    localparam signed [NB_DATA-1:0] MAX_POS = {1'b0, {(NB_DATA-1){1'b1}}};
    localparam signed [NB_DATA-1:0] MIN_NEG = {1'b1, {(NB_DATA-1){1'b0}}};

    // Ultimo resultado bueno mostrado, usado por run_freeze_test.
    reg signed [NB_DATA-1:0] last_led;
    reg                      last_f_z;
    reg                      last_f_o;

    task automatic press_button;
        input [NB_BUTTON-1:0] btn;
        input [NB_BITS-1:0]   value;
        begin
            @(negedge i_clk);
            switch = value;
            button = btn;
            @(posedge i_clk);
            @(negedge i_clk);
            button = BTN_NONE;
        end
    endtask

    task automatic run_test;
        input signed [NB_DATA-1:0] a;
        input signed [NB_DATA-1:0] b;
        input        [NB_OP-1:0]   op;
        reg signed [NB_DATA-1:0] exp_data;
        reg                      exp_zero;
        reg                      exp_ovf;
        begin
            press_button(BTN_DATA_A,  a);
            press_button(BTN_DATA_B,  b);
            press_button(BTN_DATA_OP, op);

            // El resultado se registra un ciclo despues de soltar BTN_DATA_OP
            // (pulso op_loaded en registers.v). Esperamos al SIGUIENTE negedge
            // (medio periodo completo, ~10ns) en vez de solo #1 tras el
            // posedge de captura: en simulacion post-implementacion (delays
            // reales via SDF) 1ns no alcanza para que la cadena flip-flop ->
            // LUTs de la ALU -> flip-flop de salida -> pad se asiente, y se
            // termina leyendo el resultado del test anterior.
            @(negedge i_clk);

            alu_model(a, b, op, exp_data, exp_zero, exp_ovf);

            test_count = test_count + 1;
            if (led !== exp_data || f_z !== exp_zero || f_o !== exp_ovf) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d op=%b A=%0d B=%0d -> led=%0d (esp %0d)  f_z=%b (esp %b)  f_o=%b (esp %b)",
                          test_count, op, a, b, led, exp_data, f_z, exp_zero, f_o, exp_ovf);
            end else begin
                pass_count = pass_count + 1;
                if (VERBOSE)
                    $display("[ OK ] #%0d op=%b A=%0d B=%0d -> led=%0d f_z=%b f_o=%b",
                              test_count, op, a, b, led, f_z, f_o);
            end

            last_led = led;
            last_f_z = f_z;
            last_f_o = f_o;
        end
    endtask

    // Cambiar A/B sin volver a apretar BTN_DATA_OP no debe tocar la salida.
    task automatic run_freeze_test;
        begin
            press_button(BTN_DATA_A, $random(rnd_seed));
            @(negedge i_clk);
            test_count = test_count + 1;
            if (led !== last_led || f_z !== last_f_z || f_o !== last_f_o) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d la salida cambio sin un nuevo BTN_DATA_OP", test_count);
            end else pass_count = pass_count + 1;
        end
    endtask

    task automatic run_reset_test;
        begin
            @(negedge i_clk);
            i_reset = 1;
            @(negedge i_clk);
            test_count = test_count + 1;
            if (led !== {NB_DATA{1'b0}} || f_z !== 1'b0 || f_o !== 1'b0) begin
                fail_count = fail_count + 1;
                $display("[FAIL] #%0d el reset no limpio led/f_z/f_o (led=%0d f_z=%b f_o=%b)",
                          test_count, led, f_z, f_o);
            end else pass_count = pass_count + 1;
            @(negedge i_clk);
            i_reset = 0;
        end
    endtask

    integer i, j;

    initial begin
        switch  = 0;
        button  = BTN_NONE;
        i_reset = 1;

        op_list[0] = OP_ADD; op_list[1] = OP_SUB; op_list[2] = OP_AND; op_list[3] = OP_OR;
        op_list[4] = OP_XOR; op_list[5] = OP_SRA; op_list[6] = OP_SRL; op_list[7] = OP_NOR;

        // Esperamos a que termine el pulso de GSR (Global Set/Reset) que
        // Vivado inyecta al arrancar una simulacion post-implementacion
        // (via glbl.v, tipicamente ~100ns). Si empezamos a apretar botones
        // antes de que termine, esos primeros toques se pierden: los
        // flip-flops estan siendo forzados por GSR sin importar el reloj.
        // En simulacion RTL esto no hace nada (no hay glbl ni GSR), asi que
        // no molesta dejarlo siempre.
        #200;

        @(negedge i_clk);
        i_reset = 0;

        $display("==========================================================");
        $display(" TB_TOP - probando top (NB_DATA=%0d, NB_OP=%0d, NB_BITS=%0d)", NB_DATA, NB_OP, NB_BITS);
        $display("==========================================================");

        run_test(10, 20, OP_ADD);
        run_test(MAX_POS, 1, OP_ADD);
        run_test(MIN_NEG, -1, OP_ADD);

        run_test(20, 10, OP_SUB);
        run_test(MIN_NEG, 1, OP_SUB);
        run_test(MAX_POS, -1, OP_SUB);
        run_test(42, 42, OP_SUB);

        run_test(8'sb11110000, 8'sb10101010, OP_AND);
        run_test({NB_DATA{1'b1}}, {NB_DATA{1'b0}}, OP_OR);
        run_test(37, 37, OP_XOR);
        run_test({NB_DATA{1'b0}}, {NB_DATA{1'b0}}, OP_NOR);

        run_test(MIN_NEG, 1, OP_SRA);
        run_test(MIN_NEG, 1, OP_SRL);
        run_test(-1, 0, OP_SRA);

        run_test(5, 5, 6'b111111);

        // La salida debe quedar "congelada" hasta el proximo BTN_DATA_OP
        run_freeze_test();

        for (i = 0; i < 8; i = i + 1) begin
            for (j = 0; j < NUM_RANDOM_PER_OP; j = j + 1) begin
                if (op_list[i] == OP_SRA || op_list[i] == OP_SRL)
                    run_test($random(rnd_seed), rand_range(0, NB_DATA-1), op_list[i]);
                else
                    run_test($random(rnd_seed), $random(rnd_seed), op_list[i]);
            end
        end

        // Reset tras toda la actividad, para confirmar que limpia bien en integracion.
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