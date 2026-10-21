# `regs/` — los registros de pipeline

Un solo archivo, `pipe_reg.v`, con los **4 registros que separan las etapas**.
Se dejó entero a propósito: los 4 comparten las mismas convenciones y verlos juntos
ayuda a entender qué señal viaja por cada frontera.

```
  IF ──▶ if_id_reg ──▶ ID ──▶ id_ex_reg ──▶ EX ──▶ ex_mem_reg ──▶ MEM ──▶ mem_wb_reg ──▶ WB
```

---

## Convenciones (las mismas en los 4)

- **`rst`** — reset **sincrónico**: vacía la etapa (NOP / burbuja / todo en 0).
- **`en`** — 0 = el CPU está pausado por la debug unit: el registro **mantiene su
  valor** y se ignoran `flush` y `stall` mientras está pausado. No hay clock gating.
- **`halt`** — viaja con la instrucción hasta WB, donde frena el CPU.

---

## `if_id_reg` — frontera IF/ID

Guarda la instrucción que acaba de salir de la `imem`.

**Entradas:** `clk`, `rst`, `en`, `stall`, `flush`, `if_pc`, `if_inst`
**Salidas:** `id_pc`, `id_inst`

| Entrada | Efecto |
|---|---|
| `rst` | `id_pc = 0`, `id_inst = NOP` |
| `flush` | `id_pc = 0`, `id_inst = NOP` (instrucción del camino equivocado) |
| `stall` | mantiene el valor |

> Con `flush` también se pone `id_pc = 0`: la instrucción descartada nunca se ejecutó,
> así que su PC no importa.

---

## `id_ex_reg` — frontera ID/EX

El más grande: lleva **todo** lo que calculó la etapa ID.

**Control:** `id_reg_write`, `id_alu_src`, `id_mem_read`, `id_mem_write`,
`id_branch`, `id_jump`, `id_is_jalr`, `id_is_auipc`, `id_halt`, `id_wb_sel[1:0]`,
`id_alu_op[3:0]`

**Datos:** `id_pc`, `id_pc4`, `id_rdata1`, `id_rdata2`, `id_imm`, `id_rs1[4:0]`,
`id_rs2[4:0]`, `id_rd[4:0]`, `id_funct3[2:0]`

**Salidas:** los mismos, con prefijo `ex_`.

**Flush:** en esta frontera el flush mete una **burbuja** (todos los controles en 0 y
los datos en 0). Es lo que hace que un salto descartado no escriba ningún registro
ni acceda a la memoria.

```verilog
if (rst || (en && flush)) begin
    ex_reg_write <= 0; ... ex_funct3 <= 0;   // burbuja
end else if (en) begin
    ...
end
```

> `stall` no aparece acá: el stall congela el IF/ID, y la burbuja en ID/EX la mete
> el pipeline con `flush_id_ex = ... | stall`.

---

## `ex_mem_reg` — frontera EX/MEM

**Control:** `ex_reg_write`, `ex_mem_read`, `ex_mem_write`, `ex_halt`, `ex_wb_sel[1:0]`
**Datos:** `ex_alu_out`, `ex_rdata2`, `ex_pc4`, `ex_imm`, `ex_rd[4:0]`, `ex_funct3[2:0]`

**Salidas:** los mismos, con prefijo `mem_`.

Aquí ya no hace falta el flush: cuando hay un flush, la instrucción de EX es la
burbuja que puso `id_ex_reg`, y lo que llega acá ya está limpio.

---

## `mem_wb_reg` — frontera MEM/WB

El último. Guarda el **valor final** y el destino.

**Entradas:** `mem_reg_write`, `mem_halt`, `mem_result`, `mem_rd`
**Salidas:** `wb_reg_write`, `wb_halt`, `wb_result`, `wb_rd`

---

## Resumen

| Registro | Campos | Reset |
|---|---|---|
| `if_id_reg` | `pc`, `inst` | `pc=0`, `inst=NOP` |
| `id_ex_reg` | control + datos | burbuja (todo en 0) |
| `ex_mem_reg` | control + datos | todo en 0 |
| `mem_wb_reg` | `reg_write`, `halt`, `result`, `rd` | todo en 0 |

**Nota:** ninguno de los 4 tiene un enable propio para "no escribir". El `en` global
es el que congela todo, y el `stall`/`flush` se manejan con muxing en la entrada.
