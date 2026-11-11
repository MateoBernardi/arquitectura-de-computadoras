# `uart/` — UART con FIFOs

Receptor y transmisor UART 8N1, con una cola circular en cada lado.

```
                    ┌──────────────┐   i_rx (sincronizado)   ┌──────────┐
  byte desde la  ──▶│              │─────────────────────────▶│  uart_rx │
  debug unit      │  uart_core   │   o_tx                   │          │
                   │              │◀─────────────────────────│  uart_tx │
  byte hacia la   ──▶│              │                          └──────────┘
  debug unit      │              │
                   └──┬────────┬──┘
                      │        │
                   RX_FIFO  TX_FIFO
```

---

## `uart_core.v` — `uart_core`

El bloque que junta todo. La interfaz del lado "datos" calza **exactamente** con los
puertos de `uart_interface`, así que no hace falta glue logic entre la debug unit y
este módulo.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `i_clk` | 1 | |
| `i_reset` | 1 | |
| `i_rx` | 1 | línea física de recepción (ya sincronizada) |
| `i_read_uart` | 1 | pide un byte del FIFO de RX |
| `i_write_uart` | 1 | escribe un byte en el FIFO de TX |
| `i_data_to_write` | 8 | byte a enviar |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `o_tx` | 1 | línea física de transmisión |
| `o_tx_full` | 1 | el FIFO de TX está lleno |
| `o_rx_empty` | 1 | no hay nada en el FIFO de RX |
| `o_rx_full` | 1 | el FIFO de RX está lleno |
| `o_data_to_read` | 8 | byte del FIFO de RX |

**Parámetros**: `CLK_FREQ` (100 MHz), `BAUD_RATE` (19200), `NB_DATA` (8),
`N_TICKS` (16, el factor de sobremuestreo), `PTR_LEN` (2 → FIFO de 4 palabras).

**Instancias**: `BAUD_GEN`, `RX`, `RX_FIFO`, `TX_FIFO`, `TX`.

> El FIFO de TX **se vacía solo**: `o_tx_done` lo hace pop y `~tx_empty` alimenta
> `i_tx_ready`, así que los bytes encolados salen **uno atrás de otro, sin huecos**.

---

## `baud_rate_gen.v` — `baud_rate_gen`

Genera un **tick** por bit (con sobremuestreo).

**Entradas**: `i_clk`, `i_reset`
**Salidas**: `o_tick` — un pulso por cada `N_TICKS` de reloj.

**Cálculo**: `MODULUS = CLK_FREQ / (BAUD_RATE * N_TICKS)`. Con 100 MHz, 19200 baud y
16 ticks → `MODULUS = 325`. El contador de `MODULUS` se recorta con
`CLK_FREQ/(BAUD_RATE*4)` para el caso de 1 tick.

---

## `uart_rx.v` — `uart_rx`

El receptor. Está partido en 3 módulos (FSM / combinacional / registros) pero los
puertos y el comportamiento ciclo a ciclo son los de siempre.

**Entradas**: `i_clk`, `i_reset`, `i_rx`, `i_tick`
**Salidas**: `o_rx_done` (1 cuando llegó un byte completo), `o_dout` (el byte)

**Internos**: `uart_rx_comb`, `uart_rx_fsm`, `uart_rx_regs`.

---

## `uart_rx_comb.v` — `uart_rx_comb`

Datapath combinacional del receptor: los próximos valores de los contadores y del
byte, según los controles que le pasa la FSM. También devuelve los **flags** que la
FSM vuelve a leer.

| Salida | Significado |
|---|---|
| `o_s_next` | próximo valor del contador de ticks `s` |
| `o_n_next` | próximo valor del contador de bits `n` |
| `o_byte_next` | próximo valor del byte recibido |
| `o_s_half` | `s == N_TICKS/2 - 1` (medio bit) |
| `o_s_last` | `s == N_TICKS - 1` (bit completo) |
| `o_n_last` | `n == NB_DATA - 1` (último bit del byte) |

---

## `uart_rx_fsm.v` — `uart_rx_fsm`

Máquina de estados del receptor. Combinacional.

| Estado | Qué hace |
|---|---|
| `IDLE` (0) | espera el start bit |
| receiving | corre el start bit, los 8 bits y el stop bit, contando con `s` y `n` |

Devuelve `o_state_next` y los controles del datapath: `o_s_clear`, `o_s_inc`,
`o_n_clear`, `o_n_inc`, `o_shift` (desplazar el bit de `i_rx` al byte) y `o_rx_done`.

El registro de estado está en `uart_rx_regs`; `IDLE = 0` es su valor de reset.

---

## `uart_rx_regs.v` — `uart_rx_regs`

Los registros del receptor: estado de la FSM, contador de ticks `s`, contador de
bits `n` y el byte recibido. Reset sincrónico activo en alto; el estado vuelve a 0.

---

## `uart_tx.v` — `uart_tx`

El transmisor. Misma estructura que el receptor: FSM + combinacional + registros.

**Entradas**: `i_clk`, `i_reset`, `i_tx_ready` (hay datos en el FIFO), `i_tick`,
`i_din` (byte a enviar)
**Salidas**: `o_tx_done`, `o_tx` (la línea)

**Internos**: `uart_tx_comb`, `uart_tx_fsm`, `uart_tx_regs`.

---

## `uart_tx_comb.v` — `uart_tx_comb`

Datapath combinacional del transmisor: próximos valores de `s`, `n`, del byte a
enviar y de la línea de TX.

**Salidas**

| Puerto | Descripción |
|---|---|
| `o_s_next`, `o_n_next`, `o_byte_next` | próximos valores |
| `o_tx_next` | próximo nivel de la línea |
| `o_s_last`, `o_n_last` | flags para la FSM |

---

## `uart_tx_fsm.v` — `uart_tx_fsm`

FSM del transmisor: de `i_state` + `i_tx_ready` + `i_tick` + los flags del datapath
sale el próximo estado, los controles y **qué debe mostrar la línea**.

| Salida | Significado |
|---|---|
| `o_state_next` | próximo estado |
| `o_s_clear`, `o_s_inc`, `o_n_clear`, `o_n_inc` | controles de contadores |
| `o_load` | cargar `i_din` en el byte a enviar |
| `o_shift` | desplazar el byte a enviar a la derecha |
| `o_tx_data` | 1 → la línea muestra el bit de datos actual |
| `o_tx_level` | nivel de la línea cuando `o_tx_data = 0` |
| `o_tx_done` | se terminó de enviar el byte |

---

## `uart_tx_regs.v` — `uart_tx_regs`

Registros del transmisor: estado de la FSM, contadores `s` y `n`, byte a enviar y
la línea `o_tx`. En el reset el estado vuelve a 0 (IDLE) y la línea a **1** (reposo,
como manda el protocolo UART).

---

## `fifo.v` — `fifo`

FIFO circular genérico, profundidad `2**PTR_LEN` (con `PTR_LEN = 2` → 4 palabras),
de `NB_DATA` bits.

**Entradas**: `i_clk`, `i_reset`, `i_read_fifo`, `i_write_fifo`, `i_data_to_write`
**Salidas**: `o_fifo_is_empty`, `o_fifo_is_full`, `o_data_to_read`

Se usa **dos veces**: una para el RX y otra para el TX.

---

## Nota sobre `N_TICKS`

Los umbrales de "medio bit" y "bit completo" se derivan de `N_TICKS` y `NB_DATA`
(están en `uart_rx_comb`), así que no están fijos en 16/8 como en la versión
original: se pueden cambiar por parámetro.
