# `pipeline/` — el CPU RV32I de 5 etapas

`riscv_pipeline` es el procesador: ejecuta RV32I en un pipeline de 5 etapas (IF, ID, EX,
MEM, WB) y le expone a la debug unit lo justo para controlarlo y observarlo. No sabe nada
de la UART ni de la placa: recibe un reloj, un reset y un enable, y avisa cuándo se detuvo.

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

```
                   ┌──────────────────────┐
clk           1 ──▶│                      │──▶ o_halt       1  R
i_rst         1 ──▶│                      │──▶ o_dbg_data  32  C
i_enable      1 ──▶│    riscv_pipeline    │──▶ o_dbg_count 16  C
i_imem_we     1 ──▶│     [secuencial]     │
i_imem_waddr 10 ──▶│                      │
i_imem_wdata  8 ──▶│                      │
i_dbg_addr   16 ──▶│                      │
                   └──────────────────────┘
```

| Puerto | Qué es |
|---|---|
| `i_rst` | reset sincrónico: PC = 0, pipeline vacío, x1..x31 en cero. No toca la imem ni la dmem |
| `i_enable` | 0 congela todo el estado del CPU (no hay clock gating: cada registro tiene su enable). Así la debug unit lo pausa o lo avanza de a un ciclo |
| `o_halt` | 1 cuando la instrucción que detiene el CPU (`ebreak`, `ecall` o un trap) llega a WB. En ese momento todo lo anterior ya se retiró, la instrucción que lo detuvo no escribió nada y ninguna posterior se ejecutó |
| `i_imem_*` | el puerto de escritura de la imem, para cargar el programa (lo usa la debug unit con el CPU en reset) |
| `i_dbg_addr` / `o_dbg_data` | el bus de debug: una dirección elige una palabra del estado interno (ver abajo); `o_dbg_count` es la cantidad de palabras (constante, 89) |

| Parámetro | En el sistema | Para qué |
|---|---|---|
| `IMEM_ADDR_W` | 10 | imem de 2^10 bytes = 1 KB = 256 instrucciones |
| `DMEM_DEPTH` | 256 | dmem de 256 palabras = 1 KB |
| `IMEM_INIT` | "" | archivo `.hex` para precargar la imem (solo simulación) |

Fuera del rango de cada memoria no hay nada: una instrucción traída desde fuera de la imem
o un acceso fuera de la dmem es una excepción (ver abajo).

## Las 5 etapas

```
     IF              ID               EX               MEM             WB
 ┌────────┐      ┌─────────┐      ┌─────────┐      ┌────────┐      ┌─────────┐
 │ PC     │      │ control │      │ ALU     │      │ dmem   │      │ mux del │
 │ imem   │─────▶│ immgen  │─────▶│ saltos  │─────▶│        │─────▶│ resultado│──▶ regfile
 │        │      │ regfile │      │ traps   │      │        │      │         │
 └────────┘      └─────────┘      └─────────┘      └────────┘      └─────────┘
          IF/ID            ID/EX            EX/MEM           MEM/WB
                 └──── hazard_unit ───┘  forward_unit (EX ◀── MEM, WB)
                                         flush_unit (EX ──▶ IF/ID, ID/EX)
```

| Etapa | Qué hace | Carpeta |
|---|---|---|
| IF | lee la instrucción en el PC | [`1_fetch/`](1_fetch/README.md) |
| ID | la decodifica, arma el inmediato, lee los dos operandos y decide si es legal | [`2_decode/`](2_decode/README.md) |
| EX | calcula (ALU), resuelve los saltos y detecta las excepciones de saltos y memoria | [`3_execute/`](3_execute/README.md) |
| MEM | lee o escribe la memoria de datos | [`4_memory/`](4_memory/README.md) |
| WB | escribe el resultado en el banco de registros | [`5_writeback/`](5_writeback/README.md) |

Entre etapas hay un registro de pipeline ([`regs/`](regs/README.md)) que lleva la
instrucción con todo lo que ya se calculó de ella. Los módulos que miran más de una
etapa a la vez están en [`flow/`](flow/README.md):

| Situación | Qué hace el pipeline | Costo | Quién lo decide |
|---|---|---|---|
| una instrucción usa un resultado que todavía no se escribió | lo reenvía desde EX/MEM o MEM/WB (forwarding) | 0 ciclos | `forward_unit` |
| una instrucción usa el dato de un load que está en EX | frena IF e ID un ciclo (stall); el dato le llega desde MEM/WB | 1 ciclo | `hazard_unit` |
| un salto tomado (branch, JAL, JALR) | descarta las 2 instrucciones que entraron detrás | 2 ciclos | `flush_unit` |
| una excepción, `ecall` o `ebreak` | la instrucción no escribe nada, nada posterior se ejecuta, y el CPU se detiene al llegar a WB | — | `trap_unit`, `illegal_check` |

