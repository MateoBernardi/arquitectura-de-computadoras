# `5_writeback/` — etapa WB

Escribe en el banco de registros el valor que produjo la instrucción. No tiene un módulo
propio: son tres piezas que están en otros lugares, y este README las junta.

```
                    ┌─────────┐
 resultado ALU ────▶│         │
 dato de la dmem ──▶│ mux del │──▶ resultado ──▶ MEM/WB ──▶ regfile (escritura)
 PC + 4 ───────────▶│ result. │       │
 inmediato U ──────▶│ (wb_sel)│       └──▶ forwarding a EX
                    └─────────┘
       en MEM (riscv_pipeline)      regs/          2_decode/
```

1. **El mux del resultado** (en `riscv_pipeline`, combinacional): elige el valor según
   `wb_sel`, que generó `control` en ID.

   | `wb_sel` | Valor | Instrucciones |
   |---|---|---|
   | `00` | resultado de la ALU | aritméticas, lógicas, AUIPC |
   | `01` | dato leído de la dmem | loads |
   | `10` | PC + 4 | JAL, JALR (la dirección de retorno) |
   | `11` | inmediato U | LUI |

   El mux está en MEM y no en WB porque su salida es también la fuente del forwarding
   desde EX/MEM: así la instrucción siguiente recibe el valor final, sea cual sea su origen.
2. **El registro MEM/WB** ([`regs/`](../regs/README.md)): guarda el resultado, el registro
   destino y si escribe.
3. **La escritura en el regfile** ([`2_decode/`](../2_decode/README.md)): en el flanco,
   solo con el CPU habilitado. Lo que se escribe es visible para ID en el mismo ciclo.

## El halt

La marca de "esta instrucción detiene el CPU" viaja con la instrucción hasta WB. Ahí se
convierte en `o_halt`, la salida que la debug unit usa para frenar el CPU. Cuando vale 1,
todo lo anterior ya se escribió y la instrucción que lo detuvo no escribió nada.
