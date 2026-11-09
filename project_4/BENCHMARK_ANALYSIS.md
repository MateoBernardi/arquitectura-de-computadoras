# Análisis de Rendimiento del Procesador RV32I (Pipeline de 5 Etapas)

Este documento presenta el análisis cuantitativo y cualitativo del procesador RISC-V implementado en `project_4`, evaluado mediante la ejecución en simulación y hardware de un programa de referencia conocido (**Criba de Eratóstenes**).

---

## 1. Ficha Técnica de la Arquitectura Implementada

| Parámetro | Valor / Característica |
|---|---|
| **Conjunto de Instrucciones** | RISC-V **RV32I** base (entero de 32 bits, 32 registros `x0..x31`) |
| **Microarquitectura** | Pipeline clásico de **5 etapas** (`IF`, `ID`, `EX`, `MEM`, `WB`) |
| **Frecuencia de Operación ($f_{clk}$)** | **50 MHz** (generado internamente mediante MMCM a partir de los 100 MHz de la Nexys4 DDR) |
| **Periodo de Reloj ($T_{clk}$)** | **20.0 ns** |
| **Resolución de Saltos** | En etapa **EX** ([`branch_unit.v`](project_4.srcs/sources_1/new/pipeline/3_execute/branch_unit.v)) con predicción estática *Predict-Not-Taken* |
| **Penalización por Salto Tomado** | **2 ciclos** (vaciado / *flush* de etapas `IF` e `ID`) |
| **Resolución de Dependencias RAW** | Reenvío de datos en hardware (*Forwarding*) desde `EX/MEM` y `MEM/WB` a `EX` |
| **Riesgo de Carga (Load-Use Hazard)** | Congelamiento de **1 ciclo** (*stall*) mediante [`hazard_unit.v`](project_4.srcs/sources_1/new/pipeline/flow/hazard_unit.v) |
| **Memorias** | Harvard: `imem` (1 KB = 256 instrs), `dmem` (1 KB = 256 palabras) |

---

## 2. Programa de Prueba: Criba de Eratóstenes (`criba.s`)

Se ejecutó el algoritmo clásico para marcar números primos entre $2$ y $31$ en las primeras 32 posiciones de la memoria de datos `dmem`:
* `dmem[k] = 0` $\rightarrow$ Número **Primo**.
* `dmem[k] = 1` $\rightarrow$ Número **Compuesto**.

El algoritmo involucra inicialización, lectura/escritura en memoria, bucles anidados con saltos hacia atrás y bifurcaciones condicionales para saltar números no primos.

---

## 3. Resultados Globales de Rendimiento

| Métrica | Símbolo / Fórmula | Valor Medido | Observaciones |
|---|---|---|---|
| **Instrucciones Retiradas** | $N_{inst}$ | **322** | Instrucciones útiles ejecutadas hasta `ebreak` |
| **Ciclos de Reloj Totales** | $CC$ | **457 ciclos** | Medidos en simulación exacta y en hardware real |
| **Tiempo de Ejecución** | $T_{ejec} = CC \times T_{clk}$ | **$9.140\ \mu\text{s}$** | $457 \times 20\text{ ns}$ a $50\text{ MHz}$ |
| **Ciclos por Instrucción** | $CPI = CC / N_{inst}$ | **1.419** | Desvío respecto al ideal ($1.0$) debido a riesgos |
| **Instrucciones por Ciclo** | $IPC = 1 / CPI$ | **0.705** | Throughput promedio del pipeline |

---

## 4. Desglose de Instrucciones (*Instruction Mix*)

Del total de $322$ instrucciones ejecutadas dinámicamente:

```
[████████████████████] 50.3% ALU (Aritméticas / Lógicas / Inmediatos)
[████████            ] 19.3% Memoria (60 SW, 2 LW)
[████████            ] 21.4% Branches condicionales (69 instrucciones)
[███                 ]  8.7% Saltos incondicionales (28 JAL/J)
[                    ]  0.3% Sistema (1 EBREAK)
```

| Tipo de Instrucción | Cantidad | Porcentaje (%) | Ejemplos en el código |
|---|---|---|---|
| **Operaciones ALU** | 162 | **50.3 %** | `addi`, `add`, `slli` |
| **Accesos a Memoria (Store)** | 60 | **18.6 %** | `sw` (inicialización y marcado de múltiplos) |
| **Accesos a Memoria (Load)** | 2 | **0.6 %** | `lw` (inspección de `dmem[i]`) |
| **Saltos Condicionales (Branches)** | 69 | **21.4 %** | `blt`, `bne`, `bge` |
| **Saltos Incondicionales (Jumps)** | 28 | **8.7 %** | `j` (retorno al inicio del `inner_loop`) |
| **Control / Sistema** | 1 | **0.3 %** | `ebreak` (detención y paso a `halt`) |
| **TOTAL** | **322** | **100.0 %** | |

---

## 5. Auditoría de Riesgos (*Hazards*) y Descomposición del CPI

El pipeline experimenta dos fuentes de degradación frente al caso ideal ($CPI_{ideal} \approx 1$):

### A. Riesgos de Control (Branch / Jump Penalties)
* **Redirecciones totales observadas:** **64 eventos**
  * Saltos incondicionales tomados (`j`): **28**
  * Saltos condicionales tomados (*branches taken*): **36**
  * Saltos condicionales no tomados (*branches not-taken*): **33**
* **Penalización por redirección:** Cada redirección se detecta en la etapa `EX`, obligando a la [`flush_unit.v`](project_4.srcs/sources_1/new/pipeline/flow/flush_unit.v) a descartar 2 instrucciones introducidas especulativamente en `IF` e `ID`.
* **Ciclos perdidos por saltos:** $64 \times 2 = \mathbf{128\text{ ciclos}}$ (**28.0% del tiempo total** de CPU).
* **Efectividad de la predicción estática (*Predict Not-Taken*):**
  $$\text{Precisión de predicción} = \frac{33 \text{ (not-taken)}}{69 \text{ (total branches)}} = \mathbf{47.8\%}$$

