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
