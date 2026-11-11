# verif/ — verificación formal del CPU RV32I

Verificación formal del pipeline de `project_4` con herramientas libres: Yosys,
SymbiYosys, solvers SMT y [riscv-formal](https://github.com/YosysHQ/riscv-formal). No hace
falta Vivado. Un solver busca **cualquier** entrada (programa, instrucción, valores) que
viole una propiedad, y devuelve una demostración o un contraejemplo concreto.

## Instalación

Las herramientas van en `.tools/`, en la raíz del repo (fuera de git):

```bash
# OSS CAD Suite (Yosys, SymbiYosys, solvers, Verilator)
curl -L -o /tmp/oss.tgz https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-10-27/oss-cad-suite-linux-x64-20261027.tgz
mkdir -p .tools && tar -xzf /tmp/oss.tgz -C .tools
# riscv-formal
git clone https://github.com/YosysHQ/riscv-formal.git .tools/riscv-formal

source project_4/verif/env.sh        # agrega las herramientas al PATH
```

## Qué se verifica

Todo junto, con un resumen por etapa:

```bash
./run_all.sh              # ~25 min (riscv-formal es lo más largo)
RVFI=0 ./run_all.sh       # sin riscv-formal, ~5 min
VARIANTS=1 ./run_all.sh   # además, riscv-formal con cada variante
```

| Carpeta | Alcance | Tipo de prueba |
|---|---|---|
| [`rvfi/`](rvfi/README.md) | **El CPU completo contra la ISA RV32I** (riscv-formal), incluidas las excepciones y que no se trabe | BMC desde el reset, 15 ciclos, cualquier programa |
| [`../sim/`](../sim/README.md) | **La suite oficial riscv-arch-test**, tests de traps y el **sistema completo** (UART + debug unit + CPU) | simulación (Verilator, Icarus) |
| [`forward_unit/`](forward_unit/README.md) | El operando de EX es siempre el valor más reciente | exhaustiva (combinacional) |
| [`hazard_unit/`](hazard_unit/README.md) | El stall de load-use nunca falta; cuándo sobra | exhaustiva (combinacional) |
| [`pipeline_control/`](pipeline_control/README.md) | Reset, congelamiento, stall, flush de saltos, halt y traps | inducción: cualquier cantidad de ciclos |
| [`datapath/`](datapath/README.md) | Decodificación + ALU + saltos; qué instrucciones son legales; memoria de datos | exhaustiva / BMC |

`rvfi/` responde la pregunta principal: ¿el CPU hace lo que dice el manual de RISC-V para
cualquier programa? Las otras carpetas prueban contratos de módulos individuales y
cubren lo que riscv-formal no mira (por ejemplo, el contenido de la memoria).

Cada carpeta tiene un `run.sh` que corre todo y compara cada resultado con el esperado:

```bash
cd project_4/verif/forward_unit && ./run.sh
[ok ] prove        → PASS  (esperado PASS)
[ok ] mut_prio     → FAIL  (esperado FAIL)
...
```

**Mutantes.** Cada suite incluye copias del RTL con un error inyectado (`mut_*`), y exige
que fallen. Así se comprueba que las propiedades detectan errores reales y no pasan
por ser vacías.

## Variantes: probar ideas sin Vivado

`variants/` tiene módulos alternativos con **el mismo nombre de módulo y los mismos
puertos** que uno del RTL. La variante reemplaza al archivo que declara ese módulo
(`tools/variant.sh`), sin tocar nada más:

```bash
./rvfi/run.sh hazard_unit_nostall          # riscv-formal con la variante
../sim/build.sh hazard_unit_nostall        # simulador con la variante
VARIANT=hazard_unit_nostall ../sim/run_act.sh
../sim/bench.py                            # rendimiento: base contra cada variante
```


| Variante | Idea | Dónde se evalúa |
|---|---|---|
| `hazard_unit_precise.v` | frenar solo si la instrucción realmente lee el registro | `hazard_unit/`, `rvfi/`, `../sim/` |
| `hazard_unit_nostall.v` | no frenar nunca en load-use | `rvfi/`, `../sim/` |

Cada variante responde tres preguntas: **¿cumple RV32I?** (riscv-formal y ACT), **¿cuánto
gana?** (ciclos en `../sim/`) y **¿cuánto cuesta en hardware?** (timing y área en
Vivado, con `scripts/`).

| Variante | ¿Cumple? | Ciclos: suite ACT / suma_arreglo (tabla completa en `../sim/README.md`) |
|---|---|---|
| `hazard_unit_nostall.v` | sí: riscv-formal 45/45, ACT 39/39 | −7,4 % / −7,6 % |
| `hazard_unit_precise.v` | sí: riscv-formal 45/45, ACT 39/39 | −0,2 % / 0 % |

## Estructura

```
verif/
├── run_all.sh            toda la verificación, con un resumen por etapa
├── env.sh                agrega .tools/ al PATH
├── tools/
│   ├── suite.sh          lógica común de los run.sh (mutantes, tareas, resultado esperado)
│   ├── variant.sh        qué archivo del RTL reemplaza cada variante
│   └── show_trace.py     muestra contraejemplos como tabla, con el programa desensamblado
├── common/imem_formal.v  imem con programa libre (mismo contrato de puertos que la real)
├── variants/             módulos alternativos para evaluar ideas
├── rvfi/                 riscv-formal (wrapper, mapa de memoria, configuraciones, mutantes)
├── forward_unit/  hazard_unit/  pipeline_control/  datapath/
└── scripts/              etapas siguientes, una vez cerrado el RTL: chequeos de síntesis e
                          implementación en Vivado (warnings críticos, latches, timing, ruteo)
```

## Cómo se observa el RTL sin modificarlo

Salvo el bloque RVFI de `riscv_pipeline.v` (`ifdef RISCV_FORMAL`, invisible para Vivado),
el RTL no se toca:

- **Módulos reemplazables.** `common/imem_formal.v` y `rvfi/imem_anyseq.v` sustituyen a la
  `imem` con los mismos puertos, para que el solver elija el programa.
- **Señales internas.** Se conectan desde el script de Yosys (`connect -nomap -set fv_x dut.x`),
  porque la versión libre de Yosys ignora en silencio las referencias jerárquicas
  (`dut.x`). `check -assert` hace que cualquier cable sin conectar sea un error.
- **`proc -norom`.** Sin esta opción, Yosys convierte el `case` de `control.v` en una ROM. Una
  ROM es estado, y en la inducción arrancaría con contenido arbitrario.

## Cumplimiento de RV32I

**Configuración declarada:** RV32I sin la arquitectura privilegiada (sin Sm ni Zicsr, sin
CSRs). Toda excepción es un **fatal trap**, que la spec no privilegiada permite: el
entorno de ejecución (la debug unit) detiene la ejecución, y la causa (código estándar de
`mcause`), el PC y la dirección que falló quedan en las palabras 86–88 del mapa de debug.

| Condición | Comportamiento |
|---|---|
| instrucción ilegal (incluye `csr*`, porque no hay Zicsr) | trap, causa 2 |
| salto o branch tomado a una dirección no alineada | trap **en el salto**, causa 0 (el PC nunca queda desalineado) |
| load / store desalineado | trap, causa 4 / 6 |
| load / store fuera de la dmem | trap, causa 5 / 7 |
| instrucción fuera de la imem | trap, causa 1 |
| `ecall` | halt, causa 11 |
| `ebreak` | halt, causa 3 (devuelve el control al debugger, como dice la spec) |

En todos los casos, la instrucción que falla **no escribe nada** y no se ejecuta nada
más joven. El detalle está en `../project_4.srcs/sources_1/new/pipeline/README.md`.

**Cómo se comprueba**, con herramientas estándar y de forma independiente:

| Herramienta | Qué prueba | Resultado |
|---|---|---|
| riscv-formal (`rvfi/`) | cualquier programa, contra la ISA, incluidas las excepciones y el mapa de memoria (`pma.sv`) | 45/45 PASS (con 6 mutantes que fallan) |
| riscv-arch-test, ACT4 (`../sim/`) | la suite oficial, autoverificada contra Sail | 39/39 PASS |
| `../sim/run_traps.sh` | cada causa de trap, en la instrucción correcta, y que no hay traps en el camino especulativo | 19/19 PASS |
| `../sim/run_system.sh` | el sistema completo por la UART, incluida la causa del halt que ve la debug unit | 46/46 PASS |
| `datapath/` (`illegal`) | toda codificación que no es RV32I es ilegal (las 2^32) | PASS |
