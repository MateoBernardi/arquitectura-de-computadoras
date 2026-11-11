# `top/` — `top_riscv`, el sistema en la placa

Une todo lo que va en la FPGA y lo conecta a los pines de la Nexys4 DDR: el reloj, el
reset, la UART, la debug unit y el CPU. No tiene lógica propia más allá de las conexiones,
el reloj y la palabra de versión.

```
  i_clk (100 MHz) ──▶ MMCM ──▶ reloj del sistema (70 MHz) ──▶ todo lo de abajo
  i_reset (BTNC) ───▶ reset_gen ──▶ reset del sistema ──▶ uart_core, debug_unit
  i_rx ──▶ sync_2ff ──▶ uart_core ◀──bytes──▶ debug_unit ◀──control, carga, bus──▶ riscv_pipeline
  o_tx ◀───────────────── uart_core                │
  o_led ◀────────────────────────────── estado del CPU (habilitado, en reset, detenido)
```

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

```
             ┌──────────────────────┐
i_clk   1 ──▶│                      │──▶ o_tx  1  R
i_reset 1 ──▶│      top_riscv       │──▶ o_led 3  C
i_rx    1 ──▶│     [secuencial]     │
             │                      │
             └──────────────────────┘
```

| Pin | Placa | Qué es |
|---|---|---|
| `i_clk` | oscilador de 100 MHz | reloj de entrada |
| `i_reset` | botón BTNC | reset del sistema (activo en alto) |
| `i_rx`, `o_tx` | puente USB-serie (FTDI) | la UART hacia la PC: `/dev/ttyUSB1` en Linux |
| `o_led[0]` | LD0 | CPU habilitado (corriendo) |
| `o_led[1]` | LD1 | CPU en reset (por ejemplo, durante la carga) |
| `o_led[2]` | LD2 | CPU detenido (`ebreak`, `ecall` o un trap) |

Los pines están en `constraints/nexys4ddr_top.xdc`.

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
| `BUILD_ID` | 0 | versión del RTL; la síntesis le pasa el commit (ver abajo) |

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
89): `BUILD_ID`, el commit del RTL con que se sintetizó. `verif/fpga/synth.tcl` lo pasa
como parámetro (si `rtl/` y `constraints/` no tienen cambios sin commitear; si no, 0), el
host lo muestra, y la verificación en la placa lo usa para comprobar que el bitstream
cargado es el del commit que se está probando.

## Puertos asíncronos

Ninguno de los pines tiene relación de fase con el reloj del sistema, y el diseño los trata
así: `i_rx` e `i_reset` pasan por un sincronizador (`sync_2ff`) y `o_tx` sale de un
registro. Por eso en el XDC están excluidos del análisis de timing (`set_false_path`), con
el motivo escrito.
