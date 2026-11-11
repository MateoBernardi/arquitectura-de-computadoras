# verif/fpga/ — síntesis, implementación y frecuencia máxima

Las etapas del flujo que necesitan Vivado: RTL → **síntesis → implementación →
bitstream** → placa. Se corren con `verif/run.sh fpga` (capas `sintesis`, `implementacion`
y `bitstream`). Si `rtl/`, `constraints/` y `verif/fpga/` no cambiaron desde la última
corrida verificada, `sintesis` e `implementacion` muestran ese resultado sin correr Vivado
(ver [`../README.md`](../README.md)).

| Archivo | Qué hace |
|---|---|
| `create_project.tcl` | crea el proyecto de Vivado desde cero en `build/vivado/tp4.xpr` (no se versiona) |
| `synth.tcl` | sintetiza; recibe `BUILD_ID` y la frecuencia del MMCM por variables de entorno |
| `check_synth.py` | revisa el log de la síntesis contra el RTL |
| `synth_mutants.sh` | sintetiza un RTL con errores inyectados y comprueba que `check_synth.py` los detecte |
| `impl.tcl` | place & route y los reportes de STA, ruteo, DRC y metodología |
| `check_impl.py` | revisa esos reportes |
| `bitstream.tcl` | genera el bitstream de la implementación ya verificada (no implementa de nuevo) |
| `waivers.txt` | los avisos de Vivado que son lo que pide el RTL, cada uno con su motivo |
| `fmax.sh` | busca la frecuencia máxima a la que el diseño cierra timing |

## Capa `sintesis`: el netlist es lo que pide el RTL

No compara contra números esperados (cantidad de LUTs o FFs), sino contra el RTL:

| Chequeo | Qué detecta |
|---|---|
| sin errores ni critical warnings | fallas de la herramienta o RTL inválido |
| cero latches | un `always` combinacional que no asigna en todos los caminos |
| cada aviso justificado en `waivers.txt` | cualquier aviso nuevo; y una justificación que ya no corresponde a ningún aviso también falla, para que la lista no quede vieja |
| Vivado no eliminó lógica secuencial | un registro que nadie usa (Vivado lo informa como INFO, no como aviso) |
| cada arreglo del RTL es RAM, o está justificado | memorias implementadas de otra forma que la que pide el RTL; y ninguna RAM que el RTL no declare |
| mutantes: un latch y un registro sin uso | que el chequeo realmente los detecta con esta versión de Vivado |

**Qué no hace:** probar que el netlist hace lo mismo que el RTL. Detecta las causas
conocidas de diferencias, no cualquier diferencia. Por ejemplo, un registro que en el
RTL siempre vale 0 Vivado lo reemplaza por la constante sin avisar: no es un error de
síntesis (el netlist hace lo que dice el RTL), es código muerto en el RTL.

## Capa `implementacion`: STA completo y diseño físico válido

| Chequeo | Qué garantiza |
|---|---|
| `check_timing`: nada sin restricción | que STA analizó **todos** los caminos (si un camino no tiene restricción, STA no lo mira y diría "0 violaciones") |
| setup, hold y ancho de pulso con margen ≥ 0 | timing correcto en todos los caminos, en el peor caso de proceso, tensión y temperatura |
| cruces entre relojes seguros | ningún cruce de dominio sin sincronizar |
| todas las redes ruteadas | que el router conectó cada cable del diseño |
| DRC y metodología justificados | un diseño físico válido |

Los puertos de la placa son asíncronos (UART, botón, LEDs) y el RTL los trata así: las
entradas pasan por un sincronizador `sync_2ff`. Por eso en el XDC están excluidos del
análisis con `set_false_path`, con el motivo escrito. `check_timing` los informa como
excluidos a propósito; un puerto **sin ninguna** restricción es un fallo.

## Informes para la presentación (no son chequeos)

Las capas dejan, además de los chequeos, información sobre el diseño. No falla nada por
estos números: no hay valores esperados contra los que compararlos.

