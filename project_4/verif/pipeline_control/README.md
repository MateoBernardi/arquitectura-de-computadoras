# pipeline_control

```bash
./run.sh          # ~40 s
```

Propiedades temporales del control del pipeline, sobre `riscv_pipeline` completo y sin
modificar. El programa (8 instrucciones), `i_enable` e `i_rst` son libres en cada ciclo.
La `imem` se reemplaza por `../common/imem_formal.v` (programa libre) y la `dmem` se
achica a 8 palabras con `chparam`.

## Propiedades

| | Situación (ciclo anterior) | Se exige |
|---|---|---|
| T0 | reset | PC = 0, IF/ID = NOP, ID/EX = burbuja |
| T1 | `i_enable = 0` | PC e IF/ID no cambian |
| T2 | avance normal | PC + 4, y la instrucción leída pasa a ID |
| T3 | stall de load-use | PC e IF/ID quietos, burbuja en ID/EX |
| T4 | salto tomado en EX | PC = destino; IF/ID = NOP y ID/EX = burbuja (2 burbujas) |
| T5 | halt en curso | el PC no se mueve más |
| T6 | salto tomado en EX | no hay stall en el ciclo siguiente |

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
| `bmc` | PASS | ninguna ejecución de hasta 20 ciclos viola T0–T6 |
| `prove` | PASS | k-inducción: T0–T6, I1 e I2 valen **para cualquier cantidad de ciclos** |
| `cover` | PASS | stall, salto, halt, load-use justo después de un salto, pausa durante un stall |
| `mut_flush` | FAIL ✔ | una sola burbuja después de un salto (T4) |
| `mut_stall` | FAIL ✔ | IF/ID no se congela en un stall (T3) |

## Notas técnicas

- En formal, un registro sin valor inicial arranca con **cualquier** valor. Todas las
  propiedades se exigen desde el primer reset (`f_past_valid`).
- `$past(x, n)` puede mirar más atrás que el reset. Los covers que lo usan exigen
  `f_past_valid` en el ciclo observado.
