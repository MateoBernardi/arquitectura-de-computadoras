# `top/` — `top_riscv`, el sistema en la placa

Une todo lo que va en la FPGA y lo conecta a los pines de la Nexys4 DDR: el reloj, el
reset, la UART, la debug unit y el CPU, y muestra lo que hace el CPU en los LEDs y el
display. No tiene lógica propia más allá de las conexiones, el reloj, la palabra de versión
y esa visualización.

```
  i_clk (100 MHz) ──▶ MMCM ──▶ reloj del sistema (70 MHz) ──▶ todo lo de abajo
  i_reset (BTNC) ───▶ reset_gen ──▶ reset del sistema ──▶ uart_core, debug_unit
  i_rx ──▶ sync_2ff ──▶ uart_core ◀──bytes──▶ debug_unit ◀──control, carga, bus──▶ riscv_pipeline
  o_tx ◀───────────────── uart_core                │
  o_led ◀──── led_eventos ◀───────────────────── eventos del pipeline, estado del CPU
  o_an, o_seg ◀── display_7seg ◀── última escritura en un registro ◀──┘   (i_sw: prende el display)
```

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

```
             ┌──────────────────────┐
i_clk   1 ──▶│                      │──▶ o_tx   1  R
i_reset 1 ──▶│      top_riscv       │──▶ o_led 16  C
i_rx    1 ──▶│     [secuencial]     │──▶ o_an   8  R
i_sw    1 ──▶│                      │──▶ o_seg  7  R
             │                      │
             └──────────────────────┘
```

| Pin | Placa | Qué es |
|---|---|---|
| `i_clk` | oscilador de 100 MHz | reloj de entrada |
| `i_reset` | botón BTNC | reset del sistema (activo en alto) |
| `i_rx`, `o_tx` | puente USB-serie (FTDI) | la UART hacia la PC: `/dev/ttyUSB1` en Linux |
| `i_sw[0]` | SW0 | prende el display |
| `o_led`, `o_an`, `o_seg` | LD0..LD15, display de 8 dígitos | ver "LEDs y display" |

Los pines están en `constraints/nexys4ddr_top.xdc`.

## LEDs y display

Muestran en la placa lo que hace el CPU, sin la PC. Corriendo a 70 MHz cada evento dura
14 ns, así que los LEDs de eventos los estira `led_eventos`; paso a paso (con `S` desde el
host) muestran el ciclo actual.

| LED | Qué muestra |
|---|---|
| LD0 | CPU habilitado (corriendo) |
| LD1 | CPU en reset (por ejemplo, durante la carga) |
| LD2 | CPU detenido (`ebreak`, `ecall` o un trap) |
| LD3..LD7 | con el display prendido: el número del registro de la última escritura (LD7 el bit más significativo) |
| LD10 | forwarding al operando A |
| LD11 | forwarding al operando B |
| LD12 | stall de load-use |
| LD13 | flush por un salto tomado (branch, `jal`, `jalr`) |
| LD14 | detenido por una excepción: un trap que no es `ecall` ni `ebreak` (instrucción ilegal, salto o acceso desalineado, fuera de memoria) |
| LD15 | CPU detenido (lo mismo que LD2, junto a los eventos) |

Con **SW0** arriba, el display muestra en hexadecimal el valor que escribió en su registro
la última instrucción que escribió uno (x1..x31), y LD3..LD7 el número de ese registro. Paso
a paso se ve la salida de cada instrucción; corriendo, al detenerse queda la última. Se
borra con el reset del CPU (al cargar un programa o con `X`).

Los eventos vienen del pipeline (`o_eventos`, ver [`../pipeline/README.md`](../pipeline/README.md)).
La excepción y el halt son niveles y se muestran tal cual.

### `led_eventos` — eventos visibles

```
             ┌──────────────────────┐
i_clk   1 ──▶│                      │──▶ o_led N  C
i_reset 1 ──▶│     led_eventos      │
i_en    1 ──▶│       [mixto]        │
i_ev    N ──▶│                      │
             │                      │
             └──────────────────────┘
```

