// forward_unit — propiedades formales.
//
// Este módulo NO es hardware: es un "banco de pruebas matemático".
// Todas sus entradas quedan LIBRES: el solver puede elegir cualquier valor
// para cada una. Una propiedad queda probada solo si se cumple para TODAS
// las combinaciones posibles (acá: 2^(5*4+2) combinaciones de control
// por 2^(32*6) de datos, imposible de recorrer con un testbench).
//
// Las tres palabras clave:
//   assume(p) — "le pido al solver que solo considere casos donde p vale"
//               (lo que el resto del diseño GARANTIZA que nos llega)
//   assert(p) — "demostrá que p vale siempre" (lo que ESTE módulo garantiza)
//   cover(p)  — "mostrame UN caso donde p vale" (prueba de que no es vacuo)

module forward_unit_props (
    // Lo que ve forward_unit en el hardware real:
    input [4:0]  ex_rs1, ex_rs2,       // fuentes de la instrucción en EX
    input [4:0]  mem_rd,  input mem_reg_write,  // instrucción en MEM (1 más vieja)
    input [4:0]  wb_rd,   input wb_reg_write,   // instrucción en WB  (2 más vieja)
    // Valores simbólicos de datos (el solver elige cualquiera):
    input [31:0] rf_a, rf_b,           // lo que leyó el regfile en ID (ex_rdata1/2)
    input [31:0] mem_val,              // mem_result: lo que va a escribir MEM
    input [31:0] wb_val                // wb_result:  lo que va a escribir WB
);
    // ---------------------------------------------------------------- DUT
    wire [1:0] forward_a, forward_b;
    forward_unit dut (
        .ex_rs1(ex_rs1), .ex_rs2(ex_rs2),
        .mem_rd(mem_rd), .mem_reg_write(mem_reg_write),
        .wb_rd(wb_rd),   .wb_reg_write(wb_reg_write),
        .forward_a(forward_a), .forward_b(forward_b)
    );

    // Copia EXACTA del mux de riscv_pipeline.v (líneas ~177-187): lo que
    // termina viendo la ALU según la selección del forward_unit.
    function [31:0] fwd_mux(input [1:0] sel, input [31:0] rf, m, w);
        case (sel)
            2'b10:   fwd_mux = m;
            2'b01:   fwd_mux = w;
            default: fwd_mux = rf;
        endcase
    endfunction
    wire [31:0] operand_a = fwd_mux(forward_a, rf_a, mem_val, wb_val);
    wire [31:0] operand_b = fwd_mux(forward_b, rf_b, mem_val, wb_val);

    // ----------------------------------------------------------- CONTRATO
    // Escrito como lo diría la especificación, sin mirar el RTL:
    //   "El operando que usa EX para el registro rs debe ser el valor que
    //    escribió la instrucción MÁS RECIENTE que escribe rs. Si ninguna
    //    instrucción en vuelo lo escribe, vale lo que leyó el regfile.
    //    x0 nunca se escribe."
    function writes(input we, input [4:0] rd, input [4:0] rs);
        writes = we && (rd != 5'd0) && (rd == rs);
    endfunction
    function [31:0] newest(input [4:0] rs, input [31:0] rf);
        if      (writes(mem_reg_write, mem_rd, rs)) newest = mem_val; // MEM es más nueva
        else if (writes(wb_reg_write,  wb_rd,  rs)) newest = wb_val;
        else                                        newest = rf;
    endfunction

    always @(*) begin
        // ---- SUPOSICIONES (contratos de otros módulos) ----
        // El regfile garantiza que leer x0 da 0. No lo probamos acá:
        // es responsabilidad del regfile (lo cubre el chequeo 'reg' de rvfi/).
        if (ex_rs1 == 5'd0) assume (rf_a == 32'd0);
        if (ex_rs2 == 5'd0) assume (rf_b == 32'd0);

        // ---- GARANTÍAS de forward_unit ----
        // P1/P2: el operando es siempre el valor más reciente.
        p1_operand_a_newest: assert (operand_a == newest(ex_rs1, rf_a));
        p2_operand_b_newest: assert (operand_b == newest(ex_rs2, rf_b));

        // P3/P4: x0 se lee siempre como 0, aunque alguien "escriba" x0.
        if (ex_rs1 == 5'd0) p3_x0_a: assert (operand_a == 32'd0);
        if (ex_rs2 == 5'd0) p4_x0_b: assert (operand_b == 32'd0);

        // P5: la selección 2'b11 no tiene significado; nunca debe aparecer.
        p5_no_sel_11: assert (forward_a != 2'b11 && forward_b != 2'b11);

        // ---- COBERTURA: cada camino existe de verdad ----
        c1_a_from_mem: cover (forward_a == 2'b10);
        c2_a_from_wb:  cover (forward_a == 2'b01);
        c3_b_from_mem: cover (forward_b == 2'b10);
        c4_b_from_wb:  cover (forward_b == 2'b01);
        // El caso interesante: MEM y WB escriben el mismo registro y gana MEM.
        c5_both_write_rs1: cover (writes(mem_reg_write, mem_rd, ex_rs1) &&
                                  writes(wb_reg_write,  wb_rd,  ex_rs1));
        // A desde MEM y B desde WB al mismo tiempo.
        c6_a_mem_b_wb: cover (forward_a == 2'b10 && forward_b == 2'b01);
    end
endmodule