| Informe | Lo deja | Qué tiene |
|---|---|---|
| `build/reports/sintesis/utilizacion.md` | capa `sintesis` (al final del log) | recursos del netlist sintetizado, total y por módulo |
| `build/reports/implementacion/informe.md` | capa `implementacion` (`informe.py`) | recursos después del place & route, el camino crítico tramo por tramo, la distribución de niveles de lógica y la potencia |
| `build/reports/implementacion/potencia_*.rpt` | `impl.tcl` y `potencia/potencia.sh` | potencia estimada por Vivado, sin y con actividad simulada |

**Potencia con actividad (`potencia/`).** `report_power` sin más datos supone una tasa de
conmutación por defecto para cada señal. `potencia.sh` simula el sistema (RTL, en xsim)
corriendo la criba en bucle durante 2 ms después de recibir `R` por la UART, guarda la
actividad de cada señal (SAIF) y se la pasa a `report_power`. Vivado aparea por nombre las
señales del SAIF con las del netlist (registros y puertos, ~11 % de las redes) y propaga el
resto, y dice cuántas apareó. Es una estimación: la Nexys4 DDR no mide la corriente de la
FPGA. En Ubuntu 24.04, xsim necesita `libtinfo.so.5`, que ya no viene con el sistema; si
falta, el informe queda solo con la estimación sin actividad.

## Frecuencia máxima (`fmax.sh`)

Sintetiza e implementa el diseño a 50, 60, 70, 80, 90 y 100 MHz, en ese orden, y se
detiene en la primera frecuencia que no pasa los chequeos de la implementación. Pasos más
chicos no valen la pena: solo interesa una mejora significativa. Cada punto se
implementa, porque la estimación por el margen de setup (1 / (período − WNS)) no alcanza:
cada frecuencia produce otra ubicación y otro ruteo. `fmax.sh <variante>` hace lo mismo con
una variante de `../variants/`, sobre una copia del RTL.

### Resultados

**El sistema corre a 70 MHz** (`MMCM_MULT = 7`, `MMCM_DIV_X8 = 80`: VCO de 700 MHz,
divisor 10).

| Frecuencia | WNS (ns) | WHS (ns) | Resultado |
|---|---|---|---|
| 50 MHz | +1,379 | +0,035 | PASS |
| 60 MHz | +0,411 | +0,060 | PASS |
| 70 MHz | +0,077 | +0,076 | PASS |
| 80 MHz | −1,866 | +0,035 | FAIL |

El camino crítico a 70 MHz y el análisis completo de timing están en
[`../../RESULTADOS.md`](../../RESULTADOS.md).

### Estrategia y robustez

Que una implementación cierre no alcanza: cada cambio en el diseño, aunque sea el valor de
`BUILD_ID`, produce otra ubicación y otro ruteo, y a 70 MHz el margen queda en décimas de
ns. Se implementó el diseño varias veces, con distintos `BUILD_ID` (que es como cambiar la
semilla):

| Diseño | Estrategia | WNS en cada ubicación (ns) |
|---|---|---|
| load desde WB | por defecto | +0,077, **−0,586** |
| load desde WB | `Performance_ExplorePostRoutePhysOpt` | +0,010, +0,104, +0,109 |
| load desde WB + flush sin esperar el chequeo de salto desalineado | `Performance_ExplorePostRoutePhysOpt` | +0,014, +0,197 |

Por eso `impl.tcl` usa **`Performance_ExplorePostRoutePhysOpt`**: más esfuerzo de
ubicación, replica los registros con mucho fanout y optimiza después del ruteo. La
implementación tarda un poco más (unos 4 minutos), y con la estrategia por defecto una de
dos ubicaciones fallaba. Se cambia con `TP4_IMPL_STRATEGY`.

El flush reescrito (ver `rtl/pipeline/riscv_pipeline.v`) es la misma lógica, escrita para
que no espere a la detección de un salto a una dirección desalineada: ese caso siempre
viene con un redirect, que ya vacía IF/ID e ID/EX. Saca 4 niveles de lógica del camino
crítico (de 17 a 13). Lo que queda es, sobre todo, ruteo: el 80 % del retardo.

