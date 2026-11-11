# `regs/` — los registros de pipeline

Los 4 registros que separan las etapas. Cada uno guarda, en el flanco, la instrucción que
sale de una etapa con todo lo que ya se calculó de ella, y se lo entrega a la siguiente.
Están juntos en `pipe_reg.v` para ver de un vistazo qué cruza cada frontera.

```
 IF ──▶ if_id_reg ──▶ ID ──▶ id_ex_reg ──▶ EX ──▶ ex_mem_reg ──▶ MEM ──▶ mem_wb_reg ──▶ WB
```

Las reglas son las mismas en los 4:
- `rst`: reset sincrónico; la etapa queda vacía (una NOP en IF/ID, todo en cero en el resto).
- `en`: con 0 (CPU pausado) el registro mantiene su valor; se ignoran `stall` y `flush`.

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

## `if_id_reg` — IF → ID

```
              ┌──────────────────────┐
clk      1 ──▶│                      │──▶ id_pc   32  R
rst      1 ──▶│                      │──▶ id_inst 32  R
en       1 ──▶│      if_id_reg       │
stall    1 ──▶│     [secuencial]     │
flush    1 ──▶│                      │
if_pc   32 ──▶│                      │
if_inst 32 ──▶│                      │
              └──────────────────────┘
```

- `stall` (load-use): mantiene la instrucción en ID un ciclo más.
- `flush` (salto tomado o CPU deteniéndose): la reemplaza por una NOP.

## `id_ex_reg` — ID → EX

El más grande: lleva las señales de control, los operandos, el inmediato y los campos de
la instrucción.

```
                   ┌──────────────────────┐
clk           1 ──▶│                      │──▶ ex_reg_write  1  R
rst           1 ──▶│                      │──▶ ex_alu_src    1  R
en            1 ──▶│                      │──▶ ex_mem_read   1  R
flush         1 ──▶│                      │──▶ ex_mem_write  1  R
id_reg_write  1 ──▶│                      │──▶ ex_branch     1  R
id_alu_src    1 ──▶│                      │──▶ ex_jump       1  R
id_mem_read   1 ──▶│                      │──▶ ex_is_jalr    1  R
id_mem_write  1 ──▶│                      │──▶ ex_is_auipc   1  R
id_branch     1 ──▶│                      │──▶ ex_halt       1  R
id_jump       1 ──▶│                      │──▶ ex_wb_sel     2  R
id_is_jalr    1 ──▶│                      │──▶ ex_alu_op     4  R
id_is_auipc   1 ──▶│      id_ex_reg       │──▶ ex_pc        32  R
id_halt       1 ──▶│     [secuencial]     │──▶ ex_pc4       32  R
id_wb_sel     2 ──▶│                      │──▶ ex_rdata1    32  R
id_alu_op     4 ──▶│                      │──▶ ex_rdata2    32  R
id_pc        32 ──▶│                      │──▶ ex_imm       32  R
id_pc4       32 ──▶│                      │──▶ ex_rs1        5  R
id_rdata1    32 ──▶│                      │──▶ ex_rs2        5  R
id_rdata2    32 ──▶│                      │──▶ ex_rd         5  R
id_imm       32 ──▶│                      │──▶ ex_funct3     3  R
id_rs1        5 ──▶│                      │──▶ ex_cause      4  R
id_rs2        5 ──▶│                      │
id_rd         5 ──▶│                      │
id_funct3     3 ──▶│                      │
id_cause      4 ──▶│                      │
                   └──────────────────────┘
```

- `flush` mete una burbuja (una instrucción que no hace nada): por un salto tomado, por un
  stall de load-use o porque el CPU se está deteniendo.
- `id_cause` es el código de excepción que detectó ID (ilegal, `ecall`, `ebreak`, fuera de
  la imem); recién actúa cuando la instrucción llega a EX.

## `ex_mem_reg` — EX → MEM

```
                   ┌──────────────────────┐
clk           1 ──▶│                      │──▶ mem_reg_write  1  R
rst           1 ──▶│                      │──▶ mem_mem_read   1  R
en            1 ──▶│                      │──▶ mem_mem_write  1  R
ex_reg_write  1 ──▶│                      │──▶ mem_halt       1  R
ex_mem_read   1 ──▶│                      │──▶ mem_wb_sel     2  R
ex_mem_write  1 ──▶│                      │──▶ mem_alu_out   32  R
ex_halt       1 ──▶│      ex_mem_reg      │──▶ mem_rdata2    32  R
ex_wb_sel     2 ──▶│     [secuencial]     │──▶ mem_pc4       32  R
ex_alu_out   32 ──▶│                      │──▶ mem_imm       32  R
ex_rdata2    32 ──▶│                      │──▶ mem_rd         5  R
ex_pc4       32 ──▶│                      │──▶ mem_funct3     3  R
ex_imm       32 ──▶│                      │
ex_rd         5 ──▶│                      │
ex_funct3     3 ──▶│                      │
                   └──────────────────────┘
```

`ex_rdata2` (después del forwarding) es el dato de un store; `ex_pc4` e `ex_imm`, los
valores que JAL/JALR y LUI escriben en WB.

## `mem_wb_reg` — MEM → WB

```
                    ┌──────────────────────┐
clk            1 ──▶│                      │──▶ wb_reg_write  1  R
rst            1 ──▶│                      │──▶ wb_halt       1  R
en             1 ──▶│      mem_wb_reg      │──▶ wb_result    32  R
mem_reg_write  1 ──▶│     [secuencial]     │──▶ wb_rd         5  R
mem_halt       1 ──▶│                      │
mem_result    32 ──▶│                      │
mem_rd         5 ──▶│                      │
                    └──────────────────────┘
```

`mem_result` ya es el valor final elegido por `wb_sel` (ver [`5_writeback/`](../5_writeback/README.md)).
`wb_halt` es la salida `o_halt` del CPU.
