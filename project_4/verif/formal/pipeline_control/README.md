# pipeline_control

```bash
./run.sh          # ~40 s
```

Propiedades temporales del control del pipeline, sobre `riscv_pipeline` completo y sin
modificar. El programa (8 instrucciones), `i_enable` e `i_rst` son libres en cada ciclo.
La `imem` se reemplaza por `../common/imem_formal.v` (programa libre) y la `dmem` se
achica a 8 palabras con `chparam` (`DMEM_DEPTH`).

## Propiedades

| | Situación (ciclo anterior) | Se exige |
|---|---|---|
| T0 | reset | PC = 0, IF/ID = NOP, ID/EX = burbuja |
| T1 | `i_enable = 0` | PC e IF/ID no cambian |
| T2 | avance normal | PC + 4, y la instrucción leída pasa a ID |
| T3 | stall de load-use (sin trap en EX) | PC e IF/ID quietos, burbuja en ID/EX |
| T4 | salto tomado en EX (sin trap en EX) | PC = destino; IF/ID = NOP y ID/EX = burbuja (2 burbujas) |
| T5 | halt en curso | el PC no se mueve más |
| T6 | salto tomado en EX | no hay stall en el ciclo siguiente |
| T7 | la instrucción de EX detiene el CPU (ecall, ebreak o trap) | el PC no avanza; IF/ID = NOP y ID/EX = burbuja |
| T8 | reset (en el mismo ciclo) | la dmem no se escribe, aunque `i_enable = 1` y EX/MEM tenga un store |

T7 tiene prioridad sobre T3 y T4. Un load que hace trap puede coincidir con un stall de
load-use (su consumidora espera en ID): en ese caso IF/ID se vacía en vez de congelarse. Y un
salto a una dirección no alineada es un trap: el PC no va al destino.

**Invariantes** (propiedades del estado, válidas en todo ciclo desde el reset):

- **I1**: ID/EX contiene a lo sumo una clase de instrucción
  (`$onehot0({branch, jump, halt, load, store})`).
- **I2**: con un halt en curso, EX solo contiene burbujas.

Sin ellas, el paso inductivo arranca en estados inalcanzables (por ejemplo, un ID/EX que
dice "branch y halt a la vez", que el solver mantiene congelando el CPU con
`i_enable = 0`) y no puede cerrar.

## Resultados

| Tarea | Resultado | |
|---|---|---|
| `bmc` | PASS | ninguna ejecución de hasta 20 ciclos viola T0–T8 |
| `prove` | PASS | k-inducción: T0–T8, I1 e I2 valen **para cualquier cantidad de ciclos** |
| `cover` | PASS | stall, salto, halt, load-use justo después de un salto, pausa durante un stall, trap durante un stall |
| `mut_flush` | FAIL ✔ | una sola burbuja después de un salto (T4) |
| `mut_stall` | FAIL ✔ | IF/ID no se congela en un stall (T3) |
| `mut_rstwr` | FAIL ✔ | la dmem escribe durante el reset (T8) |

## Notas técnicas

- En formal, un registro sin valor inicial arranca con **cualquier** valor. Todas las
  propiedades se exigen desde el primer reset (`f_past_valid`).
- `$past(x, n)` puede mirar más atrás que el reset. Los covers que lo usan exigen
  `f_past_valid` en el ciclo observado.
