# `debug/` — debug unit

Hace que el CPU se pueda cargar, controlar y observar desde la PC. Recibe comandos de un
byte por la UART, maneja el CPU con tres señales (habilitar, resetear, saber si se
detuvo), escribe los programas en la memoria de instrucciones y lee el estado interno
del CPU por un **bus de debug**.

```
            bytes                         enable / reset / halt
  uart_core ◀────▶ debug_unit ─────────────────────────────────▶ riscv_pipeline
                       │       carga de la imem (byte a byte)          ▲
                       ├───────────────────────────────────────────────┤
                       │       bus de debug: dirección → palabra       │
                       └───────────────────────────────────────────────┘
```

**Por qué existe:** el CPU no tiene periféricos ni un monitor propio. Sin la debug unit
no habría forma de cargarle un programa ni de ver qué hizo. Con ella, la PC puede correrlo
ciclo a ciclo y leer cada registro de pipeline, como en un simulador, pero sobre el
hardware real.

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

## `debug_unit`

```
                      ┌──────────────────────┐
i_clk            1 ──▶│                      │──▶ o_fifo_rx_read       1  C
i_reset          1 ──▶│                      │──▶ o_fifo_tx_write      1  C
i_data_to_read   8 ──▶│                      │──▶ o_data_to_write      8  C
i_fifo_rx_empty  1 ──▶│      debug_unit      │──▶ o_cpu_enable         1  C
i_fifo_tx_full   1 ──▶│     [secuencial]     │──▶ o_cpu_reset          1  C
i_cpu_halt       1 ──▶│                      │──▶ o_imem_write_enable  1  R
i_dbg_data      32 ──▶│                      │──▶ o_imem_write_addr   10  R
i_dbg_count     16 ──▶│                      │──▶ o_imem_write_data    8  R
                      │                      │──▶ o_dbg_addr          16  R
                      └──────────────────────┘
```

`o_imem_write_addr` tiene `IMEM_ADDR_W` bits (10 en el sistema: 1 KB). Las salidas C se
calculan a partir del estado de la máquina (registros), así que cambian en el flanco
aunque pasen por lógica combinacional.

| Parámetro | En el sistema | Para qué |
|---|---|---|
| `IMEM_ADDR_W` | 10 | tamaño de la imem en bytes: 2^10 = 1 KB = 256 instrucciones |

### Con el CPU

| Señal | Qué hace |
|---|---|
| `o_cpu_enable` | 1 = el CPU avanza: un solo ciclo con `S`, continuamente con `R`. Vale 0 en cuanto el CPU se detiene y mientras se hace un dump, así el estado no cambia mientras se lee |
| `o_cpu_reset` | reset del CPU: con el reset del sistema, durante toda la carga (`L`) y con `X` |
| `i_cpu_halt` | el CPU se detuvo (`ebreak`, `ecall` o un trap); durante `R` la debug unit lo avisa sola con `H` |
| `o_imem_write_*` | escriben el programa en la imem, un byte por vez |
| `o_dbg_addr` / `i_dbg_data` | piden una palabra del mapa de debug del CPU (ver [`../pipeline/README.md`](../pipeline/README.md)); `i_dbg_count` dice cuántas hay |

La dirección del bus de debug se mantiene un ciclo antes de leer el dato, así el mismo
bus sirve para fuentes combinacionales y para fuentes con un ciclo de latencia.

## El protocolo

Un byte de comando; cada comando tiene su respuesta.

| Comando | Respuesta | Qué hace |
|---|---|---|
| `L` n_lo n_hi + 4n bytes | `K` / `E` | carga un programa de n palabras (little-endian). Si es más corto que la imem, el resto se llena con NOP. Si no entra, escribe las palabras que entran, descarta el resto y responde `E` |
| `S` | `K` / `H` | avanza **un ciclo** (`H` si el CPU ya está detenido) |
| `R` | `K` / `H` | ejecución continua; cuando el CPU se detiene llega `H` sin que se pida |
| `P` | `K` | pausa la ejecución continua |
| `X` | `K` | reset del CPU: PC = 0, registros y pipeline en cero; el programa se conserva |
| `D` | n_lo n_hi + 4n bytes | el dump: las n palabras del mapa de debug (little-endian) |
| otro | `?` | comando desconocido |