### B. Riesgos de Datos (Load-Use Stalls)
* **Load-Use stalls observados:** **4 eventos**
* **Causa:** En el bucle externo `outer_loop`, la instrucción `lw x4, 0(x3)` es seguida inmediatamente por la evaluación `bne x4, x0, next_i`. Al depender el salto del dato recién cargado de la memoria `dmem`, el hardware congela el pipeline durante 1 ciclo para que el dato llegue a tiempo a la etapa de ejecución.
* **Ciclos perdidos por memoria:** $4 \times 1 = \mathbf{4\text{ ciclos}}$ (**0.88% del tiempo total**).
* **Eficiencia del reenvío (*Forwarding*):** Gracias a la [`forward_unit.v`](project_4.srcs/sources_1/new/pipeline/flow/forward_unit.v), todas las dependencias RAW de tipo ALU $\rightarrow$ ALU y MEM $\rightarrow$ Store se resolvieron con costo **0 ciclos**.

### C. Reconciliación Exacta del CPI

$$\begin{aligned}
CC &= N_{inst} + \text{Penalización Saltos} + \text{Penalización Load-Use} + \text{Llenado Inicial} - \text{Fin} \\
457 &= 322 + (64 \times 2) + (4 \times 1) + 4 - 1 \\
457 &= 322 + 128 + 4 + 3 = \mathbf{457\text{ ciclos (100\% coincidencia)}}
\end{aligned}$$

Descomposición analítica del CPI:
$$CPI = 1.000\text{ (base)} + 0.398\text{ (saltos)} + 0.012\text{ (load-use)} + 0.009\text{ (latencia inicial)} = \mathbf{1.419}$$

---

## 6. Verificación Funcional

La memoria `dmem` arrojó el siguiente vector de estado final:

| Posición `dmem[k]` | Valor | Clasificación | Correctitud |
|---|---|---|---|
| `dmem[2]` | `0` | **PRIMO** | Correcto |
| `dmem[3]` | `0` | **PRIMO** | Correcto |
| `dmem[4]` | `1` | Compuesto ($2 \times 2$) | Correcto |
| `dmem[5]` | `0` | **PRIMO** | Correcto |
| `dmem[6]` | `1` | Compuesto ($2 \times 3$) | Correcto |
| `dmem[7]` | `0` | **PRIMO** | Correcto |
| `dmem[8..10]` | `1` | Compuestos | Correcto |
| `dmem[11]` | `0` | **PRIMO** | Correcto |
| `dmem[12]` | `1` | Compuesto | Correcto |
| `dmem[13]` | `0` | **PRIMO** | Correcto |
| `dmem[14..16]` | `1` | Compuestos | Correcto |
| `dmem[17]` | `0` | **PRIMO** | Correcto |
| `dmem[18]` | `1` | Compuesto | Correcto |
| `dmem[19]` | `0` | **PRIMO** | Correcto |
| `dmem[20..22]` | `1` | Compuestos | Correcto |
| `dmem[23]` | `0` | **PRIMO** | Correcto |
| `dmem[24..28]` | `1` | Compuestos | Correcto |
| `dmem[29]` | `0` | **PRIMO** | Correcto |
| `dmem[30]` | `1` | Compuesto | Correcto |
| `dmem[31]` | `0` | **PRIMO** | Correcto |

**Resultado:** El 100% de los números primos en el rango $[2, 31]$ fueron identificados sin falsos positivos ni falsos negativos.

---

## 7. Conclusiones Arquitectónicas

A partir de las mediciones cuantitativas y de la auditoría de riesgos se derivan cinco conclusiones fundamentales de arquitectura de computadoras:

### A. Rendimiento Real vs. Ideal (El Impacto del Pipeline)
* **El límite teórico:** Un procesador pipelined ideal promete completar una instrucción por ciclo de reloj ($CPI_{ideal} = 1.0$).
* **La realidad del cómputo:** En un algoritmo real con bifurcaciones y dependencias como la Criba, el CPI medido fue de **1.419**, alcanzando un rendimiento efectivo de **$IPC = 0.705$**.
* **Diagnóstico:** El núcleo opera efectivamente al **70.5% de su capacidad teórica máxima**. El 29.5% del tiempo restante se pierde en ciclos de inactividad (burbujas y flushes) introducidos para preservar la consistencia de los datos y el control.

### B. El Cuello de Botella Principal: Riesgos de Control (Branch Penalties)
* **Concentración del costo:** De los 135 ciclos consumidos por penalizaciones de pipeline, **128 ciclos (el 94.8% del tiempo de penalización)** se debieron exclusivamente a saltos tomados.
* **Causa microarquitectónica:** Los saltos se resuelven en la etapa **`EX`** (la tercera etapa del cauce). La CPU adopta una predicción estática simple *Predict-Not-Taken*. Cada vez que la condición se cumple o se ejecuta un salto incondicional (`j`), la [`flush_unit.v`](project_4.srcs/sources_1/new/pipeline/flow/flush_unit.v) debe vaciar las 2 instrucciones que ya estaban ingresando por `IF` e `ID`.
* **Lección de diseño:** Si se buscara acelerar este diseño en una siguiente versión, la optimización con mayor impacto no radica en acelerar la ALU ni la memoria, sino en:
  1. **Adelantar la evaluación de saltos a la etapa `ID`**, lo que reduciría la penalización de 2 ciclos a 1 solo ciclo (ahorrando 64 ciclos, una mejora de velocidad directa de $\sim 14\%$).
  2. Implementar una tabla de **predicción dinámica de saltos** (por ejemplo, Branch Target Buffer o contadores saturados de 2 bits).

