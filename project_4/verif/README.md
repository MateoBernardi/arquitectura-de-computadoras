# verif/ — verificación del proyecto

Sigue las 5 etapas del flujo: RTL → síntesis → implementación → bitstream → placa. Son 11
capas de prueba repartidas en esas etapas, más una para el software del host: 12 en total
(ver la tabla de capas más abajo). Para el RTL usa herramientas libres (Yosys, SymbiYosys, solvers SMT,
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
./run.sh fpga                      # síntesis, implementación, bitstream y placa (~12 min, Vivado y la placa)
./run.sh programar placa           # solo programar la FPGA con el último bitstream y probarla (~3 min)
./run.sh act traps                 # solo algunas capas
./run.sh --variante hazard_unit_precise rvfi act traps    # una variante
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

| Etapa | Capa | Qué prueba |
|---|---|---|
| RTL | `formal` | propiedades formales por módulo (forward_unit, hazard_unit, pipeline_control, datapath), con mutantes |
| RTL | `rvfi` | el CPU completo contra la ISA RV32I con riscv-formal, incluidas las excepciones, con mutantes |
| RTL | `act` | la suite oficial riscv-arch-test, autoverificada contra Sail: las instrucciones RV32I |
| RTL | `traps` | tests propios: causa y PC que reporta cada trap (ACT, sin CSRs, no prueba excepciones) |
| RTL | `rendimiento` | ciclos y CPI del diseño base y de cada variante; cada variante tiene que dar el mismo resultado |
| RTL | `sistema` | el sistema completo (UART + debug unit + CPU), manejado por la línea serie |
| síntesis | `sintesis` | Vivado: el netlist es lo que pide el RTL (avisos justificados, sin latches, memorias), con mutantes |
| implementación | `implementacion` | Vivado: STA completo (nada sin restringir; setup, hold, pulso), cruces de reloj, ruteo, DRC |
| bitstream | `bitstream` | Vivado: genera el bitstream desde la implementación verificada del hardware actual (con el DRC de `write_bitstream`) |
| placa | `programar` | programa la FPGA por JTAG con ese bitstream y comprueba que terminó de configurarse (DONE) |
| placa | `placa` | la FPGA por la UART: versión, programas y traps comparados contra la simulación, comandos de la debug unit ([`placa/README.md`](placa/README.md)) |
| fuera del flujo | `host` | el software de la PC: protocolo, desensamblador y GUI |

La etapa de placa tiene dos capas: `programar` (JTAG) y `placa` (las pruebas), para poder
repetir las pruebas o reprogramar sin volver a pasar por Vivado. `host` prueba el software
de la PC, que no pasa por el flujo.

**Versión del hardware (`BUILD_ID`).** Es el último commit que cambió algo de lo que entra
al bitstream: `rtl/`, `constraints/` y los tcl de síntesis e implementación de `verif/fpga/`.
Un commit que solo toca documentación, tests o el host no la cambia, así que no obliga a
sintetizar de nuevo ni invalida la placa programada. Con cambios sin commitear en esos
archivos vale 0 (sin versión). `bitstream` solo acepta una implementación verificada de la
versión actual, `programar` solo carga un bitstream de esa versión, y `placa` comprueba que
la FPGA la tenga.

**Reutilización.** `sintesis` e `implementacion` guardan su resultado cuando dan PASS
(`build/verificado/`). Si después no cambió nada en `rtl/`, `constraints/` ni `verif/fpga/`,
la próxima corrida muestra ese resultado en lugar de volver a correr Vivado.
`TP4_REHACER=1 verif/run.sh fpga` las rehace igual. Las capas de FPGA, y por qué no hay simulación de netlist,
están en
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
./rvfi/run.sh hazard_unit_precise       # riscv-formal con la variante
sim/build.sh hazard_unit_precise        # simulador con la variante
VARIANT=hazard_unit_precise sim/run_act.sh
sim/bench.py                            # rendimiento: base contra cada variante
fpga/fmax.sh hazard_unit_precise        # frecuencia máxima con la variante (Vivado)
```

Cada variante responde tres preguntas: **¿cumple RV32I?** (riscv-formal y ACT), **¿cuánto
gana en ciclos?** (`sim/bench.py`) y **¿a qué frecuencia cierra?** (`fpga/fmax.sh`). Lo
que se compara al final es el tiempo de ejecución: frecuencia ÷ CPI, en millones de
instrucciones por segundo (MIPS).

| Variante | Idea | Estado |
|---|---|---|
| `hazard_unit_precise.v` | frenar solo si la instrucción realmente lee el registro | queda como variante: −0,2 % de ciclos en ACT, 0 % en los programas |

### La decisión del load-use (noviembre de 2026)

En el diseño anterior el stall de load-use **sobraba**: la dmem se lee de forma
combinacional y el forwarding desde MEM entregaba el dato del load en el mismo ciclo en que
la instrucción siguiente estaba en EX. El diseño pagaba las dos cosas: el ciclo del stall y,
en el camino crítico, dmem → forwarding → ALU. Había dos formas coherentes de arreglarlo:

- **A** (`hazard_unit_nostall`): sacar el stall y dejar el forwarding del load desde MEM.
- **B** (`riscv_pipeline_load_wb`): dejar el stall y sacar el dato de la dmem del
  forwarding desde MEM. El load se adelanta desde WB, que es donde está cuando su
  consumidora llega a EX, así que los ciclos no cambian.

Las dos cumplen la ISA: riscv-formal 45/45, ACT 39/39, traps 19/19. Frecuencia máxima
(`fpga/fmax.sh`, pasos de 10 MHz):

| Diseño | 50 MHz | 60 MHz | 70 MHz | 80 MHz | fmax |
|---|---|---|---|---|---|
| anterior | +0,106 | −0,531 | | | 50 MHz |
| A: sin stall | +0,659 | +0,272 | −1,408 | | 60 MHz |
| **B: load desde WB** | +1,379 | +0,411 | +0,077 | −1,866 | **70 MHz** |

(WNS de setup en ns; todos los puntos con hold ≥ 0.) A también sube porque sin stall la
señal deja de llegar al reset de ID/EX, pero conserva la dmem en el camino crítico.

Rendimiento, cada uno a su fmax (los ciclos de A, de `sim/bench.py` y `sim/perfil.py`; B
hace exactamente los ciclos del diseño anterior):

| Programa | anterior (50 MHz) | A (60 MHz) | B (70 MHz) | B contra A |
|---|---|---|---|---|
| ACT (39 tests) | CPI 1,335 → 37,5 MIPS | CPI 1,236 → 48,5 MIPS | CPI 1,335 → **52,4 MIPS** | +8 % |
| suma_arreglo (load-use en cada iteración) | 1,616 → 30,9 | 1,492 → 40,2 | 1,616 → **43,3** | +8 % |
| criba | 1,419 → 35,2 | 1,407 → 42,6 | 1,419 → **49,3** | +16 % |

**Se adoptó B.** Gana en todas las cargas, incluso en `suma_arreglo`, el peor caso para
B (usa cada dato justo después de cargarlo): el stall de load-use cuesta como mucho un 8 %
de los ciclos, mientras que B corre un 17 % más rápido.
Contra el diseño anterior, B es un 40 % más rápido con los mismos ciclos.

Desde B, el stall es necesario: el mutante `no_stall` de riscv-formal lo comprueba (ver
`formal/rvfi/README.md`). B pasó a ser el RTL, y A se borró de `variants/` (con el RTL
actual no cumple la ISA; queda en la historia de git).

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
├── sim/                  simulación con Verilator: ACT, traps, rendimiento y desglose del CPI
├── system/               el sistema completo (UART + debug unit + CPU), con Icarus
├── fpga/                 Vivado: crear el proyecto, síntesis, implementación, frecuencia máxima,
│                         informes (recursos, camino crítico) y potencia (potencia/)
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
