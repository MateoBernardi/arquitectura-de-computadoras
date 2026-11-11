# `2_decode/` — etapa ID

Convierte la instrucción en todo lo que necesitan las etapas siguientes: las señales de
control, el inmediato y los dos operandos. También decide si la instrucción es legal.
Todo eso entra en el registro ID/EX.

```
            ┌──▶ control ──────▶ señales de control ─┐
 instrucción├──▶ immgen ───────▶ inmediato ──────────┼──▶ ID/EX
 (de IF/ID) ├──▶ regfile ──────▶ rdata1, rdata2 ─────┤
            └──▶ illegal_check ▶ ilegal / ecall / ebreak ──▶ causa del trap
```

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

## `control` — señales de control

Mira el opcode, `funct3` y `funct7`, y genera las señales que dicen qué hace la
instrucción en cada etapa siguiente. Viajan con ella por los registros de pipeline.

```
            ┌──────────────────────┐
opcode 7 ──▶│                      │──▶ reg_write 1  C
funct3 3 ──▶│                      │──▶ alu_src   1  C
funct7 7 ──▶│                      │──▶ mem_read  1  C
            │                      │──▶ mem_write 1  C
            │       control        │──▶ branch    1  C
            │   [combinacional]    │──▶ jump      1  C
            │                      │──▶ halt      1  C
            │                      │──▶ wb_sel    2  C
            │                      │──▶ alu_op    4  C
            │                      │──▶ imm_sel   3  C
            └──────────────────────┘
```

| Salida | Para quién | Qué decide |
|---|---|---|
| `alu_op`, `alu_src` | EX | qué operación hace la ALU y si el segundo operando es el inmediato |
| `branch`, `jump` | EX | si la instrucción puede cambiar el PC |
| `mem_read`, `mem_write` | MEM | load o store |
| `reg_write`, `wb_sel` | WB | si escribe un registro y con qué valor (ver [`5_writeback/`](../5_writeback/README.md)) |
| `imm_sel` | `immgen` | el formato del inmediato: I, S, B, U o J |
| `halt` | EX | instrucción `SYSTEM`: detiene el CPU (cuál es, y si es legal, lo dice `illegal_check`) |

## `illegal_check` — ¿es RV32I?

Decide si la instrucción es una de las 40 codificaciones de RV32I. Mira la instrucción
entera, porque `ecall` y `ebreak` tienen una única codificación válida.

```
            ┌──────────────────────┐
instr 32 ──▶│                      │──▶ illegal 1  C
            │    illegal_check     │──▶ ecall   1  C
            │   [combinacional]    │──▶ ebreak  1  C
            │                      │
            └──────────────────────┘
```

Es ilegal todo lo que no es RV32I: las instrucciones de otras extensiones (`csr*` de
Zicsr, `fence.i` de Zifencei, `mul` de M…), las privilegiadas (`mret`, `wfi`), las
comprimidas y cualquier combinación de campos que el estándar no define. Se verifica en
forma exhaustiva contra la tabla oficial de codificaciones (`verif/formal/datapath`).

Una instrucción ilegal, `ecall`, `ebreak` o traída desde fuera de la imem entra a ID/EX
**sin** ningún efecto (no escribe, no salta, no accede a memoria), con `halt` y su causa.

## `immgen` — el inmediato

Arma el inmediato de 32 bits con signo a partir de los campos de la instrucción, según el
formato que le indica `control`.

```
              ┌──────────────────────┐
instr   32 ──▶│                      │──▶ imm 32  C
imm_sel  3 ──▶│        immgen        │
              │   [combinacional]    │
              │                      │
              └──────────────────────┘
```

## `regfile` — banco de registros

Los 32 registros de 32 bits. ID lee dos (`rs1` y `rs2`) y WB escribe uno, en el mismo ciclo.

```
               ┌───────────────────────────────────┐
clk       1 ──▶│                                   │──▶ rdata1   32  C
rst       1 ──▶│                                   │──▶ rdata2   32  C
we        1 ──▶│              regfile              │──▶ dbg_data 32  C
waddr     5 ──▶│              [mixto]              │
wdata    32 ──▶│  lee comb., escribe en el flanco  │
raddr1    5 ──▶│                                   │
raddr2    5 ──▶│                                   │
dbg_addr  5 ──▶│                                   │
               └───────────────────────────────────┘
```

- **x0 vale siempre 0**: escribirlo no tiene efecto y leerlo da 0.
- **Lectura y escritura en el mismo ciclo** (`BYPASS = 1`): si WB escribe el registro que
  ID está leyendo, la lectura devuelve el valor nuevo. Sin esto, ID leería el valor viejo y
  haría falta un forwarding más.
- **El reset borra x1..x31** en un ciclo. Por eso Vivado lo arma con flip-flops y no con
  RAM, que no se puede borrar entera de una vez.
- `dbg_addr` / `dbg_data` es un tercer puerto de lectura, para el bus de debug.

| Parámetro | En el pipeline | Para qué |
|---|---|---|
| `BYPASS` | 1 | lectura del valor que se escribe en el mismo ciclo |
