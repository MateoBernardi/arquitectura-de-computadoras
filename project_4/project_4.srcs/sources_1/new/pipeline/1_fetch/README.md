# `1_fetch/` — etapa IF

**Qué hace:** calcula la dirección de la siguiente instrucción, la lee de la memoria
de instrucciones y se la pasa a la etapa de decode.

En este diseño el **PC no es un módulo aparte**: está como `reg pc` dentro de
`riscv_pipeline.v`, porque necesita de `stall` y `redirect` para saber si avanza.

```
pc ──▶ imem.instr ──▶ if_id_reg ──▶ id_inst / id_pc
 ▲                                        │
 └── pc_next ◀── redirect ? target : pc+4  │
```

---

## `imem.v` — `imem`

Memoria de instrucciones: 1 KB (`ADDR_W = 10` bytes de dirección → 256 palabras),
**little-endian**.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `clk` | 1 | |
| `addr` | 32 | dirección **en bytes** que viene del PC |
| `wr_en` | 1 | escritura (carga de programa por la debug unit) |
| `wr_addr` | 10 | dirección en bytes |
| `wr_data` | 8 | byte a escribir |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `instr` | 32 | la instrucción (lectura **combinacional**) |

**Internals**

- `mem[0:DEPTH-1]` — la memoria (`DEPTH = 2**(ADDR_W-2)` palabras de 32 bits).
- `wr_word` — `wr_addr[ADDR_W-1:2]`, la palabra que se está escribiendo.
- Al Reset de hardware arranca llena de **NOP** (`32'h0000_0013` = `addi x0,x0,0`).
- `INIT_FILE` (parámetro) carga un `.hex` con `$readmemh` — solo para simulación.

**Notes**

- El puerto de escritura **no está gateado por `i_enable`**: mientras se carga el
  programa el CPU está en reset, así que no hace falta protegerlo.
- La escritura es **byte a byte**: `wr_addr[1:0]` elige el byte dentro de la palabra.
- La lectura es combinacional → la `imem` no tiene latencia, la instrucción está
  disponible en el mismo ciclo.

**Cómo se conecta**

`riscv_pipeline` la instancia como `u_imem` y le pasa `pc` como `addr`. El puerto de
escritura lo maneja la debug unit (`o_imem_write_enable/addr/data`).