### C. Validación y Eficacia del Mecanismo de Reenvío (*Forwarding*)
* **Densidad de dependencias:** Más del **50% de las instrucciones** del programa dependen del resultado producido por la instrucción inmediatamente anterior (como `addi x2, x2, 1` seguido de `blt x2, x1`, o `slli` seguido de `sw`).
* **Sin forwarding:** Cada una de esas dependencias obligaría a detener el cauce durante 2 ciclos hasta que el dato pasara por la etapa `WB` y se escribiera en el banco de registros, lo que habría elevado la ejecución a más de 700 ciclos ($CPI > 2.2$).
* **Conclusión:** La [`forward_unit.v`](project_4.srcs/sources_1/new/pipeline/flow/forward_unit.v) resolvió todas las dependencias RAW de tipo ALU $\rightarrow$ ALU y MEM $\rightarrow$ Store con **costo cero**. Esto confirma que el reenvío de datos en hardware es la técnica microarquitectónica de mayor retorno de inversión en procesadores *in-order*.

### D. Riesgos de Memoria (*Load-Use Hazard*) y el Rol del Compilador
* **Baja incidencia de memoria:** A lo largo de toda la corrida solo ocurrieron **4 stalls por riesgo de carga** (generados por el chequeo `lw x4, 0(x3)` seguido de `bne x4, x0, next_i` en el bucle principal).
* **Interacción Hardware-Software:** Aunque la [`hazard_unit.v`](project_4.srcs/sources_1/new/pipeline/flow/hazard_unit.v) congeló correctamente el cauce 1 ciclo para evitar un dato corrupto, este caso pone en evidencia la importancia de la optimización del compilador: un compilador con *instruction scheduling* inteligente podría haber intercalado una instrucción independiente (por ejemplo, el incremento de índice o la preparación de una constante) entre el `lw` y el `bne`, eliminando esos 4 stalls sin modificar el hardware.

### E. Robustez y Determinismo del Hardware
* **Consistencia matemática:** La ecuación teórica de ciclos ($CC = N_{inst} + 2 \times N_{taken} + 1 \times N_{stall} + 3$) predijo exactamente los **457 ciclos** observados en la simulación y en hardware.
* **Conclusión:** El procesador no sufre de *deadlocks*, carreras de reloj, problemas de sincronismo ni burbujas espurias. El comportamiento temporal es 100% determinístico y verificado.

---

## 8. Verificación y Ejecución en la Placa FPGA (Nexys4 DDR)

Para corroborar las mediciones de simulación sobre el silicio real, se utilizó el script automatizado [`host/benchmark_runner.py`](host/benchmark_runner.py). El script ensambla el código, lo carga vía UART, avanza el core ciclo a ciclo mediante comandos `step` (pulso de `cpu_enable` de exactamente un ciclo) hasta el `ebreak`, y finalmente realiza un volcado de registros y de la memoria de datos `dmem`.

### Corrida Experimental en Hardware

```bash
mateo@mateo-HP-Laptop-15-da0xxx:~/facu/arquitectura-de-computadoras/project_4$ python3 host/benchmark_runner.py --port /dev/ttyUSB1
===========================================================
 Benchmarking en Hardware: RISC-V RV32I (5 Etapas)
 Puerto: /dev/ttyUSB1 | Baud: 19200 | Frecuencia: 50.0 MHz
===========================================================
[1/4] Ensamblando 'host/criba.s'...
      OK -> 21 instrucciones en binario.
[2/4] Abriendo puerto serie en /dev/ttyUSB1...
[3/4] Reseteando CPU y cargando programa...
[4/4] Ejecutando y contando ciclos de reloj en hardware...
      Progreso: 400 ciclos...
      HALT alcanzado exitosamente en 457 ciclos.

Leyendo volcado de depuración (dump)...

===========================================================
 REPORTE FINAL DE RENDIMIENTO (HARDWARE REAL)
===========================================================
  Ciclos Totales (CC)           : 457
  Instrucciones Dinámicas       : 322
  Tiempo de Ejecución del Core  : 9.140 us (9140.0 ns)
  CPI (Ciclos por Instrucción)  : 1.419
  IPC (Instrucciones por Ciclo) : 0.705
  Tiempo de comunicación UART   : 7.33 s
===========================================================

Verificación de Primos en DMEM[2..31]:
  Primos detectados     : [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31]
  Primos teóricos       : [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31]
  -> RESULTADO: CORRECTO (100% de coincidencia funcional)
```

### Comparativa: Simulación vs. Hardware Real

| Parámetro | Simulación Vivado (XSIM) | Hardware Real (Nexys4 DDR) | Discrepancia |
|---|---|---|---|
| **Ciclos de Reloj ($CC$)** | **457** | **457** | **0 ciclos (0.00 %)** |
| **Tiempo de Ejecución del Core** | **$9.140\ \mu\text{s}$** | **$9.140\ \mu\text{s}$** | **0.00 %** |
| **CPI** | **1.419** | **1.419** | **0.00 %** |
| **IPC** | **0.705** | **0.705** | **0.00 %** |
| **Resultado Funcional** | 100% primos detectados | 100% primos detectados | Coincidencia exacta |

> [!NOTE]
> **Observación sobre la latencia de depuración:**
> El tiempo de ejecución real del procesador a 50 MHz fue de apenas **$9.140\ \mu\text{s}$**, mientras que el tiempo total de comunicación UART para enviar los 457 pasos individuales fue de **$7.33\text{ s}$**. Esto evidencia empíricamente la necesidad de contar ciclos en hardware o mediante pasos unitarios: medir el tiempo de ejecución desde el sistema operativo en la PC por UART habría reportado un tiempo casi un millón de veces mayor, dominado puramente por la latencia de transmisión serie y buffers del host.

---

## 9. Experimento 1: Optimización por Software (Instruction Scheduling)

