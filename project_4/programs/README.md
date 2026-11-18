# programs/ — programas de demostración y benchmarks

Programas en assembly RV32I que se cargan en la placa por la debug unit
(`host/debug_host.py`, `host/benchmark_runner.py` o la GUI). Todos terminan en `ebreak`,
que detiene el CPU y le avisa al host que terminó.

Los elegimos para que cada uno **muestre una cosa concreta del pipeline**, y son a la vez
los únicos programas de los que sacamos números de rendimiento: los corre la placa real y
los corre la simulación, y las dos dan exactamente los mismos ciclos
(`verif/placa/run.py`, `verif/sim/bench.py`).

| Programa | Qué muestra | Instr. | Ciclos | CPI |
|---|---|---|---|---|
| `pipeline_test.s` | todas las clases de instrucción y todos los riesgos, en un solo programa | 61 | 83 | 1,361 |
| `test_bypass.s` | la lectura y escritura del mismo registro en el mismo ciclo (WB → ID) | 6 | 9 | 1,500 |
| `criba.s` | costo de los saltos y del load-use | 322 | 457 | 1,419 |
| `criba_opt.s` | la criba con *instruction scheduling*: desaparece el load-use | 322 | 453 | 1,407 |
| `criba_unroll.s` | la criba con *loop unrolling*: menos saltos tomados | 277 | 378 | 1,365 |
| `suma_arreglo.s` | el peor caso de load-use: un stall en cada iteración | 518 | 837 | 1,616 |
| `overflow_test.s` | la protección de la debug unit contra programas que no entran en la imem | 261 | — | — |

(Ciclos medidos en la placa a 70 MHz. El desglose de dónde se pierde cada ciclo está en
`RESULTADOS.md`, sección 3.)

## `pipeline_test.s` — prueba de todo el ISA

Recorre las instrucciones de RV32I agrupadas por lo que ejercitan:

- **ALU y forwarding**: `add x3,x1,x2` y `sub x4,x3,x1` usan el resultado de la
  instrucción anterior (forwarding desde MEM y desde WB).
- **Load-use**: `lw x5` seguido de `add x6,x5,x5`, que obliga a un stall de 1 ciclo.
- **Saltos**: `beq` no tomado, `bne` tomado (las instrucciones que entraron detrás se
  descartan, por eso `x7` termina en 3 y no en 99), `jal`, `auipc` y `jalr` a una dirección
  absoluta (que se saltea `addi x14`).
- **Inmediatos grandes**: `lui` + `addi` arman `0x12345678`.
- **Comparaciones y shifts**, con y sin signo: `slt`, `sltu`, `sll`, `srl`, `sra`,
  `srai` sobre un número negativo.
- **Accesos de byte y media palabra**: `sb`, `sh`, y `lb`/`lbu`/`lh`/`lhu` para ver la
  extensión de signo.
- **Un loop** con `blt` hacia atrás y un `bge` final.
- **El halt**: las dos instrucciones que siguen al `ebreak` no se tienen que ejecutar
  (`x31` y `dmem[20]` quedan en 0).

**Por qué lo elegimos:** es la referencia de la simulación del sistema completo: el modelo de RV32I
en Python (`verif/system/rv32i_model.py`) lo ejecuta y genera los registros y la memoria
esperados.

## `test_bypass.s` — escritura y lectura en el mismo ciclo

`addi x1` escribe `x1`, vienen dos instrucciones que no lo tocan, y la cuarta (`add x5,x1,x1`)
lo lee. A esa distancia el forwarding ya no actúa: cuando la cuarta está en ID, la primera
está en WB escribiendo el banco de registros en ese mismo ciclo. El banco de registros
devuelve el valor nuevo (`BYPASS = 1`, ver `rtl/pipeline/2_decode/README.md`), así que
`x5 = 200` y `dmem[0] = 200`. Sin ese bypass, `x5` valdría 0.

**Por qué lo elegimos:** es el único riesgo de datos que no resuelve la forward unit. Este programa lo aísla en 6 instrucciones.

## `criba.s` — criba de Eratóstenes

Marca los primos del 2 al 31 en `dmem[0..31]`: al terminar, `dmem[k] = 0` si `k` es primo
y `1` si es compuesto. Primero pone la tabla en 0; después, para cada `i` de 2 a 5 que
siga marcado como primo, marca sus múltiplos.

**Por qué lo elegimos:** es un algoritmo conocido, con resultado fácil de verificar a
ojo en el dump de memoria, y tiene la mezcla típica de: loops anidados,
loads, stores y muchos saltos. Es el benchmark principal (CPI, MIPS, potencia).
Muestra que **los saltos son la pérdida principal**: el 20 % de las instrucciones son
saltos tomados y causan el 95 % de los ciclos perdidos (2 ciclos de flush cada uno).

## `criba_opt.s` — la criba con *instruction scheduling*

Misma criba, con un solo cambio: `addi x8, x0, 6` (el límite del loop externo) se mueve
entre `lw x4` y `bne x4, ...`. Así el `bne` ya no usa el dato del load en el ciclo
siguiente y el stall de load-use desaparece. El loop externo corre 4 veces: 4 stalls
menos, 457 → 453 ciclos, con las mismas 322 instrucciones.

**Por qué lo elegimos:** muestra que el compilador (o el programador) puede esconder un
riesgo reordenando instrucciones, sin tocar el hardware.

## `criba_unroll.s` — la criba con *loop unrolling*

Sobre `criba_opt`, el loop que pone la tabla en 0 escribe dos palabras por iteración
(`sw x0, 0(x3)` y `sw x0, 4(x3)`) y avanza de a 2. Son la mitad de las vueltas, y por lo
tanto la mitad de los `blt` tomados de ese loop: 322 → 277 instrucciones y
453 → 378 ciclos.

**Por qué lo elegimos:** ataca la pérdida principal que mostró la criba (los saltos
tomados), y deja ver que el CPI baja menos que los ciclos, porque se sacaron sobre todo
instrucciones de control del loop.

## `suma_arreglo.s` — el peor caso de load-use

Llena `dmem[0..63]` con `0..63` y después los suma: en cada vuelta el `add` usa el dato
del `lw` inmediatamente anterior. Deja la suma (2016) en `x10` y en `dmem[64]`.

**Por qué lo elegimos:** es el caso más desfavorable para nuestro diseño de 70 MHz, que
paga 1 ciclo de stall en cada load-use. Lo usamos para decidir entre los dos diseños del
camino de la memoria (`verif/README.md`): aun aquí, donde el stall pesa más (CPI 1,616),
el diseño final gana con respecto a la otra opción porque corre un 17 % más rápido.

## `overflow_test.s` — programa que no entra en la memoria

258 NOPs + 3 instrucciones = 261 palabras, cuando la imem tiene lugar para 256. La debug
unit tiene que rechazar la carga con `E` (`RSP_ERR`) y dejar el CPU en reset, sin ejecutar
nada.

**Por qué lo elegimos:** muestra que la debug unit valida lo que recibe en vez de
escribir fuera de la memoria. `host/benchmark_runner.py` lo reconoce por el nombre y
reporta si el rechazo funcionó. `verif/placa/run.py` lo saltea en la comparación con la
simulación, porque no se puede cargar a propósito.

## Cómo correrlos

```sh
# cargar, correr y ver registros y memoria
python3 host/debug_host.py --port /dev/ttyUSB1 asm programs/criba.s run wait dump

# medir ciclos y CPI en la placa
python3 host/benchmark_runner.py --port /dev/ttyUSB1 --asm programs/criba.s

# los mismos programas en simulación
verif/sim/bench.py
```