## Excepciones (fatal traps)

El CPU implementa RV32I **sin la arquitectura privilegiada** (no hay CSRs). La
especificación no privilegiada permite que toda excepción sea un *fatal trap*: el
entorno de ejecución (acá, la debug unit) detiene la ejecución. Las causas usan los
códigos estándar de `mcause`.

| Código | Causa | Se detecta en |
|---|---|---|
| 0 | salto tomado a una dirección no múltiplo de 4 (el trap es **del salto**) | EX (`trap_unit`) |
| 1 | instrucción fuera de la imem | ID |
| 2 | instrucción ilegal: todo lo que no es RV32I, incluidas `csr*`, `fence.i`, `mret` y las comprimidas | ID (`illegal_check`) |
| 3 | `ebreak` | ID |
| 4 / 6 | load / store desalineado | EX (`trap_unit`) |
| 5 / 7 | load / store fuera de la dmem | EX (`trap_unit`) |
| 11 | `ecall` | ID |

Las causas de ID viajan con la instrucción y recién actúan en EX. Así, una instrucción del
camino equivocado (detrás de un salto tomado) se descarta sin provocar un trap. Cuando la
instrucción de EX detiene el CPU, se le anulan las escrituras, se congela el PC y se
vacían IF/ID e ID/EX; la instrucción sigue hasta WB y ahí `o_halt` vale 1. La causa, el PC
y la dirección que falló quedan en las palabras 86 a 88 del bus de debug.

## El bus de debug

Un mapa de palabras de 32 bits con el estado interno, que la debug unit lee de a una
(combinacional: la palabra aparece en `o_dbg_data` en el mismo ciclo que la dirección).
Es el contrato con el host: lo decodifica `decode_dump()` en `host/lib/debug_protocol.py`.
Si se agrega una palabra, va siempre al final.

| Palabra | Contenido |
|---|---|
| 0 | PC (IF) |
| 1, 2 | IF/ID: PC, instrucción |
| 3 | control de ID/EX: `[0]` reg_write `[1]` mem_read `[2]` mem_write `[3]` branch `[4]` jump `[5]` is_jalr `[6]` is_auipc `[7]` halt `[8]` alu_src `[10:9]` wb_sel `[14:11]` alu_op |
| 4 | campos de ID/EX: `[4:0]` rs1 `[9:5]` rs2 `[14:10]` rd `[17:15]` funct3 |
| 5 a 8 | ID/EX: PC, rdata1, rdata2, inmediato |
| 9 a 12 | EX: operandos A y B de la ALU (después del forwarding), resultado, destino del salto |
| 13 | flags de EX: `[0]` stall `[1]` flush IF/ID `[2]` flush ID/EX `[3]` redirect `[4]` branch tomado `[5]` zero `[6]` overflow `[7]` halting `[9:8]` forward_a `[11:10]` forward_b |
| 14 | control de EX/MEM: `[0]` reg_write `[1]` mem_read `[2]` mem_write `[3]` halt `[5:4]` wb_sel |
| 15, 16 | EX/MEM: dirección (resultado de la ALU), dato a escribir |
| 17 | campos de EX/MEM: `[4:0]` rd `[7:5]` funct3 |
| 18 | MEM: dato leído de la dmem |
| 19 a 21 | MEM/WB: control (`[0]` reg_write `[1]` halt), resultado, rd |
| 22 a 53 | x0 a x31 |
| 54 a 85 | las primeras 32 palabras de la dmem |
| 86 a 88 | el trap: causa, PC de la instrucción, dirección que falló (válidos con `o_halt = 1`) |
| 89 | `BUILD_ID`, la versión del RTL: la agrega `top_riscv`, no el CPU |

## Reset, enable y halt

Las mismas reglas en todo el pipeline:
- **reset** (`i_rst`): sincrónico; vacía cada etapa (NOP en IF/ID, burbuja en el resto).
- **enable** (`i_enable`): con 0, ningún registro cambia, y se ignoran `stall` y `flush`.
- **halt**: viaja con la instrucción que detiene el CPU hasta WB.

## Para la verificación

`riscv_pipeline.v` tiene un bloque `ifdef RISCV_FORMAL` con la interfaz RVFI que usa
riscv-formal para comparar cada instrucción retirada contra la ISA. Vivado no define esa
macro, así que no forma parte del hardware.