### A. Diagnóstico del Cuello de Botella
En la versión original (`criba.s`), el bucle principal contenía la siguiente secuencia:
```assembly
outer_loop:
        slli x3, x2, 2
        lw   x4, 0(x3)          # Etapa MEM lee dmem[i]
        bne  x4, x0, next_i     # <- STALL: bne en ID necesita x4 de inmediato
```
Como el dato recién está disponible al final de la etapa `MEM`, no puede reenviarse a tiempo a la etapa `EX` en el ciclo inmediato posterior. Por lo tanto, la [`hazard_unit.v`](project_4.srcs/sources_1/new/pipeline/flow/hazard_unit.v) congela el cauce forzando **1 burbuja de espera** (*stall*) en cada una de las 4 iteraciones del bucle exterior ($i = 2, 3, 4, 5$).

### B. Técnica Aplicada: Reordenamiento de Instrucciones
Se reordenó el código en [`host/criba_opt.s`](host/criba_opt.s) intercalando una instrucción útil e independiente (`addi x8, x0, 6`, que fija el límite de corte y originalmente estaba dentro de `next_i`) entre la carga `lw` y la evaluación condicional `bne`:

```assembly
outer_loop:
        slli x3, x2, 2
        lw   x4, 0(x3)          # Carga de memoria en x4
        addi x8, x0, 6          # <--- INSTRUCTION SCHEDULING (independiente!)
        bne  x4, x0, next_i     # Ahora lw ya pasó a WB; reenvío con costo 0
```
Al separar el `lw` del `bne` por un ciclo, el dato se reenvía a través de la [`forward_unit.v`](project_4.srcs/sources_1/new/pipeline/flow/forward_unit.v) desde `MEM/WB` hacia `EX` **sin detener el procesador**.

### C. Resultados Experimentales (Simulación Vivado XSIM)

```
halt after 453 cycles
-------------------------------------------
Rendimiento del Benchmark (Criba Optimizada):
  Ciclos Totales (CC) : 453
  Load-Use Stalls     : 0
  Branch Flushes      : 64
-------------------------------------------
Contenido de dmem[2..31]:
  dmem[2] = 0  <-- PRIMO
  dmem[3] = 0  <-- PRIMO
  ...
  dmem[31] = 0  <-- PRIMO
```

### D. Comparativa de Rendimiento: Original vs. Optimizado

| Métrica | Versión Base (`criba.s`) | Versión Optimizada (`criba_opt.s`) | Ganancia / Variación |
|---|---|---|---|
| **Instrucciones Dinámicas ($N_{inst}$)** | 322 | 322 | 0 (igual cantidad de trabajo) |
| **Burbujas Load-Use (Stalls)** | **4** | **0** | **-100.0 % (eliminados)** |
| **Redirecciones de Salto (Flushes)** | 64 | 64 | Idéntico comportamiento |
| **Ciclos Totales ($CC$)** | **457** | **453** | **-4 ciclos ganados** |
| **Tiempo de Ejecución a 50 MHz** | **$9.140\ \mu\text{s}$** | **$9.060\ \mu\text{s}$** | **Aceleración neta** |
| **CPI** | **1.419** | **1.407** | **Mejora del 0.85 %** |
| **IPC** | **0.705** | **0.711** | **+0.85 % mayor throughput** |
| **Resultado Funcional** | 100% primos | 100% primos | Sin alteración funcional |

### E. Conclusión del Experimento
Este experimento demuestra empíricamente uno de los principios rectores de la arquitectura RISC: **la sinergia entre hardware y compilador**. El procesador no necesitó lógica de hardware adicional; bastó con que el compilador aplicara una técnica estándar de *Instruction Scheduling* para llenar la ranura de retardo de carga (*load delay slot*) con trabajo útil, eliminando por completo los ciclos ociosos del cauce.

### F. Validación en la Placa FPGA (Nexys4 DDR)

Se ejecutó la versión optimizada en la placa mediante `benchmark_runner.py`:

```bash
mateo@mateo-HP-Laptop-15-da0xxx:~/facu/arquitectura-de-computadoras/project_4$ python3 host/benchmark_runner.py --port /dev/ttyUSB1 --asm host/criba_opt.s
===========================================================
 Benchmarking en Hardware: RISC-V RV32I (5 Etapas)
 Puerto: /dev/ttyUSB1 | Baud: 19200 | Frecuencia: 50.0 MHz
===========================================================
[1/4] Ensamblando 'host/criba_opt.s'...
      OK -> 21 instrucciones en binario.
[2/4] Abriendo puerto serie en /dev/ttyUSB1...
[3/4] Reseteando CPU y cargando programa...
[4/4] Ejecutando y contando ciclos de reloj en hardware...
      Progreso: 400 ciclos...
      HALT alcanzado exitosamente en 453 ciclos.

Leyendo volcado de depuración (dump)...

===========================================================
 REPORTE FINAL DE RENDIMIENTO (HARDWARE REAL)
===========================================================
  Ciclos Totales (CC)           : 453
  Instrucciones Dinámicas       : 322
  Tiempo de Ejecución del Core  : 9.060 us (9060.0 ns)
  CPI (Ciclos por Instrucción)  : 1.407
  IPC (Instrucciones por Ciclo) : 0.711
  Tiempo de comunicación UART   : 7.26 s
===========================================================

Verificación de Primos en DMEM[2..31]:
  Primos detectados     : [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31]
  Primos teóricos       : [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31]
  -> RESULTADO: CORRECTO (100% de coincidencia funcional)
```

La medición en hardware físico corrobora al **100.0%** (0 ciclos de discrepancia) la eliminación de los 4 ciclos de *stall*, operando a $9.060\ \mu\text{s}$.

---

## 10. Experimento 2: Desenrollado de Bucles (*Loop Unrolling* — Factor 2)

### A. Diagnóstico del Cuello de Botella
En la versión base y la optimizada, el bucle `init_loop` inicializaba las 30 palabras de memoria (`i = 2..31`) de forma estrictamente secuencial:
```assembly
init_loop:                      # 30 iteraciones
        slli x3, x2, 2
        sw   x0, 0(x3)
        addi x2, x2, 1
        blt  x2, x1, init_loop  # 29 branches tomados -> 58 ciclos de flush!
```
En cada iteración, el salto condicional `blt` se toma 29 veces. Como cada salto tomado descarga 2 instrucciones en `EX`, **solo la sobrecarga de control de `init_loop` consume 58 ciclos de reloj**.

