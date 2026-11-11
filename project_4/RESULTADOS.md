# Resultados — el CPU entregado

CPU RV32I de 5 etapas en la Nexys4 DDR (Artix-7 XC7A100T, grado -1), commit `a6da504`.
Todos los números salen de `verif/run.sh todo` y de los informes que deja en
`build/reports/`. Los de rendimiento son de **programas que corren en la placa**: la capa
`placa` comprueba que la FPGA hace los mismos ciclos que la simulación del RTL, así que el
desglose que se mide en la simulación es el de la placa.

| | |
|---|---|
| ISA | RV32I, sin CSRs (toda excepción es un *fatal trap*) |
| Pipeline | 5 etapas, forwarding, stall de load-use, saltos resueltos en EX |
| Reloj | **70 MHz** (100 MHz × 7 / 10, MMCM) |
| Memorias | imem 1 KB (256 instrucciones), dmem 1 KB, las dos LUTRAM de lectura asíncrona |
| CPI medido | 1,34 a 1,62 según el programa (ideal: 1) |
| Rendimiento | 43 a 52 MIPS medidos (ideal: 70 MIPS) |
| Recursos | 3222 LUT (5,1 %), 1863 FF (1,5 %), sin BRAM ni DSP |
| Potencia estimada | 0,22 W en el chip; ~0,03 W del diseño sin el MMCM |

## 1. Verificación y corrección funcional

Un solo comando, en el orden del flujo (RTL → sistema → síntesis → implementación →
bitstream → placa):

| Capa | Qué prueba | Resultado |
|---|---|---|
| `formal` | propiedades de cada módulo del pipeline (forwarding, stall, control, datapath), con mutantes | 25/25 |
| `rvfi` | **riscv-formal**: el CPU completo contra la especificación de RV32I, para cualquier programa, incluidas las excepciones (45 chequeos + 7 mutantes) | 52/52 |
| `act` | **riscv-arch-test** (ACT4), la suite oficial: cada test se autoverifica contra Sail, el modelo de referencia de la ISA | 39/39 |
| `traps` | la causa y el PC de cada excepción (ACT, sin CSRs, no las prueba) | 19/19 |
| `rendimiento` | ciclos y CPI; cada variante tiene que terminar con el mismo estado | 14/14 |
| `sistema` | UART + debug unit + CPU, manejado por la línea serie; LEDs y display | 67/67 |
| `host` | el software de la PC | 15/15 |
| `sintesis` | el netlist es lo que pide el RTL (sin latches, avisos justificados, memorias), con mutantes | 22/22 |
| `implementacion` | STA completo, cruces de reloj, ruteo, DRC | 22/22 |
| `placa` | la FPGA, programada con ese bitstream: versión, programas y traps iguales a la simulación ciclo a ciclo, comandos | 41/41 |

**Contra un modelo de referencia (golden model).** No hay co-simulación instrucción por
instrucción con Spike o QEMU porque hay algo más fuerte. riscv-formal compara cada
instrucción retirada contra la especificación formal de la ISA para **todos** los programas
posibles, no para los que uno elige correr. Y ACT compara contra Sail, el modelo de
referencia oficial. El detalle, y por qué hacen falta los dos, está en
[`verif/README.md`](verif/README.md).

