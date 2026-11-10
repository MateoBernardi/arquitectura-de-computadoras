# `pipeline/` — el CPU de 5 etapas

Acá vive el núcleo: `riscv_pipeline.v` es el módulo que une todo y expone
la interfaz con la debug unit.

```
riscv_pipeline.v
├── 1_fetch/     imem.v
├── 2_decode/    control.v, immgen.v, regfile.v
├── 3_execute/   alu.v, alu_ops.vh, branch_unit.v
├── 4_memory/    dmem.v
├── 5_writeback/ (el camino de escritura vive repartido: ver el README)
├── regs/        pipe_reg.v
└── flow/        hazard_unit.v, forward_unit.v, flush_unit.v
```

---

## El diagrama

```
    IF                ID                EX                MEM              WB
 ┌─────────┐     ┌─────────┐      ┌─────────┐      ┌─────────┐     ┌─────────┐
 │  imem   │     │ control │      │  alu    │      │  dmem   │     │ regfile │
 │   PC    │────▶│ immgen  │─────▶│ branch  │─────▶│         │────▶│ (write) │
 │         │     │ regfile │      │ fwd mux │      │         │     │         │
 └─────────┘     └─────────┘      └─────────┘      └─────────┘     └─────────┘
      │                │                │                │                │
      └─ if_id_reg ────┴─ id_ex_reg ────┴─ ex_mem_reg ──┴─ mem_wb_reg ──┘
```

---

## Interfaz con la debug unit

`riscv_pipeline` expone todo lo que la debug unit necesita:

| Puerto | Ancho | Descripción |
|---|---|---|
| `clk` | 1 | reloj del sistema |
| `i_rst` | 1 | reset **sincrónico**: PC=0, pipeline vaciado, x1..x31 en 0. No borra la dmem; la imem se conserva. |
| `i_enable` | 1 | 0 congela todos los elementos de estado (no hay clock gating). |
| `o_halt` | 1 | nivel: 1 cuando una instrucción que detiene el CPU llega a WB: ECALL, EBREAK o un trap. |
| `i_imem_we` | 1 | puerto de escritura de la imem (byte) |
| `i_imem_waddr` | 10 | dirección (bytes) |
| `i_imem_wdata` | 8 | dato |
| `i_dbg_addr` | 16 | dirección del bus de debug |
| `o_dbg_data` | 32 | palabra leída (combinacional) |
| `o_dbg_count` | 16 | cantidad de palabras del mapa de debug |

El `o_halt` es de nivel: cuando vale 1, todo lo anterior ya se retiró, la instrucción
que lo provocó no escribió nada, y ninguna instrucción posterior llegó a ejecutarse.

---

## Excepciones (fatal traps)

El CPU implementa RV32I **sin la arquitectura privilegiada** (no hay CSRs). La spec no
privilegiada permite que toda excepción sea un *fatal trap*: el entorno de ejecución, en
este caso la debug unit, detiene la ejecución. Las causas usan los códigos estándar de
`mcause`, y la debug unit las lee en las palabras 86–88 del mapa de debug.

| Código | Causa | Se detecta en |
|---|---|---|
| 0 | salto o branch tomado a una dirección no alineada a 4 (el trap es **del salto**) | EX (`trap_unit`) |
| 1 | instrucción fuera de la imem | ID (`id_pc`) |
| 2 | instrucción ilegal: todo lo que no es RV32I, incluidas `csr*`, `fence.i`, `mret`, `wfi` | ID (`illegal_check`) |
| 3 | `ebreak` | ID |
| 4 / 6 | load / store desalineado | EX (`trap_unit`) |
| 5 / 7 | load / store fuera de la dmem | EX (`trap_unit`) |
| 11 | `ecall` | ID |

Las causas de ID viajan con la instrucción (`id_ex_reg.cause`) y recién actúan en EX, igual
que el halt de antes. Así, una instrucción del camino equivocado (detrás de un salto
tomado) se descarta sin generar un trap. Cuando la instrucción de EX detiene el CPU
(`ex_stop`):

- no escribe registros ni memoria (`reg_write`, `mem_read` y `mem_write` se anulan);
- `stop_fetch` congela el PC y vacía IF/ID e ID/EX: nada más joven se ejecuta;
- llega a WB con `halt = 1`, y ahí `o_halt` detiene el CPU.

---

## Señales internas que vale la pena mirar