### B. Técnica Aplicada: Desenrollado por Factor 2
En [`host/criba_unroll.s`](host/criba_unroll.s) se desenrolló el bucle por un factor de 2, escribiendo dos posiciones contiguas de memoria (`dmem[i]` y `dmem[i+1]`) por cada evaluación de condición:

```assembly
init_loop:                      # 15 iteraciones (Factor 2)
        slli x3, x2, 2
        sw   x0, 0(x3)          # dmem[i] = 0
        sw   x0, 4(x3)          # dmem[i+1] = 0
        addi x2, x2, 2          # i += 2
        blt  x2, x1, init_loop  # Ahora solo 14 saltos tomados (28 ciclos de flush!)
```

### C. Resultados Experimentales (Simulación Vivado XSIM)

```
halt after 378 cycles
-------------------------------------------
Rendimiento del Benchmark (Criba Unroll x2):
  Ciclos Totales (CC) : 378
  Load-Use Stalls     : 0
  Branch Flushes      : 49
-------------------------------------------
Contenido de dmem[2..31]:
  dmem[2] = 0  <-- PRIMO
  dmem[3] = 0  <-- PRIMO
  ...
  dmem[31] = 0  <-- PRIMO
```

### D. Tabla Comparativa Integral de los Tres Enfoques

| Métrica de Rendimiento | 1. Base (`criba.s`) | 2. Instruction Sched. (`criba_opt.s`) | 3. Unroll x2 (`criba_unroll.s`) | Ganancia Acumulada |
|---|---|---|---|---|
| **Tamaño Binario (Instrucciones estáticas)** | 21 instrs | 21 instrs | **22 instrs** | +4.7% tamaño en `imem` |
| **Instrucciones Dinámicas Retiradas ($N_{inst}$)** | 322 | 322 | **277** | **-14.0% instrucciones** |
| **Burbujas Load-Use (Stalls)** | 4 | **0** | **0** | **-100% (eliminadas)** |
| **Redirecciones de Salto (Flushes)** | 64 | 64 | **49** | **-23.4% flushes** |
| **Ciclos Totales de Reloj ($CC$)** | **457** | **453** | **378** | **-79 ciclos (-17.3%)** |
| **Tiempo de Ejecución (a 50 MHz)** | **$9.140\ \mu\text{s}$** | **$9.060\ \mu\text{s}$** | **$7.560\ \mu\text{s}$** | **Aceleración de 1.21x** |
| **CPI (Ciclos por Instrucción)** | 1.419 | 1.407 | **1.365** | **Mejora del 3.8%** |
| **IPC (Instrucciones por Ciclo)** | 0.705 | 0.711 | **0.733** | **+3.9% throughput** |
| **Funcionalidad** | 100% correcta | 100% correcta | 100% correcta | Sin degradación |

### E. Conclusión Arquitectónica del Experimento
El desenrollado de bucles ilustra el **compromiso clásico Tiempo vs. Espacio (*Space-Time Tradeoff*)**:
* Se pagó un costo marginal de **1 instrucción adicional en la memoria de instrucciones `imem`** (de 21 a 22 palabras).
* A cambio, se eliminaron **45 instrucciones dinámicas** y **15 vaciados de pipeline**, logrando una **reducción de 75 ciclos adicionales** y llevando el tiempo total a **$7.560\ \mu\text{s}$**.

### F. Validación en la Placa FPGA (Nexys4 DDR)

Se ejecutó la versión con *Loop Unrolling* en la placa mediante `benchmark_runner.py`:

```bash
mateo@mateo-HP-Laptop-15-da0xxx:~/facu/arquitectura-de-computadoras/project_4$ python3 host/benchmark_runner.py --port /dev/ttyUSB1 --asm host/criba_unroll.s
===========================================================
 Benchmarking en Hardware: RISC-V RV32I (5 Etapas)
 Puerto: /dev/ttyUSB1 | Baud: 19200 | Frecuencia: 50.0 MHz
===========================================================
[1/4] Ensamblando 'host/criba_unroll.s'...
      OK -> 22 instrucciones en binario.
[2/4] Abriendo puerto serie en /dev/ttyUSB1...
[3/4] Reseteando CPU y cargando programa...
[4/4] Ejecutando y contando ciclos de reloj en hardware...
      Progreso: 300 ciclos...
      HALT alcanzado exitosamente en 378 ciclos.

Leyendo volcado de depuración (dump)...

===========================================================
 REPORTE FINAL DE RENDIMIENTO (HARDWARE REAL)
===========================================================
  Ciclos Totales (CC)           : 378
  Instrucciones Dinámicas       : 277
  Tiempo de Ejecución del Core  : 7.560 us (7560.0 ns)
  CPI (Ciclos por Instrucción)  : 1.365
  IPC (Instrucciones por Ciclo) : 0.733
  Tiempo de comunicación UART   : 6.06 s
===========================================================

Verificación de Primos en DMEM[2..31]:
  Primos detectados     : [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31]
  Primos teóricos       : [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31]
  -> RESULTADO: CORRECTO (100% de coincidencia funcional)
```

Nuevamente, el silicio físico reproduce **al ciclo exacto (378 ciclos, 0.00% de error)** las predicciones de la simulación y de la microarquitectura del cauce.

---

## 11. Experimento 3: Análisis de Timing Físico, Camino Crítico y Frecuencia Máxima ($f_{max}$)

Para evaluar los límites físicos de la microarquitectura en la FPGA Xilinx Artix-7 (`xc7a100tcsg324-1` de la Nexys4 DDR), se analizó el reporte de cierre temporal post-ruteo de Vivado (`top_riscv_timing_summary_routed.rpt`) al configurar el procesador con el reloj directo de placa a **100.0 MHz** (`period = 10.000 ns`).

