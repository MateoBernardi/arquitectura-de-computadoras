`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// register_file: banco de registros RV32I (32 x 32 bits)
//
// - x0 vale siempre 0: las escrituras a x0 se ignoran.
// - Lectura combinacional de rs1 y rs2 (ID), con bypass: si WB esta
//   escribiendo el mismo registro en este ciclo, se devuelve el dato nuevo.
// - Escritura en el flanco de subida, solo con el pipeline habilitado
//   (i_enable de la debug unit): los registros cambian cuando el pipeline
//   avanza. El bypass no depende del enable (la instruccion en ID lo usa en el
//   mismo flanco en que WB escribe).
// - Reset sincronico: todos los registros en 0 (implementado con flip-flops).
// - Puerto de lectura de debug, sin bypass: muestra el valor almacenado.
// -----------------------------------------------------------------------------
module register_file (
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire        i_enable,
    // lectura (ID)
    input  wire [4:0]  i_rs1,
    input  wire [4:0]  i_rs2,
    output wire [31:0] o_rs1_data,
    output wire [31:0] o_rs2_data,
    // escritura (WB)
    input  wire        i_write_enable,
    input  wire [4:0]  i_rd,
    input  wire [31:0] i_write_data,
    // debug
    input  wire [4:0]  i_dbg_addr,
    output wire [31:0] o_dbg_data
);
    reg [31:0] regs [0:31];

    wire write = i_write_enable & (i_rd != 5'd0);

    integer k;
    always @(posedge i_clock) begin
        if (i_reset) begin
            for (k = 0; k < 32; k = k + 1)
                regs[k] <= 32'd0;
        end
        else if (i_enable && write) begin
            regs[i_rd] <= i_write_data;
        end
    end

    assign o_rs1_data = (i_rs1 == 5'd0)            ? 32'd0        :
                        (write && (i_rd == i_rs1)) ? i_write_data : regs[i_rs1];
    assign o_rs2_data = (i_rs2 == 5'd0)            ? 32'd0        :
                        (write && (i_rd == i_rs2)) ? i_write_data : regs[i_rs2];
    assign o_dbg_data = (i_dbg_addr == 5'd0)       ? 32'd0        : regs[i_dbg_addr];
endmodule
