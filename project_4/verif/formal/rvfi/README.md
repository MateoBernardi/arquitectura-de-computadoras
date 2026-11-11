# rvfi/: el CPU completo contra la ISA RV32I (riscv-formal)

[riscv-formal](https://github.com/YosysHQ/riscv-formal) es el framework estándar para
verificar formalmente procesadores RISC-V. Cada chequeo es un BMC desde el reset sobre
**cualquier** secuencia de instrucciones.

```bash
./run.sh                      # checks.cfg: el diseño actual, contra el estándar completo
./run.sh hazard_unit_precise  # con una variante de ../variants/
./run.sh checks reg_ch0       # un solo chequeo
./mutants.sh                  # mutantes: cada uno tiene que FALLAR
```

Los resultados quedan en `$TOOLS_DIR/riscv-formal/cores/tp4/<config>/<chequeo>/`. Los
contraejemplos están en `engine_0/trace.vcd`.

## Cómo está armado

1. **RVFI en el CPU.** `riscv_pipeline.v` tiene un bloque `ifdef RISCV_FORMAL` (Vivado nunca
   lo compila). Cada instrucción lleva consigo, etapa por etapa, su PC, su codificación,
   los operandos que **realmente usó** en EX (después del forwarding) y su acceso a
   memoria. Al retirarse en WB los publica por los puertos `rvfi_*`. Los accesos a
   memoria se publican con la dirección alineada a 4 (`RISCV_FORMAL_ALIGNED_MEM`).
2. **`wrapper.sv`** conecta el CPU con riscv-formal:
   - las instrucciones son **arbitrarias** en cada lectura (`imem_anyseq.v`);
   - `i_enable` es libre en todo ciclo, incluso durante el reset: no se supone nada
     sobre la debug unit. (Por eso la dmem no escribe durante el reset: si no, un store
     que quedó en EX/MEM se escribiría.)
3. **`pma.sv`** es el mapa de memoria (`RISCV_FORMAL_PMA_MAP`): qué direcciones se pueden
   ejecutar (la imem) y leer o escribir (la dmem). Un acceso fuera de ese mapa tiene que
   generar un trap, sin escribir nada.
4. **`checks.cfg`** elige los chequeos y sus profundidades. `genchecks.py` genera un `.sby` por
   chequeo dentro de `$TOOLS_DIR/riscv-formal/cores/tp4/`, la carpeta que `run.sh` arma con
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
| `ill` | ¿una instrucción ilegal genera una excepción? (solo prueba `0x00000000`; la decodificación completa está en `../datapath/illegal_props.sv`) |
| `liveness` | ¿después de cada instrucción se retira la siguiente, en a lo sumo 8 ciclos? (el CPU no se traba) |

En los `insn_*`, una instrucción que según la spec genera una excepción (salto a una
dirección no alineada, load/store desalineado, acceso fuera del mapa de memoria) tiene que
retirarse con `trap = 1`, sin escribir registros ni memoria.

## Variantes

`./run.sh <variante>` corre los mismos 45 chequeos con un módulo de `../variants/` en
lugar del original. La configuración se genera a partir de `checks.cfg`, reemplazando el
archivo del RTL que declara ese módulo.

| Variante | Resultado |
|---|---|
| `hazard_unit_precise` (frena solo si la instrucción lee el registro) | **45/45 PASS** |

Con el diseño anterior también pasaba `hazard_unit_nostall` (no frenar nunca): la dmem se
lee de forma combinacional, y el forwarding desde MEM entregaba el dato del load en el
mismo ciclo, así que el stall sobraba. Ese camino (dmem → forwarding → ALU) era el camino
crítico, y se sacó del forwarding (ver `../../README.md`, "Variantes"). Desde entonces el
load se adelanta solo desde WB y **el stall es necesario**: lo comprueba el mutante
`no_stall`.

## Resultado (`checks.cfg`): 45/45 PASS

Todos los chequeos pasan, **sin suposiciones** sobre el programa: el solver elige
cualquier instrucción en cada ciclo, incluidas las ilegales, los saltos a direcciones no
alineadas y los accesos fuera de memoria. Corre en unos 10 minutos con 8 hilos.

`liveness` es el único chequeo con una suposición, y es de **equidad**: la debug unit no
pausa el CPU más de 2 ciclos seguidos (`TP4_FAIRNESS` en `wrapper.sv`). Sin ella la
pregunta no tiene sentido, porque un CPU pausado para siempre no retira nada. Los demás
chequeos no la usan.

Antes de implementar los traps, el resultado era 36 PASS y 8 FAIL: los 6 branches (un
salto a una dirección no alineada no generaba una excepción), `reg` (un load desalineado
escribía `rd`, y las codificaciones inválidas se ejecutaban) e `ill`.

## Mutantes (`mutants.sh`)

| Mutante | Error inyectado | Lo detecta |
|---|---|---|
| `no_dmem_range` | sin chequeo de rango de la dmem | `insn_lw` |
| `no_imem_range` | sin chequeo de rango de la imem | `insn_addi` |
| `no_misjump` | un salto a una dirección no alineada no es un trap | `insn_beq` |
| `writes_on_trap` | la instrucción que hace trap escribe `rd` | `insn_lw` |
| `no_illegal` | los opcodes desconocidos son legales | `ill` |
| `deadlock` | stall eterno si la instrucción en ID lee x1 | `liveness` |
| `no_stall` | sin stall de load-use | `reg` (la consumidora del load lee un valor viejo) |

`liveness` solo puede detectar un CPU que se traba **después** de retirar alguna
instrucción. Si se traba desde el reset, el chequeo no encuentra ninguna instrucción con
la que empezar y termina con ERROR (no con FAIL). Ese caso lo cubre `cover`, que exige
que se retiren instrucciones.

## Fuera del alcance de riscv-formal

riscv-formal no modela el contenido de la memoria de datos: el dato de lectura que se
publica sale del propio CPU. Que la `dmem` guarde y devuelva bien cada byte está probado en
`../datapath/dmem_props.sv`.