### A. Resumen General de Timing (Post-Route)

| Parámetro de Timing | Valor Medido | Estado / Diagnóstico |
|---|---|---|
| **Reloj Objetivo (`sys_clk_pin`)** | 100.000 MHz ($T_{req} = 10.000\text{ ns}$) | Restricción impuesta en el `.xdc` |
| **Worst Negative Slack (WNS)** | **-4.592 ns** | **VIOLACIÓN DE SETUP** (Timing no cierra a 100 MHz) |
| **Total Negative Slack (TNS)** | **-1328.405 ns** | Suma de todas las violaciones del diseño |
| **Puntos Finales Fallidos** | **421 endpoints** (de 9617) | 4.38% de los caminos no cumplen el tiempo |
| **Worst Hold Slack (WHS)** | **+0.080 ns** | **CUMPLIDO** (Sin problemas de retención / hold) |
| **Total Hold Slack (THS)** | **0.000 ns** | 0 fallas de hold |
| **Worst Pulse Width Slack (WPWS)** | **+3.750 ns** | **CUMPLIDO** (Ancho de pulso válido) |

### B. Anatomía del Camino Crítico (*Critical Path*)

El reporte de temporización identificó el camino combinacional más largo del procesador:

* **Punto de inicio (*Startpoint*):** `u_cpu/u_ex_mem/mem_alu_out_reg[2]/C` (etapa `EX/MEM`).
* **Punto de destino (*Endpoint*):** `u_cpu/u_id_ex/ex_pc_reg[7]/R` (pin de reset sincrónico de la etapa `ID/EX`).
* **Retardo total de datos (*Data Path Delay*):** **13.986 ns**
  * **Retardo lógico:** 3.860 ns (27.60 %)
  * **Retardo de ruteo (*net routing*):** 10.126 ns (72.40 %)
* **Niveles de lógica atravesados:** **20 niveles combinacionales en un solo ciclo de reloj**:
  `RAMD64E` (1) $\to$ `MUXF7` (1) $\to$ `LUT3` (2) $\to$ `LUT6` (10) $\to$ `LUT2` (1) $\to$ `CARRY4` (5).

```
[EX/MEM Reg]
      │ (mem_alu_out: dirección)
      ▼
┌──────────────┐
│  dmem asínc  │  Lectura combinacional de memoria de datos (RAM distribuida)
└──────┬───────┘
      │ (wb_result / mem_rdata)
      ▼
┌──────────────┐
│ Forward Mux  │  Multiplexor de reenvío hacia la entrada de la ALU en EX
└──────┬───────┘
      │ (alu_b)
      ▼
┌──────────────┐
│  ALU (EX)    │  Operación de resta y generación del flag Zero (5 niveles CARRY4)
└──────┬───────┘
      │ (alu_zero)
      ▼
┌──────────────┐
│ Branch Unit  │  Evaluación de la condición de salto (branch_taken / redirect)
└──────┬───────┘
      │ (redirect)
      ▼
┌──────────────┐
│  Flush Unit  │  Generación de la señal de vaciado combinacional (flush_id_ex)
└──────┬───────┘
      │ (reset sincrónico)
      ▼
[ID/EX Reg (R)]  Reset sincrónico de los registros de pipeline
```

### C. Cálculo de la Frecuencia Máxima de Operación ($f_{max}$)

El retardo acumulado del camino crítico determina el periodo mínimo de reloj ($T_{min}$) que físicamente admite el circuito:

$$T_{min} = T_{clk} - WNS = 10.000\text{ ns} - (-4.592\text{ ns}) = \mathbf{14.592\text{ ns}}$$

A partir del periodo mínimo, se calcula la frecuencia de corte:

$$f_{max} = \frac{1}{T_{min}} = \frac{1}{14.592\text{ ns}} \approx \mathbf{68.53\text{ MHz}}$$

### D. Justificación de la Elección de 50 MHz (`USE_MMCM = 1`)

Con $f_{max} \approx 68.53\text{ MHz}$, la frecuencia nativa de la placa (100 MHz) excede la capacidad del circuito en más de un 45%. 
Por ello, la inclusión del MMCM en [`top_riscv.v`](top_riscv.v) para generar **50.0 MHz** ($T_{clk} = 20.0\text{ ns}$) es una decisión de diseño fundamental:
* A 50 MHz, el tiempo disponible ($20.0\text{ ns}$) holgadamente supera los $14.59\text{ ns}$ del camino crítico.
* El margen de seguridad (*Slack positivo*) resultante es de aproximadamente $+5.4\text{ ns}$, garantizando un funcionamiento libre de metaestabilidad bajo variaciones de temperatura, tensión de alimentación y proceso en la FPGA.

### E. Utilización de Recursos del Silicio (Nexys4 DDR — `xc7a100tcsg324-1`)

El reporte de utilización post-placement (`top_riscv_utilization_placed.rpt`) muestra una ocupación muy eficiente:

| Recurso de la FPGA | Cantidad Utilizada | Cantidad Disponible | Porcentaje de Utilización (%) |
|---|---|---|---|
| **Slice LUTs totales** | 3.174 | 63.400 | **5.01 %** |
| *-- LUT como lógica pura* | 2.649 | 63.400 | 4.18 % |
| *-- LUT como memoria distribuida (RAM)* | 524 | 19.000 | 2.76 % |
| **Slice Registers (Flip-Flops)** | 1.686 | 126.800 | **1.33 %** |
| **Multiplexores F7 (MUXF7)** | 640 | 31.700 | **2.02 %** |
| **Multiplexores F8 (MUXF8)** | 128 | 15.850 | **0.81 %** |
| **Block RAMs (RAMB18/RAMB36)** | 0 | 135 | **0.00 %** (todo mapeado a LUTRAM) |
| **DSP48 Slices** | 0 | 240 | **0.00 %** (sin multiplicador hardware) |

