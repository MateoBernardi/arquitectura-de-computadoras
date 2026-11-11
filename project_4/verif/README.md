# verif/ — verificación del proyecto

Sigue el flujo RTL → sistema → síntesis → implementación → bitstream → placa. Para el
RTL usa herramientas libres (Yosys, SymbiYosys, solvers SMT,
[riscv-formal](https://github.com/YosysHQ/riscv-formal), Verilator, Icarus,
riscv-arch-test); Vivado solo hace falta para las etapas de FPGA.

## Instalación

```bash
verif/tools/install.sh        # instala lo que falte, con versiones fijas
verif/run.sh --lista          # qué capa puede correr y qué le falta a cada una
```

Las herramientas van en `TOOLS_DIR`: por defecto `.tools/`, al lado de `project_4/`
(fuera de git). Se puede usar otra carpeta con `TOOLS_DIR=/ruta verif/run.sh ...`.
Si una herramienta no está en `TOOLS_DIR`, se usa la del sistema.

## Cómo se corre

```bash
./run.sh                           # todas las capas (~35 min)
./run.sh rapido                    # todo menos riscv-formal y Vivado (~6 min)
./run.sh fpga                      # síntesis, implementación y placa (~12 min, Vivado y la placa)
./run.sh act traps                 # solo algunas capas
./run.sh --variante hazard_unit_nostall rvfi act traps    # una variante
./run.sh --lista                   # capas, grupos y herramientas
```

Cada prueba escribe un renglón `[ok ]` o `[MAL]`, y `run.sh` los cuenta. El resultado de
una capa es:

| Resultado | Significa |
|---|---|
| PASS | corrió al menos una prueba y todas dieron bien |
| FAIL | alguna falló, el script terminó con error, **o no corrió ninguna prueba** |
| SKIP | falta una herramienta: la capa no se probó. **Un SKIP nunca es un PASS** |

El código de salida es 0 solo si todas las capas pedidas dan PASS (1 si alguna falla, 2
si alguna quedó en SKIP). Los reportes quedan en `build/reports/` (de `project_4/`): un
`<capa>.log` con la salida completa y `resumen.md` con la tabla de resultados, el commit
y las versiones de las herramientas. Todo lo generado va a `build/`.

| Capa | Qué prueba |
|---|---|
| `formal` | propiedades formales por módulo (forward_unit, hazard_unit, pipeline_control, datapath), con mutantes |
| `rvfi` | el CPU completo contra la ISA RV32I con riscv-formal, incluidas las excepciones, con mutantes |
| `act` | la suite oficial riscv-arch-test, autoverificada contra Sail: las instrucciones RV32I |
| `traps` | tests propios: causa y PC que reporta cada trap (ACT, sin CSRs, no prueba excepciones) |
| `rendimiento` | ciclos y CPI del diseño base y de cada variante; cada variante tiene que dar el mismo resultado |
| `sistema` | el sistema completo (UART + debug unit + CPU), manejado por la línea serie |
| `host` | el software de la PC: protocolo, desensamblador y GUI |
| `sintesis` | Vivado: el netlist es lo que pide el RTL (avisos justificados, sin latches, memorias), con mutantes |
| `implementacion` | Vivado: STA completo (nada sin restringir; setup, hold, pulso), cruces de reloj, ruteo, DRC |
| `placa` | la FPGA real por la UART: versión, programas y traps comparados contra la simulación, comandos de la debug unit ([`placa/README.md`](placa/README.md)) |

Las capas de FPGA, y por qué no hay simulación de netlist ni capa de bitstream, están en
[`fpga/README.md`](fpga/README.md).

## Qué se verifica

| Carpeta | Alcance | Tipo de prueba |
|---|---|---|
| [`formal/rvfi/`](formal/rvfi/README.md) | **El CPU completo contra la ISA RV32I** (riscv-formal), incluidas las excepciones y que no se trabe | BMC desde el reset, 15 ciclos, cualquier programa |
| [`sim/`](sim/README.md), [`system/`](system/README.md) | **La suite oficial riscv-arch-test**, tests de traps y el **sistema completo** (UART + debug unit + CPU) | simulación (Verilator, Icarus) |
| [`formal/forward_unit/`](formal/forward_unit/README.md) | El operando de EX es siempre el valor más reciente | exhaustiva (combinacional) |
| [`formal/hazard_unit/`](formal/hazard_unit/README.md) | El stall de load-use nunca falta; cuándo sobra | exhaustiva (combinacional) |
| [`formal/pipeline_control/`](formal/pipeline_control/README.md) | Reset, congelamiento, stall, flush de saltos, halt y traps | inducción: cualquier cantidad de ciclos |
| [`formal/datapath/`](formal/datapath/README.md) | Decodificación + ALU + saltos; qué instrucciones son legales; memoria de datos | exhaustiva / BMC |

`rvfi/` responde la pregunta principal: ¿el CPU hace lo que dice el manual de RISC-V para
cualquier programa? Las otras carpetas prueban contratos de módulos individuales y
cubren lo que riscv-formal no mira (por ejemplo, el contenido de la memoria).

`forward_unit/` y la prueba `exec` de `datapath/` se superponen con riscv-formal, que ya
prueba el forwarding y cada instrucción sobre el CPU entero. Se conservan a propósito.
Son propiedades escritas a mano, cortas y sobre un solo módulo, así que muestran de
forma directa cómo se arma una verificación formal (especificación, `assert`, `cover`,
mutantes). Además corren en segundos y, si algo falla, señalan el módulo.

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
sim/build.sh hazard_unit_nostall        # simulador con la variante
VARIANT=hazard_unit_nostall sim/run_act.sh
sim/bench.py                            # rendimiento: base contra cada variante
```


| Variante | Idea | Dónde se evalúa |
|---|---|---|
| `hazard_unit_precise.v` | frenar solo si la instrucción realmente lee el registro | `hazard_unit/`, `rvfi/`, `sim/` |
| `hazard_unit_nostall.v` | no frenar nunca en load-use | `rvfi/`, `sim/` |

Cada variante responde tres preguntas: **¿cumple RV32I?** (riscv-formal y ACT), **¿cuánto
gana?** (ciclos en `sim/`) y **¿cuánto cuesta en hardware?** (timing y área en
Vivado, con `scripts/`).

| Variante | ¿Cumple? | Ciclos: suite ACT / suma_arreglo (tabla completa en `sim/README.md`) |
|---|---|---|
| `hazard_unit_nostall.v` | sí: riscv-formal 45/45, ACT 39/39 | −7,4 % / −7,6 % |
| `hazard_unit_precise.v` | sí: riscv-formal 45/45, ACT 39/39 | −0,2 % / 0 % |

## Estructura

```
verif/
├── run.sh                punto de entrada: todas las capas, con resumen y reportes
├── env.sh                rutas comunes (PROJ, RTL_DIR, TOOLS_DIR) y PATH de las herramientas
├── tools/
│   ├── install.sh        instala las herramientas en TOOLS_DIR
│   ├── suite.sh          lógica común de las suites formales (mutantes, resultado esperado)
│   ├── variant.sh        qué archivo del RTL reemplaza cada variante
│   ├── pyunit.py         corre los tests de Python con el formato [ok ]/[MAL]
│   └── show_trace.py     muestra contraejemplos como tabla, con el programa desensamblado
├── formal/               verificación formal: forward_unit/ hazard_unit/ pipeline_control/
│                         datapath/ rvfi/ (riscv-formal) y common/imem_formal.v
├── sim/                  simulación con Verilator: ACT, traps, rendimiento
├── system/               el sistema completo (UART + debug unit + CPU), con Icarus
├── fpga/                 Vivado: crear el proyecto, síntesis, implementación, frecuencia máxima
├── placa/                la FPGA real: programarla (JTAG) y probarla por la UART
└── variants/             módulos alternativos para evaluar ideas
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
más joven. El detalle está en `../rtl/pipeline/README.md`.

**Cómo se comprueba**, con herramientas estándar y de forma independiente:

| Herramienta | Qué prueba | Resultado |
|---|---|---|
| riscv-formal (`formal/rvfi/`) | cualquier programa, contra la ISA, incluidas las excepciones y el mapa de memoria (`pma.sv`) | 45/45 PASS (con 6 mutantes que fallan) |
| riscv-arch-test, ACT4 (`sim/`) | la suite oficial, autoverificada contra Sail: las instrucciones RV32I (suite I). Sin CSRs no corre los tests de excepciones | 39/39 PASS |
| `sim/run_traps.sh` (test propio) | la causa y el PC que el CPU reporta en cada trap, y que no hay traps en el camino especulativo. Existe porque la suite oficial, tal como la corremos (sin CSRs), no prueba las excepciones | 19/19 PASS |
| `system/run.sh` | el sistema completo por la UART, incluida la causa del halt que ve la debug unit | 46/46 PASS |
| `formal/datapath/` (`illegal`) | toda codificación que no es RV32I es ilegal (las 2^32) | PASS |
