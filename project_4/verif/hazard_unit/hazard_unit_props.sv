// hazard_unit — propiedades formales: seguridad (correcto) y precisión (eficiente).
//
// El contrato depende del SIGNIFICADO de la
// instrucción que está en ID, no solo de los números de registro. Por eso las
// entradas libres incluyen la instrucción completa (id_inst), y los campos
// rs1/rs2 se extraen exactamente como en riscv_pipeline.v.
//
// Hay dos tipos de propiedad:
//   SEGURIDAD  — "nunca falta un stall necesario"  (si falla: resultados MAL)
//   PRECISIÓN  — "nunca sobra un stall"            (si falla: resultados BIEN
//                                                   pero se pierden ciclos)

module hazard_unit_props (
    input [31:0] id_inst,       // instrucción en ID (cualquiera de las 2^32)
    input        ex_mem_read,   // ¿la instrucción en EX es un load?
    input [4:0]  ex_rd          // su registro destino
);
    // Campos crudos, igual que en riscv_pipeline.v (líneas ~93-97)
    wire [6:0] opcode = id_inst[6:0];
    wire [4:0] id_rs1 = id_inst[19:15];
    wire [4:0] id_rs2 = id_inst[24:20];

    // ---------------------------------------------------------------- DUT
    wire stall;
`ifdef PRECISE
    // Variante alternativa: conoce el opcode (ver hazard_unit_precise.v)
    hazard_unit_precise dut (
        .ex_mem_read(ex_mem_read), .ex_rd(ex_rd),
        .id_rs1(id_rs1), .id_rs2(id_rs2), .id_opcode(opcode),
        .stall(stall)
    );
`else
    hazard_unit dut (
        .ex_mem_read(ex_mem_read), .ex_rd(ex_rd),
        .id_rs1(id_rs1), .id_rs2(id_rs2),
        .stall(stall)
    );
`endif

    // ------------------------------------------- ESPECIFICACIÓN (ISA RV32I)
    // Qué instrucciones LEEN rs1 / rs2 según el manual de RISC-V,
    // formato por formato. Esto es la especificación, no el RTL.
    localparam OP_R = 7'b0110011, OP_I    = 7'b0010011, OP_LOAD = 7'b0000011,
               OP_S = 7'b0100011, OP_B    = 7'b1100011, OP_JAL  = 7'b1101111,
               OP_JALR = 7'b1100111, OP_LUI = 7'b0110111, OP_AUIPC = 7'b0010111,
               OP_SYS  = 7'b1110011;

    wire uses_rs1 = opcode == OP_R || opcode == OP_I || opcode == OP_LOAD ||
                    opcode == OP_S || opcode == OP_B || opcode == OP_JALR;
    wire uses_rs2 = opcode == OP_R || opcode == OP_S || opcode == OP_B;

    // El riesgo load-use real: el load en EX escribe un registro (≠ x0) que
    // la instrucción en ID realmente va a leer.
    wire load_in_ex = ex_mem_read && ex_rd != 5'd0;
    wire needed = load_in_ex && ((uses_rs1 && ex_rd == id_rs1) ||
                                 (uses_rs2 && ex_rd == id_rs2));
    wire false_stall = stall && !needed;

    // Nota: "p → q" (implicación) se escribe !p || q. El frontend libre de
    // Yosys no acepta el operador -> de SystemVerilog dentro de un assert.

    wire legal = uses_rs1 || opcode == OP_JAL || opcode == OP_LUI ||
                 opcode == OP_AUIPC || opcode == OP_SYS;

    always @(*) begin
`ifdef LEGAL_ONLY
        // ---- SUPOSICIÓN opcional ----
        // El solver puede elegir CUALQUIER patrón de 32 bits, incluso opcodes
        // que no existen. Esto lo limita a instrucciones RV32I válidas, para
        // que el contraejemplo sea un programa real. Se usa solo en 'exact':
        // las propiedades de seguridad valen incluso sin esta suposición.
        a_legal: assume (legal);
`endif
        // ---- SEGURIDAD ----
        // S1: si hace falta un stall, hay stall.
        s1_stall_when_needed: assert (!needed || stall);      // needed → stall
        // S2: solo un load con destino ≠ x0 puede frenar el pipeline, y solo
        //     si coincide con algún campo de registro de la instrucción en ID.
        s2_stall_only_for_load: assert (!stall || (load_in_ex &&   // stall → ...
                                        (ex_rd == id_rs1 || ex_rd == id_rs2)));
        // S3: los formatos que usan rs1 Y rs2 nunca sufren stalls falsos
        //     (para ellos, "campo coincide" == "operando coincide").
        s3_no_false_RSB: assert (!(false_stall &&
                          (opcode == OP_R || opcode == OP_S || opcode == OP_B)));

`ifdef EXACT
        // ---- PRECISIÓN ----
        // E1: no hay stalls de más. Con el hazard_unit actual se ESPERA que falle.
        e1_no_false_stall: assert (!stall || needed);       // stall → needed
`endif

        // ---- COBERTURA: ¿qué formatos sufren stalls falsos? ----
        // Cada cover alcanzado es una clase de instrucción que pierde ciclos
        // sin necesidad. Juntos clasifican TODOS los casos posibles.
        f_I:     cover (false_stall && opcode == OP_I);
        f_LOAD:  cover (false_stall && opcode == OP_LOAD);
        f_JALR:  cover (false_stall && opcode == OP_JALR);
        f_JAL:   cover (false_stall && opcode == OP_JAL);
        f_LUI:   cover (false_stall && opcode == OP_LUI);
        f_AUIPC: cover (false_stall && opcode == OP_AUIPC);
        f_SYS:   cover (false_stall && opcode == OP_SYS);
        // Y que el stall necesario también ocurre (no es vacío):
        c_needed_rs1: cover (needed && ex_rd == id_rs1 && ex_rd != id_rs2);
        c_needed_rs2: cover (needed && ex_rd == id_rs2 && ex_rd != id_rs1);
    end
endmodule
