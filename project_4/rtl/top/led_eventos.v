`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// led_eventos: hace visibles en un LED eventos que duran un ciclo de reloj
//
// - CPU corriendo: un evento dura 20 ns y el ojo no lo ve. Cada evento se recuerda
//   durante una ventana de 2^VENTANA_LOG2 ciclos (2^22 a 70 MHz = 60 ms): el LED
//   queda prendido en la ventana siguiente a la que tuvo el evento. Un evento que se
//   repite seguido deja el LED prendido fijo.
// - CPU detenido (paso a paso o en pausa): las señales del pipeline no cambian, así
//   que el LED muestra además el evento del ciclo actual tal cual (la OR con i_ev).
// -----------------------------------------------------------------------------
module led_eventos #(
    parameter N           = 6,
    parameter VENTANA_LOG2 = 22
) (
    input  wire         i_clk,
    input  wire         i_reset,
    input  wire         i_en,       // el CPU avanzó en este ciclo
    input  wire [N-1:0] i_ev,       // eventos del ciclo actual (combinacionales)
    output wire [N-1:0] o_led
);
    reg [VENTANA_LOG2-1:0] cnt;
    reg [N-1:0]            visto, mostrar;

    always @(posedge i_clk) begin
        if (i_reset) begin
            cnt     <= 0;
            visto   <= 0;
            mostrar <= 0;
        end else begin
            cnt <= cnt + 1'b1;
            if (&cnt) begin                     // fin de la ventana
                mostrar <= visto | (i_en ? i_ev : {N{1'b0}});
                visto   <= 0;
            end else if (i_en)
                visto <= visto | i_ev;
        end
    end

    assign o_led = mostrar | i_ev;
endmodule
