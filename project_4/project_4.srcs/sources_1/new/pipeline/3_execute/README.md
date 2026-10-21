# `3_execute/` — etapa EX

**Qué hace:** opera con los dos operandos, evalúa la condición de los branches y
calcula el destino del salto.

```
   fwd_a_val ──┐
   fwd_b_val ──┼──▶ alu ──▶ alu_out, alu_zero, alu_ovf, alu_lt, alu_ltu
   ex_imm    ──┘                    │
                                    └──▶ branch_unit ──▶ branch_taken, branch_target
```

---

## `alu.v` — `alu_tp1`

La ALU. Combinacional, 32 bits.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `i_data_a` | 32 (signed) | operando A (ya reenviado) |
| `i_data_b` | 32 (signed) | operando B (ya reenviado) |
| `i_data_op` | 4 | código de operación (de `alu_ops.vh`) |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `o_data` | 32 | resultado |
| `o_z` | 1 | el resultado es 0 (`zero`) |
| `o_o` | 1 | overflow con signo (solo en ADD/SUB) |
| `o_lt` | 1 | `a < b` con signo |
| `o_ltu` | 1 | `a < b` sin signo |

**Operaciones** (`alu_ops.vh`)

| Código | Op | | Código | Op |
|---|---|---|---|---|
| `0000` | ADD | | `0111` | SLL |
| `0001` | SUB | | `1000` | SRL |
| `0010` | AND | | `1001` | SRA |
| `0011` | OR | | `1010` | NOR |
| `0100` | XOR | | `0101` | SLT |
| `0101` | SLT | | `0110` | SLTU |

**Wires internas**

- `alu_result` — reg de 32 bits con el resultado del `case`.
- `shamt` — `i_data_b[4:0]`: en RV32I los shifts cuentan **solo los 5 bits bajos**
  del segundo operando. Sin esto, `SRAI` (que mete `0100000` en `imm[11:5]`) y los
  shifts por registro con `rs2 > 31` dan mal.
- `o_lt` / `o_ltu` se calculan **siempre**, sin depender de `i_data_op`, porque el
  `branch_unit` los necesita para BLT/BGE/BLTU/BGEU. SLT y SLTU los reutilizan.

**Notes**

- `o_z` se calcula **fuera** del `case`, mirando `alu_result` completo: sirve tanto
  para `branch_unit` (BEQ/BNE) como para el flag `zero` del bus de debug.
- El overflow (`o_o`) solo tiene sentido en ADD y SUB; en el resto queda en 0.

---

## `alu_ops.vh` — header

Solo `localparam` con los códigos de operación de la ALU. Lo incluyen `alu.v` (que
está en esta carpeta) y `control.v` (que está en `2_decode/`): por eso
`add_sources.tcl` agrega `pipeline/3_execute` al `include_dirs` del fileset, y el
archivo se marca como `Verilog Header`.

---

## `branch_unit.v` — `branch_unit`

Evalúa la condición del branch y calcula el destino.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `funct3` | 3 | `instr[14:12]` de la instrucción en EX |
| `zero` | 1 | de la ALU (`rs1 == rs2`) |
| `alu_lt` | 1 | de la ALU (`rs1 < rs2` con signo) |
| `alu_ltu` | 1 | de la ALU (`rs1 < rs2` sin signo) |
| `pc` | 32 | PC de la instrucción |
| `b_imm` | 32 | inmediato B sign-extendido |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `branch_taken` | 1 | la condición se cumple |
| `branch_target` | 32 | `pc + b_imm` |

**Condiciones**

| `funct3` | Branch | Condición |
|---|---|---|
| `000` | BEQ | `zero` |
| `001` | BNE | `~zero` |
| `100` | BLT | `alu_lt` |
| `101` | BGE | `~alu_lt` |
| `110` | BLTU | `alu_ltu` |
| `111` | BGEU | `~alu_ltu` |

**Cómo se conecta**

En `riscv_pipeline`:

```verilog
wire branch_taken = ex_branch & bu_taken;      // el branch Y la condición
assign redirect    = branch_taken | ex_jump;    // branch tomado, JAL o JALR
```

El `redirect_target` se calcula en el pipeline, no acá:

- branch / JAL → `bu_target` (`pc + imm`), el mismo sumador.
- JALR → `(alu_out & ~32'h1)`, es decir `(rs1 + imm)` con el bit 0 en 0.
