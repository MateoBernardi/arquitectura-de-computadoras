# `uart/` — UART con colas

El enlace serie con la PC: recibe y envía bytes en formato **8N1** (8 bits de datos, sin
paridad, 1 bit de stop) por el chip USB-serie de la placa. Del otro lado está la debug
unit, que habla con la UART de a bytes y nunca ve los bits.

```
   PC ── USB ── FTDI ──▶ i_rx ──▶ sync_2ff ──▶ uart_rx ──▶ cola RX ──▶ debug_unit
                                                                        │
   PC ◀─ USB ── FTDI ◀── o_tx ◀────────────── uart_tx ◀── cola TX ◀─────┘
                         baud_rate_gen: un tick cada 1/16 de bit, para RX y TX
```

**Por qué las colas:** la debug unit y la línea serie trabajan a ritmos muy distintos
(un byte por la línea tarda unos 36 000 ciclos a 70 MHz). Las colas desacoplan los dos
lados: la debug unit deja un byte en la cola de TX y sigue; los bytes que llegan esperan
en la cola de RX hasta que la debug unit los lee.

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

## `uart_core` — el bloque completo

Lo que instancia `top_riscv`. Del lado de la debug unit, la interfaz son dos colas: se
lee un byte de RX cuando no está vacía y se escribe uno en TX cuando no está llena.

```
                     ┌──────────────────────┐
i_clk           1 ──▶│                      │──▶ o_tx           1  R
i_reset         1 ──▶│                      │──▶ o_rx_empty     1  R
i_rx            1 ──▶│      uart_core       │──▶ o_rx_full      1  R
i_read_uart     1 ──▶│     [secuencial]     │──▶ o_tx_full      1  R
i_write_uart    1 ──▶│                      │──▶ o_data_to_read 8  C
i_data_to_write 8 ──▶│                      │
                     └──────────────────────┘
```

`o_data_to_read` es el byte del frente de la cola de RX: se lee sin esperar un ciclo, y
`i_read_uart` lo saca de la cola. La cola de TX se vacía sola: cuando el transmisor
termina un byte toma el siguiente, así que los bytes encolados salen uno detrás de otro.

| Parámetro | En el sistema | Para qué |
|---|---|---|
| `CLK_FREQ` | `SYS_FREQ` (70 MHz) | frecuencia del reloj, para calcular el baud rate |
| `BAUD_RATE` | 19200 | velocidad de la línea |
| `NB_DATA` | 8 | bits por dato |
| `N_TICKS` | 16 | muestras por bit (sobremuestreo) |
| `PTR_LEN` | 2 | profundidad de cada cola: 2^`PTR_LEN` = 4 bytes |

**Por qué 19200 baudios:** el divisor del generador de baud es entero, y con 19200 es
grande (de 162 a 325 entre 50 y 100 MHz), así que el error de baud queda por debajo del
0,62 % a cualquier frecuencia del sistema. Con 115200 el divisor es chico y el error
llegaría al 3,7 %, cerca de lo que tolera una UART.

## `baud_rate_gen` — el ritmo de la línea

Un contador que da un pulso (`tick`) cada `CLK_FREQ / (BAUD_RATE · N_TICKS)` ciclos: 16
veces por bit. RX y TX cuentan esos ticks para saber dónde están dentro de cada bit.

```
             ┌──────────────────────┐
i_clk   1 ──▶│                      │──▶ o_tick 1  C
i_reset 1 ──▶│    baud_rate_gen     │
             │     [secuencial]     │
             │                      │
             └──────────────────────┘
```

`o_tick` compara el contador (un registro) con su valor final.

## `uart_rx` — receptor

Espera el bit de start, se ubica en el **medio** de cada bit (8 ticks después del flanco)
para muestrear donde la señal es estable, junta los 8 bits y verifica el bit de stop.

```
             ┌──────────────────────┐
i_clk   1 ──▶│                      │──▶ o_rx_done 1  C
i_reset 1 ──▶│       uart_rx        │──▶ o_dout    8  R
i_rx    1 ──▶│     [secuencial]     │
i_tick  1 ──▶│                      │
             └──────────────────────┘
```

`o_rx_done` es un pulso de un ciclo cuando llega un byte completo; `uart_core` lo usa para
meter `o_dout` en la cola de RX.

## `uart_tx` — transmisor

Cuando hay un byte en la cola, lo envía: bit de start (0), los 8 bits empezando por el
menos significativo, y el bit de stop (1). Cada bit dura 16 ticks.

```
                ┌──────────────────────┐
i_clk      1 ──▶│                      │──▶ o_tx_done 1  C
i_reset    1 ──▶│       uart_tx        │──▶ o_tx      1  R
i_tx_ready 1 ──▶│     [secuencial]     │
i_tick     1 ──▶│                      │
i_din      8 ──▶│                      │
                └──────────────────────┘
```

`i_tx_ready` es "la cola de TX no está vacía"; `o_tx_done` saca el byte de la cola al
terminar. La línea sale de un registro, así no tiene glitches, y en el reset queda en 1
(reposo).

## Cómo están armados RX y TX

Cada uno está partido en tres módulos con la misma división, que separa lo que decide
de lo que guarda:

| Módulo | Tipo | Qué hace |
|---|---|---|
| `uart_rx_fsm`, `uart_tx_fsm` | combinacional | la máquina de estados: con el estado actual y los flags del datapath, decide el próximo estado y qué hacer en este ciclo (contar, desplazar, terminar) |
| `uart_rx_comb`, `uart_tx_comb` | combinacional | el datapath: los próximos valores de los contadores (ticks dentro del bit, bits del byte) y del byte, y los flags que lee la FSM ("medio bit", "último bit") |
| `uart_rx_regs`, `uart_tx_regs` | secuencial | los registros: estado, contadores, byte y, en TX, la línea |

Los umbrales ("medio bit", "bit completo", "último bit") se derivan de `N_TICKS` y
`NB_DATA`, así que se pueden cambiar por parámetro.

## `fifo` — cola circular

Una cola de `2^PTR_LEN` datos de `NB_DATA` bits, con un puntero de lectura y uno de
escritura. Se usa dos veces: para RX y para TX.

```
                     ┌──────────────────────┐
i_clk           1 ──▶│                      │──▶ o_fifo_is_empty 1  R
i_reset         1 ──▶│         fifo         │──▶ o_fifo_is_full  1  R
i_read_fifo     1 ──▶│     [secuencial]     │──▶ o_data_to_read  8  C
i_write_fifo    1 ──▶│                      │
i_data_to_write 8 ──▶│                      │
                     └──────────────────────┘
```

Escribir con la cola llena o leer con la cola vacía no hace nada. `o_data_to_read` es
siempre el dato del frente (lectura asíncrona: Vivado la implementa como RAM distribuida).