Si una implementación no cierra, la capa `implementacion` falla: nunca se programa la placa
con un bitstream que no pasó el STA.

### Historia: de 50 a 70 MHz

El diseño anterior adelantaba a EX, desde MEM, el dato leído de la dmem. Su barrido dio:

| Frecuencia | WNS (ns) | Resultado |
|---|---|---|
| 50 MHz | +0,106 | PASS |
| 50,31 a 52,29 MHz (pasos de un divisor del MMCM) | +0,1 a +0,7 | PASS |
| 60 MHz | −0,531 | FAIL |

El barrido fino se descartó (un 5 % no justifica cambiar la frecuencia), pero mostró dos
cosas: la estimación por el margen es pesimista (a 50 MHz estimaba 50,3 MHz y cerró hasta
52,29 MHz), y el margen varía mucho entre implementaciones (de +0,1 a +0,7 ns, sin relación
con la frecuencia).

A 60 MHz el camino crítico era la cadena completa de un load seguido de un salto que lo usa:

```
EX/MEM (alu_out) → dmem (RAM distribuida, lectura asíncrona) → forwarding → ALU
                 → branch_unit → flush_unit → reset de ID/EX
```

Ese forwarding sobraba: con el stall de load-use, la instrucción que usa un load llega a EX
cuando el load ya está en WB. Sacarlo no cambia ni un ciclo y saca a la dmem del camino:
de 50 a 70 MHz. La evaluación (y la otra opción, sacar el stall) está en
[`../README.md`](../README.md#variantes-probar-ideas-sin-vivado).

## Decisiones

**Sin simulación del netlist (post-síntesis ni post-implementación con timing).** La
simulación de netlist detecta diferencias entre cómo se simula y cómo se sintetiza el RTL,
pero solo en los escenarios del testbench: es evidencia, no certeza, y a 19200 baudios
tarda horas. Lo que detectaría ya lo cubren otras etapas: los avisos de Vivado sobre esos
patrones son fallos en `sintesis`, el timing lo prueba el STA para todos los caminos (más
que una simulación con timing), y la capa `placa` corre programas en el chip real y los
compara contra la simulación del RTL.

**La capa de bitstream es corta.** `write_bitstream` traduce la implementación ya ruteada,
y su propio DRC frena si hay un problema. La capa `bitstream` comprueba que parta de una
implementación verificada de la versión actual del hardware, que `write_bitstream` termine,
y deja el resultado en `build/bitstream/top_riscv.bit` con su `BUILD_ID`. Que la FPGA tenga
ese bitstream lo comprueba la capa `placa`, que lee `BUILD_ID` del dump.

**Vivado para la síntesis, y no Yosys con equivalencia formal.** Se evaluó sintetizar con
Yosys, probar formalmente que su netlist es equivalente al RTL, y usar Vivado solo para
place & route. La equivalencia daría certeza sobre la síntesis, pero:
- no cubre las optimizaciones que Vivado vuelve a hacer al implementar (`opt_design`,
  `phys_opt_design`), así que la garantía no es de punta a punta;
- el timing se prueba igual en los dos flujos (STA de Vivado);
- la síntesis de Yosys para Xilinx suele dar peor timing, y este diseño cierra a 70 MHz
  con muy poco margen: es probable que con Yosys no cierre, y el objetivo es la máxima
  frecuencia.

Estimación (de criterio, no medida) de la confianza en que el hardware hace lo que dice el RTL:

| | Vivado + chequeos | Yosys + equivalencia + Vivado P&R |
|---|---|---|
| la síntesis conserva el comportamiento | ~97 % | ~99,9 % (probado) |
| las optimizaciones de la implementación lo conservan | ~99 % | ~99 % |
| timing | ~99,9 % (STA) | ~99,9 % (STA) |
| cierra a 70 MHz | sí (medido) | ~30 % |

Con la capa `placa`, las dos quedan cerca del 99 % para los programas reales. Se puede
hacer una prueba de concepto de Yosys + equivalencia más adelante, sin cambiar el flujo,
y adoptarla si se prueba la equivalencia y cierra timing a la frecuencia elegida.
