# `debug/` — debug unit

Es la que hace que se pueda depurar el CPU desde la PC. Habla con el host por UART
y con el CPU por un **bus de debug** (lectura de un mapa de registros internos).

```
   UART  ──▶ debug_unit ──▶ o_cpu_enable / o_cpu_reset / o_halt
                            └──▶ bus de debug ──▶ riscv_pipeline
```

Está partida en 3 módulos, como el UART: FSM (lógica) + combinacional (datapath) +
registros (estado).

---

## `debug_unit.v` — `debug_unit`

El módulo que junta todo.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `i_clk` | 1 | |
| `i_reset` | 1 | reset del sistema |
| `i_data_to_read` | 8 | byte recibido de la UART |
| `i_fifo_rx_empty` | 1 | no hay nada para leer en la UART |
| `i_fifo_tx_full` | 1 | la UART no puede recibir más |
| `i_cpu_halt` | 1 | el CPU llegó a un halt |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `o_fifo_rx_read` | 1 | pide un byte a la UART |
| `o_fifo_tx_write` | 1 | escribe un byte en la UART |
| `o_data_to_write` | 8 | byte a enviar |
| `o_cpu_enable` | 1 | habilita (o pausa) el CPU |
| `o_cpu_reset` | 1 | reset del CPU |
| `o_imem_write_enable` | 1 | escritura en la imem (carga de programa) |
| `o_imem_write_addr` | 8 | dirección en bytes |
| `o_imem_write_data` | 8 | byte |
| `o_dbg_addr` | 16 | dirección del bus de debug |
| `i_dbg_data` | 32 | palabra leída |
| `i_dbg_count` | 16 | cantidad de palabras del mapa |

---

## El protocolo

Un byte de comando por UART. Cada comando tiene una respuesta.

| Byte | Comando | Respuesta | Qué hace |
|---|---|---|---|
| `L` | load | `K` / `E` | carga de programa: `n_lo`, `n_hi` y después `4n` bytes little-endian |
| `S` | step | `K` / `H` | avanza **un ciclo** |
| `R` | run | `K` / `H` | ejecución continua |
| `P` | pause | `K` | pausa |
| `X` | reset | `K` | reset del CPU |
| `D` | dump | — | `count_lo`, `count_hi` y después `count` palabras de 32 bits little-endian |
| otro | — | `?` | comando desconocido |

`H` (halt) también llega **espontáneo**: si el CPU llega a un ECALL/EBREAK mientras
está en modo `R`, la debug unit responde `H` sola.

El `count` del dump lo define el CPU (`i_dbg_count`): son las 86 palabras del mapa
de debug (ver [`../pipeline/README.md`](../pipeline/README.md)).

---

## El bus de debug

`o_dbg_addr` **se mantiene un ciclo antes** de muestrear `i_dbg_data`. Así el mismo
cable sirve tanto para fuentes combinacionales (el mapa del CPU) como para fuentes
con un ciclo de latencia (por ejemplo una BRAM de memoria de datos).

`o_dbg_addr` se incrementa con cada palabra del dump, y el estado `DUMP_LATCH`
justamente sirve para esperar ese ciclo de latencia.

---

## `debug_unit_fsm.v` — `debug_unit_fsm`

La lógica del protocolo: decodifica el comando, decide el próximo estado, las
respuestas y las señales de control del datapath y del CPU.

**Comandos y respuestas** (localparams)

```verilog
CMD_LOAD  = 8'h4C;  // 'L'      RSP_OK   = 8'h4B;  // 'K'
CMD_STEP  = 8'h53;  // 'S'      RSP_ERR  = 8'h45;  // 'E'
CMD_RUN   = 8'h52;  // 'R'      RSP_HALT = 8'h48;  // 'H'
CMD_PAUSE = 8'h50;  // 'P'      RSP_UNK  = 8'h3F;  // '?'
CMD_RESET = 8'h58;  // 'X'
CMD_DUMP  = 8'h44;  // 'D'
```

**Estados**

| Estado | Qué hace |
|---|---|
| `IDLE` (0) | espera un comando |
| `LOAD_LEN_LO` | recibe el byte bajo de la longitud |
| `LOAD_LEN_HI` | recibe el byte alto de la longitud |
| `LOAD_DATA` | recibe los bytes del programa |
| `LOAD_FILL` | el programa quedó más corto que la longitud: rellena con NOP |
| `REPLY` | manda la respuesta y vuelve a `IDLE` |
| `DUMP_CNT_LO` | recibe el byte bajo de la cantidad de palabras |
| `DUMP_CNT_HI` | recibe el byte alto |
| `DUMP_ADDR` | pide una palabra del bus de debug |
| `DUMP_LATCH` | espera el ciclo de latencia del bus |
| `DUMP_BYTE` | manda los 4 bytes de la palabra (little-endian) |

**Salidas de control del CPU**

| Puerto | Efecto |
|---|---|
| `o_cpu_enable` | 1 = el CPU avanza; 0 = pausado |
| `o_cpu_reset` | 1 = reset del CPU (reset del sistema, carga o comando `X`) |
| `o_run_next` / `o_step_next` | modos: correr / un paso |

---

## `debug_unit_comb.v` — `debug_unit_comb`

El datapath combinacional: los próximos valores de los registros de datos según los
controles de la FSM, el byte que se manda por TX, y los flags que la FSM usa para
decidir.

**Flags que devuelve**

| Flag | Significado |
|---|---|
| `o_len_zero` | la longitud que llega es 0 |
| `o_load_last` | último byte del programa |
| `o_in_range` | el contador de bytes está dentro de la imem |
| `o_dbg_count_zero` | la cantidad de palabras del dump es 0 |
| `o_dbg_last` | última palabra del dump |
| `o_byte_last` | último byte de la palabra |

**Registros que maneja**

`i_len` (16 bits, longitud del programa), `i_byte_cnt` (18 bits, contador de bytes),
`i_overflow`, `i_reply` (8 bits, la respuesta a mandar), `i_imem_addr`,
`i_imem_data`, `i_dbg_addr`, `i_dbg_word`, `i_byte_idx` (2 bits, byte dentro de la
palabra del dump).

---

## `debug_unit_regs.v` — `debug_unit_regs`

Los registros: estado de la FSM (`o_state`, 4 bits), los modos (`o_run`, `o_step`,
`o_cpu_rst`) y los registros del datapath.

Reset sincrónico activo en alto; **todo** vuelve a 0 (`IDLE = 0`).

**Registros**

| Registro | Ancho | Para qué |
|---|---|---|
| `o_state` | 4 | estado de la FSM |
| `o_run` | 1 | modo corrida continua |
| `o_step` | 1 | modo un paso |
| `o_cpu_rst` | 1 | pulso de reset del CPU |
| `o_len` | 16 | longitud del programa a cargar |
| `o_byte_cnt` | 18 | cuántos bytes se recibieron |
| `o_overflow` | 1 | el programa no entra en la imem |
| `o_reply` | 8 | respuesta a enviar |
| `o_imem_we` | 1 | habilita la escritura en la imem |
| `o_imem_addr` | 8 | dirección |
| `o_imem_data` | 8 | byte |
| `o_dbg_addr` | 16 | dirección del bus de debug |
| `o_dbg_word` | 32 | palabra leída |
| `o_byte_idx` | 2 | byte dentro de la palabra, para mandarlos little-endian |

---

## Del lado del host

El cliente del protocolo está en `host/debug_protocol.py`; la decodificación del dump
en `decode_dump()`. Si se agrega una palabra al mapa de debug, va **siempre al
final** y hay que extender `decode_dump()`.