| Wire | Origen | Significado |
|---|---|---|
| `stall` | `hazard_unit` | load-use detectado: hay que congelar el pipeline 1 ciclo |
| `redirect` | EX | un branch tomado, JAL o JALR cambió el PC |
| `ex_stop` | EX | la instrucción de EX detiene el CPU: `ex_halt` (ecall/ebreak/ilegal/fuera de la imem) o `ex_exc` (`trap_unit`) |
| `halting` | registro `halting_r` | pegajoso: 1 desde que `ex_stop` vale 1 hasta el reset |
| `stop_fetch` | `ex_stop` + halting | ninguna instrucción posterior puede ejecutarse |
| `trap_cause` / `trap_pc` / `trap_tval` | registros | por qué se detuvo el CPU (palabras 86–88 del mapa de debug) |
| `flush_if_id` | `flush_unit` + stop_fetch | hay que vaciar IF/ID (instrucción del camino equivocado) |
| `flush_id_ex` | `flush_unit` + stop_fetch + stall | hay que meter una burbuja en ID/EX |
| `fwd_a_val` / `fwd_b_val` | mux de forwarding | operandos ya reenviados |
| `mem_result` | mux `wb_sel` | valor que produce la instrucción (también se reenvía desde aquí) |
| `redirect_target` | EX | destino del salto: `pc + imm` (branch/JAL) o `(rs1 + imm) & ~1` (JALR) |
| `pc_next` | EX | `redirect ? redirect_target : pc + 4` |

---

## El bus de debug

Mapa de 89 palabras de 32 bits. La debug unit pide una por una con `i_dbg_addr`;
`o_dbg_count` dice cuántas hay.

| Dir | Contenido | Nota |
|---|---|---|
| 0 | `pc` | |
| 1 | `id_pc` | |
| 2 | `id_inst` | |
| 3 | control de ID/EX | `[0]reg_write [1]mem_read [2]mem_write [3]branch [4]jump [5]is_jalr [6]is_auipc [7]halt [8]alu_src [10:9]wb_sel [14:11]alu_op` |
| 4 | campos de ID/EX | `[4:0]rs1 [9:5]rs2 [14:10]rd [17:15]funct3` |
| 5 | `ex_pc` | |
| 6 | `ex_rdata1` | |
| 7 | `ex_rdata2` | |
| 8 | `ex_imm` | |
| 9 | `alu_a` | después del forwarding |
| 10 | `alu_b` | después del forwarding |
| 11 | `alu_out` | |
| 12 | `redirect_target` | |
| 13 | flags de EX | `[0]stall [1]flush_if_id [2]flush_id_ex [3]redirect [4]branch_taken [5]zero [6]overflow [7]halting [9:8]forward_a [11:10]forward_b` |
| 14 | control de EX/MEM | `[0]reg_write [1]mem_read [2]mem_write [3]halt [5:4]wb_sel` |
| 15 | `mem_alu_out` | |
| 16 | `mem_rdata2` | dato a escribir |
| 17 | campos de EX/MEM | `[4:0]rd [7:5]funct3` |
| 18 | `mem_rdata` | dato leído de la dmem |
| 19 | control de MEM/WB | `[0]reg_write [1]halt` |
| 20 | `wb_result` | valor final |
| 21 | `wb_rd` | `[4:0]` |
| 22–53 | x0..x31 | `dbg_reg_idx` |
| 54–85 | 32 palabras de dmem | `dbg_dmem_idx` |
| 86 | causa del trap | código de la tabla de excepciones; válido con `o_halt = 1` |
| 87 | PC del trap | la instrucción que detuvo el CPU |
| 88 | valor del trap | la dirección que falló (causas 0, 1, 4–7); 0 en las demás |

> `DBG_REGS = 22`, `DBG_DMEM = 22 + 32 = 54`, `DBG_TRAP = 54 + 32 = 86`, `DBG_COUNT = 89`.
> Si se agrega una palabra al mapa, va **siempre al final** y hay que extender
> `decode_dump()` en `host/debug_protocol.py`.

---

## Reglas de reset y enable

Las tres son iguales en todo el pipeline:

- **rst** — reset sincrónico: vacía la etapa (NOP / burbuja).
- **en** — si vale 0, el CPU está pausado por la debug unit: los registros
  **mantienen su valor** y se ignoran `flush` y `stall` mientras está pausado.
- **halt** — viaja con la instrucción hasta WB, donde frena el CPU. Marca a una
  instrucción que detiene la ejecución (ecall, ebreak o un trap).

