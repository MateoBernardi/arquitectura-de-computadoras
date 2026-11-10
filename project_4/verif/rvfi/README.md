# rvfi/: el CPU completo contra la ISA RV32I (riscv-formal)

[riscv-formal](https://github.com/YosysHQ/riscv-formal) es el framework estándar para
verificar formalmente procesadores RISC-V. Cada chequeo es un BMC desde el reset sobre
**cualquier** secuencia de instrucciones.

```bash
./run.sh                      # checks.cfg: el diseño actual (todos los chequeos)
./run.sh nostall              # nostall.cfg: variante sin stall de load-use
./run.sh strict               # strict.cfg: sin suposiciones, contra el estándar completo
./run.sh checks reg_ch0       # un solo chequeo
```

Los resultados quedan en `.tools/riscv-formal/cores/tp4/<config>/<chequeo>/`. Los
contraejemplos están en `engine_0/trace.vcd`.

## Cómo está armado

1. **RVFI en el CPU.** `riscv_pipeline.v` tiene un bloque `ifdef RISCV_FORMAL` (Vivado nunca
   lo compila). Cada instrucción lleva consigo, etapa por etapa, su PC, su codificación,
   los operandos que **realmente usó** en EX (después del forwarding) y su acceso a
   memoria. Al retirarse en WB los publica por los puertos `rvfi_*`. Los accesos a
   memoria se publican con la dirección alineada a 4 (`RISCV_FORMAL_ALIGNED_MEM`).
2. **`wrapper.sv`** conecta el CPU con riscv-formal:
   - las instrucciones son **arbitrarias** en cada lectura (`imem_anyseq.v`);
   - `i_enable` es libre (la debug unit puede pausar en cualquier ciclo), pero vale 0
     durante el reset, que es el contrato de la debug unit.
3. **`checks.cfg`** elige los chequeos y sus profundidades. `genchecks.py` genera un `.sby` por
   chequeo dentro de `.tools/riscv-formal/cores/tp4/`, la carpeta que `run.sh` arma con
   enlaces a estos archivos.

## Los chequeos

| Chequeo | Pregunta |
|---|---|
| `insn_<instr>` (37) | ¿la instrucción calcula lo que dice el manual con los operandos que usó? |
| `reg` | ¿cada instrucción lee el **último valor escrito** en sus registros? Cubre forwarding, stalls y bypass WB→ID |
| `pc_fwd`, `pc_bwd` | ¿el PC de cada instrucción es el "próximo PC" de la anterior? Cubre saltos y flush |
| `causal` | ¿una escritura se retira antes que las lecturas que dependen de ella? |
| `unique` | ¿cada instrucción se retira una sola vez? |
| `cover` | ¿se retiran instrucciones? (que lo anterior no sea vacío) |
| `ill` (solo `strict`) | ¿una instrucción ilegal genera una excepción? |

## Configuraciones

| Archivo | Qué cambia |
|---|---|
| `checks.cfg` | el diseño actual, con las suposiciones de abajo |
| `nostall.cfg` | `hazard_unit` → `../variants/hazard_unit_nostall.v` (nunca frena) |
| `strict.cfg` | sin suposiciones y con `ill`: todo lo que no cumple el estándar aparece como FAIL |

## Suposiciones de `checks.cfg`

El estándar exige excepciones que este CPU no implementa. Para poder verificar el resto,
`checks.cfg` asume que los programas nunca las provocan:

- **Sin saltos a direcciones no alineadas ni accesos desalineados.** El RVFI marca esas
  instrucciones con `rvfi_trap`, y `wrapper.sv` asume que no se retiran (salvo
  `ecall`/`ebreak`, que son trap + halt).
- **Sin chequeo de instrucciones ilegales** (`ill`).

`strict.cfg` quita las dos suposiciones. Los resultados están en `../README.md` y en el
reporte de cumplimiento.

## Fuera del alcance de riscv-formal

riscv-formal no modela el contenido de la memoria de datos: el dato de lectura que se
publica sale del propio CPU. Que la `dmem` guarde y devuelva bien cada byte está probado en
`../datapath/dmem_props.sv`.