### F. Conclusiones y Recomendaciones de Microarquitectura

1. **La causa raíz del camino crítico:** La arquitectura actual combina en un único lazo combinacional la lectura asíncrona de memoria de datos (`dmem`), el *forwarding*, la ejecución de la ALU, la decisión de salto condicional (`branch_unit`) y el disparo del vaciado (`flush_unit`).
2. **Cómo alcanzar los 100 MHz en futuras revisiones:**
   * **Opción A (Memoria Sincrónica):** Registrar la salida de `dmem` convirtiéndola en una lectura sincrónica de 1 ciclo de latencia (mapeándola a Block RAM nativa en vez de Distributed RAM).
   * **Opción B (Branch Register):** Registrar la señal de branch antes de activar los flushes, o trasladar la evaluación del branch a la etapa `ID` utilizando comparadores dedicados en lugar de la ALU completa.

---

## 12. Experimento 4: Riesgo de Lectura/Escritura Simultánea en el Banco de Registros (`BYPASS`)

### A. Fundamento Teórico: El Riesgo RAW a Distancia 3 (WB $\to$ ID)
En un cauce de 5 etapas, existe una condición de carrera sutil cuando una instrucción escribe un registro en la etapa **`WB`** (etapa 5) y otra instrucción intenta leer ese mismo registro en la etapa **`ID`** (etapa 2) en el **mismo ciclo de reloj**:

$$\text{Ciclo 5:} \quad [\text{Inst 1: WB}] \longleftrightarrow [\text{Inst 2: MEM}] \longleftrightarrow [\text{Inst 3: EX}] \longleftrightarrow [\text{Inst 4: ID}]$$

* El banco de registros (`regfile.v`) tiene **escritura sincrónica** (ocurre en el flanco ascendente del reloj).
* Por lo tanto, durante todo el Ciclo 5, las celdas internas de memoria `regs[rd]` aún contienen el **valor antiguo** (*stale data*).
* La [`forward_unit.v`](project_4.srcs/sources_1/new/pipeline/flow/forward_unit.v) solo puede reenviar datos desde las etapas inmediatamente anteriores (`EX/MEM` y `MEM/WB`). Cuando Inst 4 pasa a la etapa `EX` en el ciclo 6, Inst 1 ya abandonó el cauce (se retiró), por lo que **la red de reenvío no puede alcanzarla**.

### B. Programa de Prueba: `test_bypass.s`
Para aislar y hacer visible este fenómeno, se diseñó un programa con una dependencia RAW estricta de distancia 3 (2 instrucciones intermedias independientes):

```assembly
# test_bypass.s - Revela el riesgo WB -> ID
addi x1, x0, 100        # Inst 1: escribe x1 = 100 (estará en WB cuando Inst 4 esté en ID)
addi x3, x0, 1          # Inst 2: intermedia (en MEM cuando Inst 4 esté en ID)
addi x4, x0, 2          # Inst 3: intermedia (en EX cuando Inst 4 esté en ID)
add  x5, x1, x1         # Inst 4: lee x1 en ID (con distancia 3)
sw   x5, 0(x0)          # Guarda x5 en dmem[0]
ebreak                  # Fin
```

### C. Resultados Experimentales en Simulación (XSIM)

Se evaluó el comportamiento del procesador con el parámetro `BYPASS` de [`regfile.v`](project_4.srcs/sources_1/new/pipeline/2_decode/regfile.v) activado y desactivado:

| Parámetro en `riscv_pipeline.v` | Valor Leído de `x1` en ID | Cálculo de `x5 = x1 + x1` | Valor en `dmem[0]` | Estado Funcional |
|---|---|---|---|---|
| **`BYPASS = 1` (Write-Through activo)** | **`100`** | **`200`** | **`200`** | **CORRECTO** |
| **`BYPASS = 0` (Sin bypass interno)** | **`0` (valor viejo)** | **`0`** | **`0`** | **CORRUPCIÓN DE DATOS** |

### D. Salida de la Simulación Vivado

* **Con `BYPASS = 0`:**
  ```
  halt after 9 cycles
  x1 = 100, x5 = 0, dmem[0] = 0   <-- ¡FALLA! Lee el valor viejo de x1 en ID
  ```
* **Con `BYPASS = 1`:**
  ```
  halt after 9 cycles
  x1 = 100, x5 = 200, dmem[0] = 200 <-- ¡CORRECTO! Write-through cortocircuita wdata
  ```

### E. Conclusión de Arquitectura
El parámetro `BYPASS = 1` en [`regfile.v`](project_4.srcs/sources_1/new/pipeline/2_decode/regfile.v):
```verilog
assign rdata1 = (raddr1 == 5'd0) ? 32'd0 : (BYPASS && wr && waddr == raddr1) ? wdata : regs[raddr1];
```
implementa una ranura de cortocircuito interna (*write-through combinational bypass*). Sin este circuito, el procesador requeriría congelar el pipeline por 1 ciclo cada vez que ocurra una dependencia a distancia 3, o sufriría corrupción silenciosa de datos. Este experimento justifica la necesidad del bypass interno en la etapa de decodificación.

### F. Validación Experimental en la Placa FPGA (Nexys4 DDR)

Se ejecutó la prueba en hardware real sobre la placa Nexys4 DDR en dos condiciones consecutivas: primero con el bitstream estándar que incluye `BYPASS = 1`, y luego programando un bitstream con `BYPASS = 0` para observar el fallo físico en el silicio:

