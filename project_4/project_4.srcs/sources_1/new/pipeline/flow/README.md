# `flow/` — control de flujo entre etapas

Acá están los **3 módulos que cruzan etapas**: ninguno pertenece a una sola, porque
cada uno mira señales de dos o tres etapas distintas.

| módulo | qué lee | qué escribe | etapas que toca |
|---|---|---|---|
| `hazard_unit` | `id_rs1/id_rs2` (ID) + `ex_rd`/`ex_mem_read` (EX/MEM) | `stall` | **ID ↔ EX/MEM** |
| `forward_unit` | `ex_rs1/ex_rs2` (EX) + `mem_rd` (MEM) + `wb_rd` (WB) | `forward_a/forward_b` | **EX ↔ MEM ↔ WB** |
| `flush_unit` | `redirect` (sale de EX) | `flush_if_id`, `flush_id_ex` | **EX → IF/ID, ID/EX** |

Los tres son **combinacionales**.

---

## `hazard_unit.v` — `hazard_unit`

Detecta el **conflicto load-use**: un load en EX y la instrucción siguiente en ID
usa el registro que el load va a escribir.

```
lw   x5, 0(x6)      ← en EX, ex_mem_read=1, ex_rd=5
add  x5, x5, x1     ← en ID, id_rs1=5  →  stall
```

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `ex_mem_read` | 1 | ¿la instrucción en EX es un load? |
| `ex_rd` | 5 | destino del load |
| `id_rs1` | 5 | `rs1` de la instrucción en ID |
| `id_rs2` | 5 | `rs2` de la instrucción en ID |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `stall` | 1 | 1 → hay que congelar el pipeline 1 ciclo |

**Regla**

```
stall = ex_mem_read && (ex_rd != 0) && (ex_rd == id_rs1 || ex_rd == id_rs2)
```

**Efecto del stall** (en `riscv_pipeline.v`)

- `flush_id_ex` |= `stall` → se mete una **burbuja** en ID/EX.
- `pc_en = en & ~stall & ~stop_fetch` → el PC **no** avanza.
- `if_id_reg` con `stall=1` → mantiene la instrucción en ID.

Resultado: la instrucción que dependía del load espera 1 ciclo. Como el forwarding
no existe entre ID y EX, esta espera es obligatoria.

> Detecta **solo load-use**. Un conflict RAW entre dos ALU (por ejemplo
> `add x5,x5,x1` seguido de `sub x2,x5,x3`) lo resuelve el forwarding, sin stall.

---

## `forward_unit.v` — `forward_unit`

Detecta el **conflicto RAW** (lectura después de escritura) y decide de qué registro
de pipeline reenviar el valor.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `ex_rs1` | 5 | `rs1` de la instrucción en EX |
| `ex_rs2` | 5 | `rs2` de la instrucción en EX |
| `mem_rd` | 5 | destino de la instrucción en MEM |
| `mem_reg_write` | 1 | esa instrucción escribe un registro |
| `wb_rd` | 5 | destino de la instrucción en WB |
| `wb_reg_write` | 1 | esa instrucción escribe un registro |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `forward_a` | 2 | de dónde sale el operando A |
| `forward_b` | 2 | de dónde sale el operando B |

**Codificación**

| Código | Origen | Antigüedad |
|---|---|---|
| `2'b00` | el regfile (`ex_rdata1`/`ex_rdata2`) | sin conflicto |
| `2'b10` | `mem_result` (EX/MEM) | instrucción de hace 1 |
| `2'b01` | `wb_result` (MEM/WB) | instrucción de hace 2 |

**Prioridad**

EX/MEM tiene **más prioridad** que MEM/WB: si las dos escriben el mismo registro,
el valor más reciente es el de EX/MEM.

```verilog
if (wb_rd == ex_rs1 && !(mem_reg_write && mem_rd == ex_rs1))
    forward_a = 2'b01;
```

**Dónde se aplica** (en `riscv_pipeline.v`)

```verilog
case (forward_a)
    2'b10:   fwd_a_val = mem_result;
    2'b01:   fwd_a_val = wb_result;
    default: fwd_a_val = ex_rdata1;
endcase
```

Y de ahí salen los operandos de la ALU:

```verilog
wire [31:0] alu_a = ex_is_auipc ? ex_pc : fwd_a_val;
wire [31:0] alu_b = ex_alu_src  ? ex_imm : fwd_b_val;
```

---

## `flush_unit.v` — `flush_unit`

Un branch tomado, un JAL o un JALR invalidan las **2 instrucciones que van detrás
del salto** y que ya estaban en el pipeline.

```
        EX (salto tomado)
             │ redirect
             ▼
   ┌─────────────────────┐
   │  IF/ID  → burbuja   │   flush_if_id
   │  ID/EX  → burbuja   │   flush_id_ex
   └─────────────────────┘
```

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `redirect` | 1 | EX: branch tomado, JAL o JALR |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `flush_if_id` | 1 | vaciar el registro IF/ID |
| `flush_id_ex` | 1 | meter una burbuja en ID/EX |

Ambos son simplemente `redirect` (el módulo es un passthrough, pero deja la intención
explícita y el lugar donde agregar lógica extra).

**Consecuencia:** como los saltos se resuelven en EX, **todo salto taken cuesta 2
burbujas**. La idea de `project_3` era resolver el JAL en ID para que cueste 1.

**Efecto en el pipeline** (en `riscv_pipeline.v`)

```verilog
wire stop_fetch = ex_halt | halting;
wire flush_if_id = flush_if_id_r | stop_fetch;
wire flush_id_ex = flush_id_ex_r | stop_fetch | stall;
```

`stop_fetch` hace lo mismo que un flush cuando hay un halt: ninguna instrucción
posterior puede ejecutarse.
