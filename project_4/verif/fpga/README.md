# verif/fpga/ — síntesis, implementación y frecuencia máxima

Las etapas del flujo que necesitan Vivado: RTL → **síntesis → implementación** →
bitstream → placa. Se corren con `verif/run.sh fpga` (capas `sintesis` e
`implementacion`).

| Archivo | Qué hace |
|---|---|
| `create_project.tcl` | crea el proyecto de Vivado desde cero en `build/vivado/tp4.xpr` (no se versiona) |
| `synth.tcl` | sintetiza; recibe `BUILD_ID` y la frecuencia del MMCM por variables de entorno |
| `check_synth.py` | revisa el log de la síntesis contra el RTL |
| `synth_mutants.sh` | sintetiza un RTL con errores inyectados y comprueba que `check_synth.py` los detecte |
| `impl.tcl` | place & route y los reportes de STA, ruteo, DRC y metodología |
| `check_impl.py` | revisa esos reportes |
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

## Frecuencia máxima (`fmax.sh`)

Sintetiza e implementa el diseño a 60, 70, 80, 90 y 100 MHz, en ese orden, y se detiene en
la primera frecuencia que no pasa los chequeos de la implementación. Pasos más chicos no
valen la pena: solo interesa una mejora significativa sobre los 50 MHz que ya funcionan.
Cada punto se implementa, porque la estimación por el margen de setup
(1 / (período − WNS)) no alcanza: cada frecuencia produce otra ubicación y otro ruteo.

### Resultados

Primero se probó un barrido fino desde 50 MHz, en pasos de un divisor del MMCM (≈ 0,33 MHz),
y se lo detuvo en 52,29 MHz: todos los puntos cerraron timing.

| Frecuencia | WNS (ns) | WHS (ns) | Resultado |
|---|---|---|---|
| 50,00 MHz | +0,106 | +0,068 | PASS |
| 50,31 MHz | +0,151 | +0,037 | PASS |
| 50,63 MHz | +0,638 | +0,036 | PASS |
| 50,96 MHz | +0,109 | +0,067 | PASS |
| 51,28 MHz | +0,522 | +0,023 | PASS |
| 51,61 MHz | +0,716 | +0,018 | PASS |
| 51,95 MHz | +0,195 | +0,033 | PASS |
| 52,29 MHz | +0,184 | +0,049 | PASS |

Dos conclusiones:
- **la estimación por el margen es pesimista**: a 50 MHz el margen de +0,106 ns estimaba
  una Fmax de 50,3 MHz, y el diseño cerró hasta 52,29 MHz;
- **el margen varía mucho entre implementaciones** (de +0,1 a +0,7 ns, sin relación con
  la frecuencia): depende de cómo quedan la ubicación y el ruteo en cada corrida.

Se descartó seguir así: una mejora del 5 % no justifica cambiar la frecuencia. El barrido
pasó a pasos de 10 MHz:

| Frecuencia | WNS (ns) | WHS (ns) | Resultado |
|---|---|---|---|
| 60 MHz | −0,531 | +0,033 | FAIL |

**El sistema se queda en 50 MHz.** A 60 MHz faltan 0,53 ns: el camino crítico tarda
16,45 ns y el período es de 16,67 ns (sin contar el margen que exige el reloj). Ese camino
es la cadena completa de un load seguido de un salto que lo usa:

```
EX/MEM (alu_out) → dmem (RAM distribuida, lectura asíncrona) → forwarding → ALU
                 → branch_unit → flush_unit → reset de ID/EX
```

Son 20 niveles de lógica, y el 76 % del retardo es ruteo. Para una mejora significativa
habría que cortar ese camino en el RTL, por ejemplo con una lectura sincrónica de la dmem
o resolviendo los saltos una etapa más tarde. Eso cambia el pipeline (y su CPI), así que no
es un ajuste de frecuencia sino un rediseño, y queda fuera de esta etapa.

## Decisiones

**Sin simulación del netlist (post-síntesis ni post-implementación con timing).** La
simulación de netlist detecta diferencias entre cómo se simula y cómo se sintetiza el RTL,
pero solo en los escenarios del testbench: es evidencia, no certeza, y a 19200 baudios
tarda horas. Lo que detectaría ya lo cubren otras etapas: los avisos de Vivado sobre esos
patrones son fallos en `sintesis`, el timing lo prueba el STA para todos los caminos (más
que una simulación con timing), y la capa `placa` corre programas en el chip real y los
compara contra la simulación del RTL.

**Sin capa de bitstream.** `write_bitstream` traduce la implementación ya ruteada, y su
propio DRC frena si hay un problema. La trazabilidad (que el bitstream corresponda a un
commit) la verifica la capa `placa`, que lee `BUILD_ID` del dump y lo compara con el commit.
El bitstream se genera al programar la placa (`verif/placa/program.tcl` o la GUI).

**Vivado para la síntesis, y no Yosys con equivalencia formal.** Se evaluó sintetizar con
Yosys, probar formalmente que su netlist es equivalente al RTL, y usar Vivado solo para
place & route. La equivalencia daría certeza sobre la síntesis, pero:
- no cubre las optimizaciones que Vivado vuelve a hacer al implementar (`opt_design`,
  `phys_opt_design`), así que la garantía no es de punta a punta;
- el timing se prueba igual en los dos flujos (STA de Vivado);
- la síntesis de Yosys para Xilinx suele dar peor timing, y este diseño cierra a 50 MHz
  con muy poco margen: es probable que con Yosys no cierre, y el objetivo es la máxima
  frecuencia.

Estimación (de criterio, no medida) de la confianza en que el hardware hace lo que dice el RTL:

| | Vivado + chequeos | Yosys + equivalencia + Vivado P&R |
|---|---|---|
| la síntesis conserva el comportamiento | ~97 % | ~99,9 % (probado) |
| las optimizaciones de la implementación lo conservan | ~99 % | ~99 % |
| timing | ~99,9 % (STA) | ~99,9 % (STA) |
| cierra a 50 MHz | sí (medido) | ~30 % |

Con la capa `placa`, las dos quedan cerca del 99 % para los programas reales. Se puede
hacer una prueba de concepto de Yosys + equivalencia más adelante, sin cambiar el flujo,
y adoptarla si se prueba la equivalencia y cierra timing a la frecuencia elegida.
