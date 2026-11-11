`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// display_7seg: muestra un valor de 32 bits en los 8 dígitos del display, en hex
//
// - Los 8 dígitos comparten los segmentos: se prende uno a la vez, cada
//   2^(REFRESCO_LOG2-3) ciclos, y el ojo ve los 8 (2^17 a 70 MHz: cada dígito
//   0,23 ms, la vuelta completa 1,9 ms ≈ 530 Hz).
// - Segmentos y ánodos activos en bajo (como en la placa). i_on = 0 apaga todo.
// - El dígito 7 (el de la izquierda) es el nibble más significativo.
// -----------------------------------------------------------------------------
module display_7seg #(
    parameter REFRESCO_LOG2 = 17
) (
    input  wire        i_clk,
    input  wire        i_on,
    input  wire [31:0] i_valor,
    output reg  [7:0]  o_an = 8'hFF,     // ánodo de cada dígito (0 = prendido)
    output reg  [6:0]  o_seg = 7'h7F     // segmentos {g,f,e,d,c,b,a} (0 = prendido)
);
    reg [REFRESCO_LOG2-1:0] cnt = 0;
    always @(posedge i_clk) cnt <= cnt + 1'b1;
    wire [2:0] dig = cnt[REFRESCO_LOG2-1 -: 3];

    wire [3:0] nib = i_valor[dig*4 +: 4];
    reg  [6:0] seg;
    always @(*) begin
        case (nib)                      //   gfedcba
            4'h0: seg = 7'b0111111;  4'h1: seg = 7'b0000110;
            4'h2: seg = 7'b1011011;  4'h3: seg = 7'b1001111;
            4'h4: seg = 7'b1100110;  4'h5: seg = 7'b1101101;
            4'h6: seg = 7'b1111101;  4'h7: seg = 7'b0000111;
            4'h8: seg = 7'b1111111;  4'h9: seg = 7'b1101111;
            4'hA: seg = 7'b1110111;  4'hB: seg = 7'b1111100;
            4'hC: seg = 7'b0111001;  4'hD: seg = 7'b1011110;
            4'hE: seg = 7'b1111001;  default: seg = 7'b1110001;   // F
        endcase
    end

    // registrados: los pines salen de un flip-flop, sin glitches
    always @(posedge i_clk) begin
        o_an  <= i_on ? ~(8'b1 << dig) : 8'hFF;
        o_seg <= ~seg;
    end
endmodule
