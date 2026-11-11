# datapath

```bash
./run.sh          # ~1 min
```

Tres pruebas que complementan a riscv-formal (`../rvfi/`). Cubren de forma exhaustiva la
aritmética y la memoria de datos, que riscv-formal no modela.

## `exec_props.sv`: decodificación + inmediato + ALU + saltos

`control` → `immgen` → muxes `alu_a`/`alu_b` → `alu` → `branch_unit`, conectados igual que
en `riscv_pipeline.v`. Para **cualquier** instrucción aritmética o de salto legal y
**cualquier** valor de operandos y PC:

| | Propiedad |
|---|---|
| E1 | el valor que se escribe en `rd` es el del manual (todas las operaciones de R, I, LUI y AUIPC) |
| E2 | esas instrucciones escriben `rd` y no tocan memoria ni saltan |
| E3 | la decisión de salto es la del manual (BEQ, BNE, BLT, BGE, BLTU, BGEU) |
| E4 | el destino del salto es `pc + imm_b` |
| E5 | un salto condicional no escribe registros ni memoria |

## `dmem_props.sv`: memoria de datos

La `dmem` real (8 palabras) contra un modelo trivial de 32 bytes. El solver elige en
cada ciclo un store o un load cualquiera (byte, media palabra o palabra, con la
dirección alineada), y cada lectura tiene que coincidir con el modelo (D1).

## `illegal_props.sv`: qué instrucciones son legales

`illegal_check` contra las **40 instrucciones de RV32I** como pares (máscara, patrón),
tomados de [riscv-opcodes](https://github.com/riscv/riscv-opcodes), la lista oficial de
RISC-V International (contrastados con la copia que trae riscv-arch-test). Para
**cualquiera** de las 2^32 instrucciones:

| | Propiedad |
|---|---|
| L1 | `illegal` vale 1 si y solo si la instrucción no es ninguna de las 40 |
| L2 | `ecall` y `ebreak` valen 1 solo para su única codificación |

Completa a riscv-formal: sus chequeos `insn_*` prueban que las instrucciones legales no
hacen trap, pero el chequeo `ill` solo prueba la instrucción `0x00000000`. Sin L1, una
`mul` (extensión M) decodificada como `add` pasaría inadvertida: es el mutante `mut_ill`.

## Resultados

| Tarea | Resultado | |
|---|---|---|
| `exec` | PASS | demostración completa (combinacional) |
| `exec_cover` | PASS | SRAI con signo, SLT verdadero, BGEU tomado |
| `mut_sra` | FAIL ✔ | SRA sin extensión de signo: `lui x27,0x9068c; srai x27,x27,10` |
| `dmem` | PASS | cualquier secuencia de 10 accesos |
| `dmem_cover` | PASS | LB negativo después de SB, LHU después de SH |
| `mut_sb` | FAIL ✔ | `sb` al byte 3 escribe `wdata[15:8]` (un error de una versión anterior) |
| `illegal` | PASS | demostración completa (combinacional) |
| `mut_ill` | FAIL ✔ | acepta `funct7 = 0000001` (mul/div) |

Las memorias se convierten en flip-flops (`memory_map`): para memorias chicas, el solver
es mucho más rápido que con la teoría de arrays.