Ni `L` ni `X` borran la dmem: ver [La dmem entre programas](../pipeline/4_memory/README.md#la-dmem-entre-programas).
El cliente del protocolo está en `host/lib/debug_protocol.py`.

## Cómo está armada

Igual que el receptor y el transmisor de la UART: lo que decide separado de lo que guarda.

| Módulo | Tipo | Qué hace |
|---|---|---|
| `debug_unit_fsm` | combinacional | la máquina de estados del protocolo: decodifica el comando, decide el próximo estado, la respuesta y las señales al CPU y a las colas |
| `debug_unit_comb` | combinacional | el datapath: longitud y contador de la carga, dirección y dato de la imem, dirección del bus de debug, la palabra del dump y cuál de sus 4 bytes se envía |
| `debug_unit_regs` | secuencial | todos los registros; en el reset vuelven a 0 (estado `IDLE`) |

| Estados | Para qué |
|---|---|
| `IDLE` | espera un comando |
| `LOAD_LEN_LO`, `LOAD_LEN_HI`, `LOAD_DATA`, `LOAD_FILL` | la carga: longitud, bytes del programa, relleno con NOP |
| `DUMP_CNT_LO`, `DUMP_CNT_HI`, `DUMP_ADDR`, `DUMP_LATCH`, `DUMP_BYTE` | el dump: cantidad de palabras, y por cada una pedirla, esperar el ciclo del bus y enviar sus 4 bytes |
| `REPLY` | envía la respuesta y vuelve a `IDLE` |

### Cómo la FSM lee el protocolo

La UART solo transporta bytes. Lo que significa cada uno lo decide la FSM según el estado
en que está. Algunos estados leen la cola RX y otros no:

| Estado | ¿Lee la cola RX? | Qué hace con el byte |
|---|---|---|
| `IDLE` | sí | lo interpreta como **comando**: un `case` sobre `L`, `S`, `R`, `P`, `X`, `D`; si no es ninguno, responde `?` |
| `LOAD_LEN_LO`, `LOAD_LEN_HI`, `LOAD_DATA` | sí | lo toma como **dato** (la longitud o un byte del programa), sin mirar su valor |
| `LOAD_FILL`, `REPLY`, `DUMP_*` | no | el byte queda esperando en la cola hasta volver a `IDLE` |

Entonces un comando es el byte que llega mientras la FSM está en `IDLE`. El mismo `0x4C`
(`'L'`) en `LOAD_DATA` es un byte de una instrucción. Por eso el protocolo no necesita
delimitadores ni escapes: el programa puede contener cualquier byte.

**La carga sabe dónde termina porque el host le manda la longitud.** Los dos bytes que
siguen a `L` son n, la cantidad de palabras. La FSM guarda n, pone un contador de bytes en
0 y en `LOAD_DATA` lo incrementa con cada byte. Cuando llega al byte 4n − 1
(`o_load_last`), pasa a `LOAD_FILL`. No puede usar "cola vacía" como fin del programa: a
19200 baudios llega un byte cada ~520 µs (unos 36.000 ciclos a 70 MHz), así que la cola
está vacía casi todo el tiempo y la FSM solo espera en `LOAD_DATA` al próximo byte.

**Qué pasa si llega un comando fuera de `IDLE`:**

- **En `LOAD_LEN_*` o `LOAD_DATA`** se consume como dato. Si el host anuncia n palabras y
  manda menos, la FSM queda en `LOAD_DATA` esperando los bytes que faltan, porque no hay
  timeout. Los comandos que lleguen después se escriben en la imem hasta completar los
  4n bytes. Para salir de ahí sin completarlos hay que apretar el botón de reset.
- **En `LOAD_FILL`, `REPLY` o `DUMP_*`** no se pierde: espera en la cola y se procesa como
  comando cuando la FSM vuelve a `IDLE`. El límite es el tamaño de la cola (4 bytes): si
  llegan más mientras nadie lee, los que no entran se pierden.

En la práctica esto no pasa porque el host (`host/lib/debug_protocol.py`) es sincrónico:
manda un comando y espera su respuesta (`K`, `E`, `H`, `?` o el dump completo) antes de
mandar el siguiente. La FSM solo responde al terminar, justo antes de volver a `IDLE`, así
que la respuesta funciona como aviso de que puede llegar otro comando.

### La lógica de la FSM

Todas las transiciones salen de `IDLE`. Las que leen la cola esperan `~rx_empty`, y las
que escriben esperan `~tx_full`. `LOAD_FILL`, `DUMP_ADDR` y `DUMP_LATCH` avanzan solos, un
paso por ciclo.

**Comandos de un byte** (`S`, `R`, `P`, `X` y cualquier byte desconocido):

```
IDLE ──'S' 'R' 'P' 'X' u otro──▶ REPLY ──(TX no llena)──▶ IDLE
IDLE ──halt con run = 1───────▶ REPLY ('H', sin que nadie lo pida)
```

Estos comandos no recorren estados propios: cambian registros de **modo** y pasan a `REPLY`
con la respuesta. `REPLY` la escribe en la cola TX y vuelve a `IDLE`.

| Comando | `run` | `step` (pulso de 1 ciclo) | `cpu_rst` (pulso) | Respuesta |
|---|---|---|---|---|
| `S` | 0 | 1, si el CPU no está detenido | — | `K`, o `H` si está detenido |
| `R` | 1, si el CPU no está detenido | — | — | `K`, o `H` si está detenido |
| `P` | 0 | — | — | `K` |
| `X` | 0 | — | 1 | `K` |
| `L` | 0 | — | — | (al final de la carga) |

La ejecución continua **no es un estado**: es `run = 1` con la FSM en `IDLE`. Por eso un
`P` durante `R` se atiende enseguida. En cada ciclo en `IDLE`, antes de mirar la cola RX,
la FSM se fija si el CPU se detuvo con `run = 1`. Si es así, pone `run = 0` y manda `H`.

**Carga** (`L`):

```
IDLE ─'L'─▶ LOAD_LEN_LO ─▶ LOAD_LEN_HI ─n > 0─▶ LOAD_DATA ─byte 4n−1─▶ LOAD_FILL ─imem completa─▶ REPLY ─▶ IDLE
                                │               (4n bytes,                 ▲                     ('K', o 'E'
                                │                de a uno)                 │                      si no entra)
                                └───────────────── n = 0 ──────────────────┘
```

`LOAD_DATA` escribe en la imem solo los bytes que entran (`o_in_range`) y descarta el
resto. `LOAD_FILL` sigue con el mismo contador hasta el final de la imem, escribiendo
`0x00000013` (`addi x0, x0, 0`) byte a byte, y al terminar elige `K` o `E` según el flag
de overflow que se calculó al recibir n.

**Dump** (`D`):

```
IDLE ─'D'─▶ DUMP_CNT_LO ─▶ DUMP_CNT_HI ─n > 0─▶ DUMP_ADDR ─▶ DUMP_LATCH ─▶ DUMP_BYTE ─última palabra─▶ IDLE
            (manda n_lo)   (manda n_hi)             ▲                      (4 bytes)
                                │                   │                          │
                                └─ n = 0 ─▶ IDLE    └── quedan más palabras ───┘
                                                        (dirección + 1)
```

`DUMP_ADDR` mantiene la dirección del bus de debug un ciclo, `DUMP_LATCH` guarda la
palabra y `DUMP_BYTE` manda sus 4 bytes, del menos significativo al más significativo.
El dump no pasa por `REPLY`: los bytes del dump son la respuesta.

**Señales al CPU.** Salen de los registros de modo y del estado:

```verilog
assign o_cpu_enable = (run | step) & ~cpu_halt & ~dumping;   // no avanza mientras se lee
assign o_cpu_reset  = reset | cpu_rst | loading;              // en reset durante toda la carga
```