Cada evento se recuerda durante una ventana de 2^22 ciclos (60 ms a 70 MHz) y el LED queda
prendido toda la ventana siguiente: un evento aislado se ve, y uno que se repite deja el
LED fijo. Además, el LED muestra el evento del ciclo actual (`i_ev`, combinacional): con el
CPU detenido las señales del pipeline no cambian, así que paso a paso se ve el ciclo en el
que está. Se limpia con el reset del CPU, para que no queden eventos del programa anterior.

### `display_7seg` — display multiplexado

```
              ┌──────────────────────┐
i_clk    1 ──▶│                      │──▶ o_an  8  R
i_on     1 ──▶│     display_7seg     │──▶ o_seg 7  R
i_valor 32 ──▶│     [secuencial]     │
              │                      │
              └──────────────────────┘
```

Los 8 dígitos comparten los segmentos: se prende uno por vez, cada 2^14 ciclos (0,23 ms),
y la vuelta completa (1,9 ms, unos 530 Hz) es demasiado rápida para notar el parpadeo. Las
salidas salen de registros (sin glitches en los pines). Segmentos y ánodos son activos en
bajo, como en la placa.

## Parámetros

| Parámetro | Valor | Para qué |
|---|---|---|
| `CLK_FREQ` | 100 000 000 | frecuencia de `i_clk` (la del oscilador de la placa) |
| `USE_MMCM` | 1 | 1: el sistema corre a `SYS_FREQ`, generada por el MMCM; 0: usa `i_clk` directo (simulación) |
| `MMCM_MULT` | 7 | VCO = `CLK_FREQ` × `MMCM_MULT` = 700 MHz (600 a 1200 MHz en el Artix-7 -1) |
| `MMCM_DIV_X8` | 80 | divisor de salida × 8 (va en pasos de 0,125): `SYS_FREQ` = VCO / 10 = **70 MHz** |
| `BAUD_RATE` | 19 200 | velocidad de la UART (ver [`../uart/README.md`](../uart/README.md)) |
| `N_TICKS` | 16 | muestras por bit de la UART |
| `PTR_LEN` | 2 | profundidad de las colas de la UART: 4 bytes |
| `IMEM_ADDR_W` | 10 | imem de 1 KB (256 instrucciones) |
| `BUILD_ID` | 0 | versión del hardware; la síntesis le pasa un commit (ver abajo) |

## El reloj

El sistema corre a **70 MHz**, generados por un MMCM a partir de los 100 MHz de la placa:
es la frecuencia más alta, en pasos de 10 MHz, a la que el diseño cierra timing
(`verif/fpga/fmax.sh`); a 80 MHz ya no. El camino más largo es el de un salto que depende de
la instrucción anterior: forwarding → ALU → comparación → descarte de las instrucciones del
camino equivocado, unos 13,7 ns. El detalle está en [`verif/fpga/README.md`](../../verif/fpga/README.md)
y en [`RESULTADOS.md`](../../RESULTADOS.md).

Para cambiar la frecuencia alcanza con `MMCM_MULT` y `MMCM_DIV_X8`: la UART calcula su
divisor con `SYS_FREQ`, y Vivado deriva la restricción del reloj del sistema a partir de la
del reloj de entrada (en el XDC), así que no hay nada más que tocar. Mientras el MMCM no
enganchó (`locked`), el sistema queda en reset.

## La palabra de versión

La debug unit lee del CPU un mapa de 89 palabras; `top_riscv` le agrega una al final (la
89): `BUILD_ID`, la versión del hardware con que se sintetizó: el último commit que cambió
`rtl/`, `constraints/` o los tcl de síntesis e implementación (0 si tienen cambios sin
commitear). `verif/run.sh` lo calcula y `verif/fpga/synth.tcl` lo pasa como parámetro; el
host lo muestra, y la verificación en la placa lo usa para comprobar que el bitstream
cargado es el del hardware que se está probando.

## Puertos asíncronos

Ninguno de los pines tiene relación de fase con el reloj del sistema, y el diseño los trata
así: `i_rx`, `i_reset` e `i_sw` pasan por un sincronizador (`sync_2ff`), `o_tx` sale de un
registro, y los LEDs y el display los mira una persona. Por eso en el XDC están excluidos del análisis de timing (`set_false_path`), con
el motivo escrito.
