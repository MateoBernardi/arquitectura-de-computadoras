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

| Carpeta | Alcance | Tipo de prueba |
|---|---|---|
| [`rvfi/`](rvfi/README.md) | **El CPU completo contra la ISA RV32I** (riscv-formal) | BMC desde el reset, 15 ciclos, cualquier programa |
| [`forward_unit/`](forward_unit/README.md) | El operando de EX es siempre el valor más reciente | exhaustiva (combinacional) |
| [`hazard_unit/`](hazard_unit/README.md) | El stall de load-use nunca falta; cuándo sobra | exhaustiva (combinacional) |
| [`pipeline_control/`](pipeline_control/README.md) | Reset, congelamiento, stall, flush de saltos, halt | inducción: cualquier cantidad de ciclos |
| [`datapath/`](datapath/README.md) | Decodificación + ALU + saltos; memoria de datos | exhaustiva / BMC |

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

`variants/` tiene módulos alternativos con los mismos puertos que los originales. Para
evaluar una idea se cambia el archivo en la configuración y se corren los mismos chequeos:

| Variante | Idea | Dónde se evalúa |
|---|---|---|
| `hazard_unit_precise.v` | frenar solo si la instrucción realmente lee el registro | `hazard_unit/` |
| `hazard_unit_nostall.v` | no frenar nunca en load-use | `rvfi/nostall.cfg` |

## Estructura

```
verif/
├── env.sh                agrega .tools/ al PATH
├── tools/
│   ├── suite.sh          lógica común de los run.sh (mutantes, tareas, resultado esperado)
│   └── show_trace.py     muestra contraejemplos como tabla, con el programa desensamblado
├── common/imem_formal.v  imem con programa libre (mismo contrato de puertos que la real)
├── variants/             módulos alternativos para evaluar ideas
├── rvfi/                 riscv-formal (wrapper, configuraciones)
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

## Plan: cumplimiento de RV32I

**Configuración declarada:** RV32I sin la arquitectura privilegiada (sin Sm ni Zicsr, sin
CSRs de M-mode). Las excepciones que exige la ISA se implementan como **fatal traps**, que
la spec no privilegiada permite: el entorno de ejecución (la debug unit) detiene la
ejecución.

| Condición | Comportamiento |
|---|---|
| instrucción ilegal (incluye `csr*`, porque no hay Zicsr) | fatal trap, causa "illegal" |
| salto o branch tomado a una dirección no alineada | fatal trap **en el salto** (el PC nunca queda desalineado) |
| load/store desalineado | fatal trap |
| acceso fuera de la imem o la dmem (hoy da la vuelta en silencio) | fatal trap ("access fault") |
| `ecall` | halt, causa "ecall" |
| `ebreak` | halt (devuelve el control al debugger, como dice la spec) |

En todos los casos, la instrucción que falla **no escribe nada**, no se ejecuta nada más
joven, y la causa y el PC quedan visibles en palabras nuevas al final del mapa de debug
(`debug_protocol.py` y la GUI se actualizan).

**Pasos:**
1. Simulador: el RTL con Verilator (`sim/`), con memorias grandes solo en simulación (un
   parámetro `DMEM_DEPTH` nuevo, con el valor por defecto actual) y la misma imagen
   cargada en la imem y en la dmem. Corre los tests oficiales **riscv-arch-test (ACT4)**,
   autoverificados contra Sail. Requiere `gcc-riscv64-unknown-elf`,
   `picolibc-riscv64-unknown-elf`, `ruby-full`, `ruby-bundler` y `mise`.
2. Correr el CPU actual con la suite completa (riscv-formal + ACT4) y listar las fallas.
3. Implementar los fatal traps, el chequeo de rango y los cambios del mapa de debug, y
   repetir hasta que pase todo.