**Netlist (gate-level).** No se simula: el STA prueba el timing de todos los caminos en el
peor caso, y la capa `sintesis` comprueba que el netlist sea lo que pide el RTL. La
discusión está en [`verif/fpga/README.md`](verif/fpga/README.md#decisiones).

## 2. Análisis estático de tiempos (STA)

### Frecuencia

| | |
|---|---|
| Reloj del sistema | 70 MHz (período 14,286 ns) |
| Setup: peor margen (WNS) | +0,173 ns, 0 caminos con violaciones |
| Hold: peor margen (WHS) | +0,037 ns |
| Ancho de pulso (WPWS) | +3,000 ns |
| fmax en pasos de 10 MHz | **70 MHz** (80 MHz falla por −1,87 ns) |
| fmax estimada por el margen | 70,9 MHz |

El STA es el de Vivado en el peor caso de proceso, tensión y temperatura (slow corner).
Nada queda sin restringir: `check_timing` no encuentra puertos ni caminos sin restricción,
salvo los puertos asíncronos, excluidos a propósito con el motivo escrito en el XDC.

70 MHz cierra en todas las ubicaciones que se probaron (cada `BUILD_ID` da otra), con
márgenes de +0,01 a +0,20 ns, usando la estrategia `Performance_ExplorePostRoutePhysOpt`
(ver [`verif/fpga/README.md`](verif/fpga/README.md#estrategia-y-robustez)).

### El camino crítico

13,71 ns de los 14,29 disponibles, 16 niveles de lógica. **El 77 % del retardo es ruteo** y
el 23 % lógica.

```
EX/MEM.rd ─▶ forward_unit ─▶ mux de forwarding B ─▶ mux inmediato/registro ─▶ ALU (resta, cadena de carry)
   0 ns         1,9 ns            3,7 ns                    4,8 ns                  9,0 ns
         ─▶ zero ─▶ branch tomado (redirect) ─▶ ¿destino desalineado? ─▶ enable del PC
            10,4 ns      11,1 ns                     11,6 ns              12,8 ns → 13,7 ns en el PC
```

Es un branch que compara un registro que escribió la instrucción anterior. En un mismo
ciclo pasan las cinco cosas: elegir de dónde viene el operando (forwarding), restarlo, ver si
el resultado es cero, decidir el salto y, si el destino está desalineado, no actualizar el
PC (el trap es del salto). Repartido por partes:

| Tramo | ns | |
|---|---|---|
| forwarding (comparar destinos, elegir el operando) | 3,7 | |
| operando B y ALU | 5,3 | la resta de 32 bits es la parte más larga |
| decisión del salto | 2,1 | |
| trap del salto y enable del PC | 1,7 | |
| la red del enable hasta los 33 flip-flops del PC | 0,9 | |

Niveles de lógica de los 1000 caminos más largos: casi todos tienen de 2 a 4 niveles o
entre 15 y 17 (la familia de este camino, en sus 32 bits).

**Cómo se llegó a 70 MHz** (de 50 MHz): el camino crítico anterior también pasaba por la
lectura de la dmem (un load seguido de un salto que usa el dato). Ese forwarding sobraba
porque el stall de load-use ya separa al load de quien lo usa, y sacarlo no cambió ni un
ciclo. La evaluación, contra la otra opción (sacar el stall), está en
[`verif/README.md`](verif/README.md#variantes-probar-ideas-sin-vivado).

## 3. Rendimiento: teórico contra real

**Teórico.** El pipeline retira, como máximo, una instrucción por ciclo: CPI ideal = 1 y
**70 MIPS** a 70 MHz. Las memorias responden en el mismo ciclo (lectura asíncrona), así que
no hay ciclos de espera por memoria. Lo único que aleja al CPU del ideal son tres cosas, con
costo fijo:

| Situación | Costo | Por qué |
|---|---|---|
| salto tomado (branch, `jal`, `jalr`) | 2 ciclos | se resuelve en EX: las 2 instrucciones que entraron detrás se descartan (equivale a predecir siempre "no tomado") |
| una instrucción usa el dato de un load justo anterior | 1 ciclo | el dato recién está al final de MEM |
| llenado y vaciado del pipeline | 3 ciclos por programa | |

**Real**, en la placa (ciclos medidos en la FPGA y desglosados en la simulación, que da
los mismos):

| Programa | Instrucciones | Ciclos (placa) | CPI | MIPS a 70 MHz | % del ideal |
|---|---|---|---|---|---|
| `criba` | 322 | 457 | 1,419 | 49,3 | 70 % |
| `criba_opt` | 322 | 453 | 1,407 | 49,8 | 71 % |
| `criba_unroll` | 277 | 378 | 1,365 | 51,3 | 73 % |
| `suma_arreglo` | 518 | 837 | 1,616 | 43,3 | 62 % |
| `pipeline_test` | 61 | 83 | 1,361 | 51,4 | 73 % |
| suite ACT (39 tests, solo simulación) | 124 057 | 165 575 | 1,335 | 52,4 | 75 % |

### De dónde salen los ciclos perdidos

| Programa | stall de load-use | flush por branch tomado | flush por `jal` | flush por `jalr` | llenado | memoria |
|---|---|---|---|---|---|---|
| `criba` | +0,012 | **+0,224** | **+0,174** | 0 | +0,009 | 0 |
| `criba_opt` | 0 | **+0,224** | **+0,174** | 0 | +0,009 | 0 |
| `criba_unroll` | 0 | **+0,152** | **+0,202** | 0 | +0,011 | 0 |
| `suma_arreglo` | +0,124 | **+0,486** | 0 | 0 | +0,006 | 0 |
| `pipeline_test` | +0,016 | **+0,230** | +0,033 | +0,033 | +0,049 | 0 |
| suite ACT | +0,098 | **+0,180** | +0,051 | +0,005 | +0,001 | 0 |

(Aporte al CPI de cada causa. CPI = 1 + la suma de la fila.)

**Los saltos son la pérdida principal: de 0,24 a 0,49 ciclos por instrucción**, del 70 al
98 % de lo que se pierde. El load-use pesa poco (0 a 0,12) y la memoria nada.

### CPI por categoría de instrucción

| Categoría | CPI | Por qué |
|---|---|---|
| ALU (registro o inmediato), `lui`, `auipc`, store | 1 | el forwarding cubre todas las dependencias |
| branch no tomado | 1 | el pipeline ya siguió por el camino correcto |
| load | 1, o 2 si la siguiente instrucción usa el dato | stall de load-use |
| branch tomado, `jal`, `jalr` | 3 | 2 ciclos de flush |

La mezcla de cada programa, con la cantidad de instrucciones de cada categoría, está en
`build/reports/perfil.md` (`verif/sim/perfil.py`). Por ejemplo, en la criba el 20 % de las
instrucciones son saltos tomados (11 % branches, 9 % `jal`) y causan el 95 % de los ciclos
perdidos.

**Qué daría reducir la penalización de salto**, con los mismos programas: si costara 1 ciclo
(saltos resueltos en ID), la criba pasaría de CPI 1,42 a 1,22; con una predicción perfecta, a
1,02. Pero resolver en ID agrega la comparación al camino de ID, que hoy no es el crítico, y
habría que medir cuánto baja la frecuencia. Queda como trabajo futuro.

## 4. Recursos, potencia y eficiencia

### Utilización (después del place & route)

| Recurso | Usados | Del chip |
|---|---|---|
| LUT | 3222 (2697 de lógica, 525 como memoria) | 5,1 % |
| FF | 1863 | 1,5 % |
| MUXF7 / MUXF8 | 666 / 128 | 2,1 % / 0,8 % |
| BRAM / DSP | 0 / 0 | — |
| MMCM / BUFG | 1 / 2 | |

| Bloque | LUT | LUTRAM | FF | Comentario |
|---|---|---|---|---|
| CPU (`riscv_pipeline`) | 2611 | 512 | 1578 | |
| · banco de registros | 870 | 0 | 1024 | en flip-flops: el reset borra los 32 registros en un ciclo, y una RAM no puede |
| · ID/EX (con la ALU y el forwarding que Vivado ubicó ahí) | 771 | 0 | 195 | |
| · imem / dmem | 277 / 316 | 256 / 256 | 0 | RAM distribuida, lectura asíncrona |
| debug unit | 488 | 0 | 124 | sobre todo el mux del dump (90 palabras) |
| UART | 86 | 12 | 55 | |
| LEDs y display | 31 | 0 | 62 | |

No usa BRAM porque las memorias se leen de forma asíncrona (en el mismo ciclo), y una BRAM
solo lee de forma sincrónica. Ni DSP: RV32I no tiene multiplicación.

### Potencia (estimada por Vivado)

La Nexys4 DDR no mide la corriente de la FPGA, así que la potencia es la que estima
`report_power`. Se estimó dos veces: con las tasas de conmutación por defecto, y con la
actividad de una simulación del sistema corriendo la criba en bucle (2 ms, SAIF; Vivado
apareó el 15 % de las redes, los registros y los puertos, y propagó el resto).

| | Sin actividad | Con actividad simulada |
|---|---|---|
| **total en el chip** | 0,218 W | **0,220 W** |
| estática (fugas del chip: está con o sin diseño) | 0,097 W | 0,097 W |
| dinámica | 0,121 W | 0,122 W |
| · MMCM | 0,090 W | 0,090 W |
| · relojes | 0,006 W | 0,007 W |
| · lógica (LUT, FF, LUTRAM) | 0,007 W | 0,006 W |
| · señales (ruteo) | 0,013 W | 0,012 W |
| · E/S | 0,005 W | 0,007 W |

El diseño en sí (lógica, ruteo y relojes) consume **~0,025 W**. El resto es la fuga del chip
(44 %) y el MMCM (41 %). Las dos estimaciones casi coinciden porque la parte que depende de
la actividad es chica. La confianza que informa Vivado es "Medium".

### Eficiencia

| | Con la potencia total (0,220 W) | Con la del diseño (lógica + ruteo + relojes, 0,025 W) |
|---|---|---|
| MIPS/mW (criba, 49,3 MIPS) | 0,22 | 1,97 |
| energía por instrucción | 4,5 nJ | 0,51 nJ |

No se informa CoreMark/MHz ni DMIPS/MHz: los dos necesitan más memoria de la que tiene la
placa (CoreMark son ~12 KB de código), y aquí solo se informa lo que corre en el hardware.

## 5. Trabajo futuro

- **Benchmarks probados en la placa.** Los kernels de
  [riscv-tests](https://github.com/riscv-software-src/riscv-tests) (`multiply`, `median`,
  `vvadd`, `qsort`) entran en la imem (de 56 a 132 instrucciones), pero sus datos no (de 1,2 a
  16 KB). Además, la debug unit solo carga la imem. Haría falta un comando para cargar la dmem
  y datasets más chicos (cada benchmark trae su generador y se autoverifica). Darían C
  compilado y probado, no un puntaje comparable con otros CPUs.
- **Penalización de salto** (la pérdida principal, ver la sección 3): resolver en ID, o una
  predicción estática (hacia atrás = tomado).
- **El MMCM es el 41 % de la potencia.** Un reloj de 70 MHz necesita un MMCM o un PLL; un
  PLLE2 (100 MHz × 14 / 20) alcanza para una sola salida y probablemente consuma menos: habría
  que medirlo con `report_power`.
