# hazard_unit

```bash
./run.sh
```

## Contrato

El stall de load-use hace falta cuando hay un load en EX con destino `rd ≠ x0` y la
instrucción en ID **realmente lee** ese registro. Qué formatos leen `rs1`/`rs2` sale del
manual RV32I: R, S y B leen los dos; I lee solo `rs1`; U, J y SYSTEM no leen ninguno.

[`hazard_unit_props.sv`](hazard_unit_props.sv) deja libre la instrucción completa en ID
(32 bits) y extrae los campos como `riscv_pipeline.v`.

| | Propiedad | Tipo |
|---|---|---|
| S1 | si hace falta stall, hay stall | seguridad |
| S2 | solo frena un load con `rd ≠ x0` que coincide con algún campo de registro | seguridad |
| S3 | los formatos R, S y B nunca tienen stalls de más | seguridad |
| E1 | nunca hay stalls de más | precisión |

## Resultados

| Tarea | Resultado | |
|---|---|---|
| `prove` | PASS | **seguro**: nunca falta un stall |
| `cover` | PASS | hay stalls de más con instrucciones I, LOAD, JALR, JAL, LUI, AUIPC y SYSTEM |
| `exact` | **FAIL** | **no es preciso** (hallazgo, ver abajo) |
| `precise` | PASS | la variante `../variants/hazard_unit_precise.v` cumple S1–S3 y E1 |
| `mut_rs2` | FAIL ✔ | sin comparar `rs2` falta el stall (S1) |
| `mut_load` | FAIL ✔ | frena sin un load (S2, S3) |

### Hallazgo: stalls innecesarios

`hazard_unit` compara contra los campos crudos `inst[19:15]` e `inst[24:20]`, aunque en
ese formato sean bits del inmediato:

```asm
lw   x5, 0(x2)
addi x6, x1, 5      # imm[4:0] = 5 → "rs2" = x5 → stall innecesario
lw   x1, 0(x2)
ebreak              # 0x00100073: bits [24:20] = 1 → stall innecesario
```

El resultado es correcto, pero se pierde un ciclo. La variante precisa recibe además el
opcode y lo evita. Para usarla hay que cambiar la instancia en `riscv_pipeline.v` y
conectar `.id_opcode(id_opcode)`.

La suposición `LEGAL_ONLY` (solo instrucciones RV32I válidas) se usa únicamente en
`exact`, para que el contraejemplo sea un programa real. La seguridad vale para
cualquier patrón de 32 bits.
