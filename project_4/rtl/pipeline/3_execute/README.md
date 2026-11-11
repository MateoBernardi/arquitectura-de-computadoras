# `3_execute/` — etapa EX

Hace el cálculo de la instrucción y resuelve los saltos. Es la etapa donde se juntan más
cosas: los operandos llegan después del forwarding, la ALU calcula, `branch_unit` decide
si el salto se toma y `trap_unit` (en [`flow/`](../flow/README.md)) mira si el salto o el
acceso a memoria provocan una excepción.

```
 ID/EX ──▶ forwarding ──▶ operandos A, B ──▶ alu ──▶ resultado ──────────────▶ EX/MEM
           (de MEM, WB)                       │
                                              └──▶ comparaciones ──▶ branch_unit ──▶ ¿salto tomado?, destino
```

- El **operando A** es `rs1` (o el PC, en AUIPC); el **B** es `rs2` o el inmediato.
- El **destino del salto** es PC + inmediato (branch, JAL) o `rs1` + inmediato con el
  bit 0 en cero (JALR). Si el salto se toma, el pipeline descarta las 2 instrucciones que
  entraron detrás (`flush_unit`).

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

## `alu_tp1` — la ALU

```
                ┌──────────────────────┐
i_data_a  32 ──▶│                      │──▶ o_data 32  C
i_data_b  32 ──▶│       alu_tp1        │──▶ o_z     1  C
i_data_op  4 ──▶│   [combinacional]    │──▶ o_o     1  C
                │                      │──▶ o_lt    1  C
                │                      │──▶ o_ltu   1  C
                └──────────────────────┘
```

| Código | Operación | | Código | Operación |
|---|---|---|---|---|
| `0000` | ADD | | `0110` | SLTU |
| `0001` | SUB | | `0111` | SLL |
| `0010` | AND | | `1000` | SRL |
| `0011` | OR | | `1001` | SRA |
| `0100` | XOR | | `1010` | NOR |
| `0101` | SLT | | | |

Los códigos están en `alu_ops.vh`, que también incluye `control` (por eso la síntesis
agrega esta carpeta al include path). Los desplazamientos usan los 5 bits bajos del
segundo operando, como pide RV32I.

Además del resultado, la ALU da las comparaciones que necesita `branch_unit`: `o_z`
(iguales), `o_lt` (menor con signo) y `o_ltu` (menor sin signo); se calculan siempre,
sea cual sea la operación. `o_o` es el overflow con signo de ADD y SUB (solo para el bus
de debug: RV32I no tiene excepciones aritméticas).

## `branch_unit` — los branches

Decide si un branch se toma, con las comparaciones de la ALU, y calcula su destino.

```
              ┌──────────────────────┐
funct3   3 ──▶│                      │──▶ branch_taken   1  C
zero     1 ──▶│                      │──▶ branch_target 32  C
alu_lt   1 ──▶│     branch_unit      │
alu_ltu  1 ──▶│   [combinacional]    │
pc      32 ──▶│                      │
b_imm   32 ──▶│                      │
              └──────────────────────┘
```

| Branch | Se toma si |
|---|---|
| BEQ / BNE | `rs1 = rs2` / `rs1 ≠ rs2` |
| BLT / BGE | `rs1 < rs2` / `rs1 ≥ rs2`, con signo |
| BLTU / BGEU | lo mismo, sin signo |

`branch_target` = PC + inmediato; el pipeline lo usa también para JAL.
