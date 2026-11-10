// dmem_props — la memoria de datos contra un modelo de bytes.
//
// Secuencial: el solver elige en cada ciclo una operación cualquiera (store
// o load de byte, media palabra o palabra; dirección alineada) y el dato que
// lee la dmem real tiene que ser el que dice la ISA, leyendo los bytes de un
// modelo trivial: un array de 32 bytes que arranca en 0.
//
// riscv-formal no modela el contenido de la memoria: esta prueba cubre que
// la dmem guarda y devuelve bien cada byte (sb/sh/sw, lb/lh/lbu/lhu/lw).

module dmem_props (
    input        clk,
    input        we,
    input [31:0] addr,
    input [31:0] wdata,
    input [2:0]  funct3
);
    localparam BYTES = 32;      // dmem de 8 palabras (chparam en el .sby)

    // ---------------------------------------------------------- RTL real
    wire [31:0] rdata, dbg_data;
    dmem u_dmem (.clk(clk), .we(we), .addr(addr), .wdata(wdata), .funct3(funct3),
                 .rdata(rdata), .dbg_addr(8'd0), .dbg_data(dbg_data));

    // ------------------------------------------------------ especificación
    reg [7:0] m [0:BYTES-1];
    integer k;
    initial for (k = 0; k < BYTES; k = k + 1) m[k] = 8'd0;

    wire [4:0] a0 = addr[4:0];
    wire [31:0] word = {m[a0 + 2'd3], m[a0 + 2'd2], m[a0 + 1'b1], m[a0]};
    reg  [31:0] spec_rdata;
    always @(*) case (funct3)
        3'd0:    spec_rdata = {{24{word[7]}},  word[7:0]};     // LB
        3'd1:    spec_rdata = {{16{word[15]}}, word[15:0]};    // LH
        3'd2:    spec_rdata = word;                            // LW
        3'd4:    spec_rdata = {24'd0, word[7:0]};              // LBU
        default: spec_rdata = {16'd0, word[15:0]};             // LHU
    endcase

    always @(posedge clk) if (we) begin
                             m[a0]        <= wdata[7:0];       // SB / SH / SW
        if (funct3 != 3'd0)  m[a0 + 1'b1] <= wdata[15:8];
        if (funct3 == 3'd2) begin
                             m[a0 + 2'd2] <= wdata[23:16];
                             m[a0 + 2'd3] <= wdata[31:24];
        end
    end

    // ----------------------------------------------------------- propiedades
    wire is_load_f3  = funct3 != 3'd3 && funct3 != 3'd6 && funct3 != 3'd7;
    wire is_store_f3 = funct3 <= 3'd2;
    wire aligned = (funct3[1:0] == 2'd2) ? addr[1:0] == 2'd0 :
                   (funct3[1:0] == 2'd1) ? addr[0]   == 1'b0 : 1'b1;

    always @(*) begin
        // Entorno: solo funct3 válidos y accesos alineados (como en el CPU)
        assume (we ? is_store_f3 : is_load_f3);
        assume (aligned);
        // Cada lectura (cuando no se escribe) da lo que dice el modelo
        if (!we) d1_read_matches: assert (rdata == spec_rdata);

        c_lb_after_sb: cover (!we && funct3 == 3'd0 && spec_rdata[31]);
        c_lhu_after_sh: cover (!we && funct3 == 3'd5 && spec_rdata[15:8] != 0);
    end
endmodule
