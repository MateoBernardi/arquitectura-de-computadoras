# forward_unit

```bash
./run.sh
```

## Contrato

> El operando que usa EX para el registro `rs` es el valor de la instrucción **más
> reciente** en vuelo que escribe `rs` (MEM antes que WB). Si ninguna lo escribe, es el
> valor que leyó el regfile. `x0` vale siempre 0.

[`forward_unit_props.sv`](forward_unit_props.sv) instancia `forward_unit` y una copia del
mux de forwarding de `riscv_pipeline.v`, y compara el **valor que llega a la ALU** con el
contrato. Todas las entradas son libres: 22 bits de control y 6 valores de 32 bits.

| | Propiedad |
|---|---|
| P1, P2 | `operand_a/b == newest(rs)` |
| P3, P4 | si `rs == x0`, el operando es 0, aunque una instrucción "escriba" x0 |
| P5 | la selección `2'b11` nunca aparece |
| supuesto | el regfile entrega 0 al leer x0 (contrato del regfile, cubierto por `rvfi/` `reg`) |

## Resultados

| Tarea | Resultado | |
|---|---|---|
| `prove` | PASS | demostración completa |
| `cover` | PASS | cada camino de forwarding (A/B, desde MEM/WB, ambos a la vez) es alcanzable |
| `mut_prio` | FAIL ✔ | WB le gana a MEM → se usa un valor viejo |
| `mut_x0` | FAIL ✔ | se reenvía x0 |
| `mut_rs2` | FAIL ✔ | el camino B compara contra rs1 |

La condición de la rama WB no verifica `mem_rd != 0`, mientras que la rama MEM sí. La
prueba demuestra que esa asimetría es inofensiva.