#### 1. Corrida en Hardware con `BYPASS = 1` (Circuito Correcto):
```bash
mateo@mateo-HP-Laptop-15-da0xxx:~/facu/arquitectura-de-computadoras/project_4$ python3 host/benchmark_runner.py --port /dev/ttyUSB1 --asm host/test_bypass.s
===========================================================
 Benchmarking en Hardware: RISC-V RV32I (5 Etapas)
 Puerto: /dev/ttyUSB1 | Baud: 19200 | Frecuencia: 50.0 MHz
===========================================================
[1/4] Ensamblando 'host/test_bypass.s'...
      OK -> 6 instrucciones en binario.
[2/4] Abriendo puerto serie en /dev/ttyUSB1...
[3/4] Reseteando CPU y cargando programa...
[4/4] Ejecutando y contando ciclos de reloj en hardware...

      HALT alcanzado exitosamente en 9 ciclos.

Leyendo volcado de depuración (dump)...

===========================================================
 REPORTE FINAL DE RENDIMIENTO (HARDWARE REAL)
===========================================================
  Ciclos Totales (CC)           : 9
  Instrucciones Dinámicas       : 6
  Tiempo de Ejecución del Core  : 0.180 us (180.0 ns)
  CPI (Ciclos por Instrucción)  : 1.500
  IPC (Instrucciones por Ciclo) : 0.667
  Tiempo de comunicación UART   : 0.16 s
===========================================================

Verificación del Experimento BYPASS (WB -> ID):
  Registro x1 (escrito por Inst 1) : 100
  Registro x5 (x1 + x1 en Inst 4)  : 200 (Esperado: 200 con BYPASS=1)
  Memoria dmem[0]                  : 200
  -> RESULTADO: CORRECTO (El bypass interno WB->ID funciona perfectamente en hardware)
```

#### 2. Corrida en Hardware con `BYPASS = 0` (Fallo Inducido en Silicio):
```bash
mateo@mateo-HP-Laptop-15-da0xxx:~/facu/arquitectura-de-computadoras/project_4$ python3 host/benchmark_runner.py --port /dev/ttyUSB1 --asm host/test_bypass.s
===========================================================
 Benchmarking en Hardware: RISC-V RV32I (5 Etapas)
 Puerto: /dev/ttyUSB1 | Baud: 19200 | Frecuencia: 50.0 MHz
===========================================================
[1/4] Ensamblando 'host/test_bypass.s'...
      OK -> 6 instrucciones en binario.
[2/4] Abriendo puerto serie en /dev/ttyUSB1...
[3/4] Reseteando CPU y cargando programa...
[4/4] Ejecutando y contando ciclos de reloj en hardware...

      HALT alcanzado exitosamente en 9 ciclos.

Leyendo volcado de depuración (dump)...

===========================================================
 REPORTE FINAL DE RENDIMIENTO (HARDWARE REAL)
===========================================================
  Ciclos Totales (CC)           : 9
  Instrucciones Dinámicas       : 6
  Tiempo de Ejecución del Core  : 0.180 us (180.0 ns)
  CPI (Ciclos por Instrucción)  : 1.500
  IPC (Instrucciones por Ciclo) : 0.667
  Tiempo de comunicación UART   : 0.16 s
===========================================================

Verificación del Experimento BYPASS (WB -> ID):
  Registro x1 (escrito por Inst 1) : 100
  Registro x5 (x1 + x1 en Inst 4)  : 0 (Esperado: 200 con BYPASS=1)
  Memoria dmem[0]                  : 0
  -> RESULTADO: FALLA (Lectura de dato antiguo en ID)
```

### G. Cuadro Comparativo: Simulación vs. Hardware Real

| Caso Evaluado | Valor Teórico / Esperado | Resultado en Simulación (XSIM) | Resultado en Silicio Real (FPGA) | Diagnóstico |
|---|---|---|---|---|
| **Con `BYPASS = 1`** | $x_5 = 200,\ dmem[0] = 200$ | $x_5 = 200,\ dmem[0] = 200$ | **$x_5 = 200,\ dmem[0] = 200$** | **100% Coincidencia (Éxito)** |
| **Con `BYPASS = 0`** | $x_5 = 0,\ dmem[0] = 0$ (error) | $x_5 = 0,\ dmem[0] = 0$ (error) | **$x_5 = 0,\ dmem[0] = 0$ (error)** | **Fallo confirmado en silicio** |

## 12. Experimento 4: Overflow a la memoria de instrucciones
### A. Validación Experimental en la Placa FPGA (Nexys4 DDR)
===========================================================
 Benchmarking en Hardware: RISC-V RV32I (5 Etapas)
 Puerto: /dev/ttyUSB1 | Baud: 19200 | Frecuencia: 50.0 MHz
===========================================================
[1/4] Ensamblando 'host/overflow_test.s'...
      OK -> 261 instrucciones en binario.
[2/4] Abriendo puerto serie en /dev/ttyUSB1...
[3/4] Reseteando CPU y cargando programa (261 instrucciones, límite: 256)...

  *** EXPERIMENTO DE DESBORDAMIENTO DE MEMORIA ***
  Programa: 261 instrucciones  |  imem: 256 palabras
  Excede la capacidad en: 5 instrucciones

  >>> RESPUESTA DE LA FPGA: E (RSP_ERR) <<<<
  Mensaje del protocolo: load: el programa no entra en la memoria de instrucciones

===========================================================
 REPORTE DEL EXPERIMENTO DE DESBORDAMIENTO
===========================================================
  Instrucciones enviadas  : 261
  Capacidad de imem       : 256 palabras
  Instrucciones rechazadas: 5
  Respuesta de la FSM     : E (RSP_ERR = 0x45)
  Estado del CPU          : Reset (en hold, no ejecutó nada)
  -> RESULTADO: CORRECTO (Protección de overflow funciona)
===========================================================

> [!IMPORTANT]
> **Importancia Pedagógica del Experimento:**
> Este experimento confirma de forma tangible e indiscutible la existencia del riesgo estructural/RAW entre las etapas de Writeback y Decode. Al retirar el multiplexor interno de write-through (`BYPASS = 0`), la FPGA física leyó efectivamente el valor obsoleto `0` almacenado en las celdas de memoria distribuida del banco de registros, produciendo un error silencioso de cálculo exactamente idéntico al modelado en la teoría y en la simulación.
