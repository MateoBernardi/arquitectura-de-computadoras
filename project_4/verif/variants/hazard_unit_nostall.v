`timescale 1ns / 1ps

// hazard_unit_nostall — VARIANTE para probar una hipótesis (no está en el diseño).
//
// Mismo nombre de módulo y mismos puertos que flow/hazard_unit.v (mismo
// contrato de puertos), pero NUNCA frena el pipeline. Si el CPU entero sigue
// cumpliendo la especificación con esta variante, el stall de load-use no
// hace falta para la corrección (ver verif/README.md, "Variantes").
module hazard_unit (
    input       ex_mem_read,
    input [4:0] ex_rd,
    input [4:0] id_rs1,
    input [4:0] id_rs2,
    input [6:0] id_opcode,
    output      stall
);
    assign stall = 1'b0;
endmodule
