# `2_decode/` — etapa ID

**Qué hace:** toma la instrucción y la convierte en (a) las señales de control del
datapath, (b) el inmediato y (c) los dos operandos leídos del banco de registros.

```
id_inst ──▶ control ──▶ reg_write, alu_src, mem_read/write, branch, jump, halt,
             │             wb_sel, alu_op, imm_sel
             ├──▶ immgen ──▶ imm
             └──▶ regfile ──▶ rdata1, rdata2
```

---

## `control.v` — `control`

Decodifica `opcode` / `funct3` / `funct7` y genera todas las señales de control.
Es **combinacional**, no tiene registros.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `opcode` | 7 | `instr[6:0]` |
| `funct3` | 3 | `instr[14:12]` |
| `funct7` | 7 | `instr[31:25]` |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `reg_write` | 1 | la instrucción escribe en el regfile |
| `alu_src` | 1 | el operando B de la ALU es el inmediato (si no, es rs2) |
| `mem_read` | 1 | es un load |
| `mem_write` | 1 | es un store |
| `branch` | 1 | es un branch condicional |
| `jump` | 1 | es JAL o JALR |
| `halt` | 1 | ECALL / EBREAK (cualquier `SYSTEM`) → frena el CPU |
| `wb_sel` | 2 | qué valor se escribe: `00`=ALU, `01`=MEM, `10`=PC+4, `11`=Uimm |
| `alu_op` | 4 | código de operación de la ALU (ver `alu_ops.vh`) |
| `imm_sel` | 3 | formato del inmediato: `000`=I, `001`=S, `010`=B, `011`=U, `100`=J |

**Decodificación por opcode**

| `opcode` | Tipo | Notas |
|---|---|---|
| `0110011` | R | `alu_op` según `{funct7[5], funct3}` |
| `0010011` | I (ALU) | `alu_src=1`, inmediato I |
| `0000011` | Load | `mem_read=1`, `wb_sel=01` |
| `0100011` | Store | `mem_write=1`, inmediato S |
| `1100011` | Branch | `branch=1`, inmediato B; `alu_op` = SUB o SLT/SLTU según `funct3` |
| `1101111` | JAL | `jump=1`, `wb_sel=10` (PC+4), inmediato J |
| `1100111` | JALR | `jump=1`, `alu_src=1`, `wb_sel=10` |
| `0110111` | LUI | `wb_sel=11` (el inmediato U sin shift) |
| `0010111` | AUIPC | `alu_src=1`, `alu_op=ADD` (PC + imm) |
| `1110011` | SYSTEM | `halt=1` |

> `alu_ops.vh` vive en `3_execute/`, pero `control.v` lo incluye igual para tener
> los mismos códigos de operación.

---

## `immgen.v` — `immgen`

Extrae y sign-extiende el inmediato según el formato.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `instr` | 32 | la instrucción completa |
| `imm_sel` | 3 | formato, viene de `control` |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `imm` | 32 | inmediato sign-extendido a 32 bits |

**Formatos**

| `imm_sel` | Formato | Bits del inmediato |
|---|---|---|
| `000` | I | `instr[31:20]` |
| `001` | S | `instr[31:25]`, `instr[11:7]` |
| `010` | B | `instr[31]`, `instr[7]`, `instr[30:25]`, `instr[11:8]`, `1'b0` |
| `011` | U | `instr[31:12]`, `12'b0` |
| `100` | J | `instr[31]`, `instr[19:12]`, `instr[20]`, `instr[30:21]`, `1'b0` |

Los formatos B y JUv el bit 0 en 0 porque las direcciones son pares.

---

## `regfile.v` — `regfile`

Banco de 32 registros de 32 bits. Escritura **sincrónica**, lectura **asincrónica**.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `clk` | 1 | |
| `rst` | 1 | reset sincrónico: pone x1..x31 en 0 |
| `we` | 1 | habilita la escritura |
| `waddr` | 5 | registro destino (`rd`) |
| `wdata` | 32 | dato a escribir |
| `raddr1` | 5 | `rs1` |
| `raddr2` | 5 | `rs2` |
| `dbg_addr` | 5 | puerto de lectura del debug unit |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `rdata1` | 32 | dato de `rs1` |
| `rdata2` | 32 | dato de `rs2` |
| `dbg_data` | 32 | `regs[dbg_addr]` |

**Parámetro `BYPASS`**

- `BYPASS = 1` (lo que usa el pipeline): si en el **mismo ciclo** se está escribiendo
  `waddr`, la lectura de ese registro devuelve `wdata` en vez del valor viejo.
  Es el **write-through interno**: sin él, el WB escribiría un registro y el ID
  siguiente leería el valor anterior.
- `BYPASS = 0` (CPU single-cycle): no hace falta y formaría un lazo combinacional.

**Internals**

- `regs[0:31]` — los 32 registros. Arrancan todos en 0 (`initial`).
- `wr` — `we && (waddr != 0)`.
- **x0 siempre vale 0**: la escritura con `waddr == 0` se ignora y la lectura de x0
  devuelve 0 por hardware (no depende del contenido de `regs[0]`).
