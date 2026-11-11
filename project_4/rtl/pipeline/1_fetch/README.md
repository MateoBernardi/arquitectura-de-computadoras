# `1_fetch/` — etapa IF

Trae la instrucción que indica el PC y se la pasa a ID por el registro IF/ID.

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

## El PC

No es un módulo aparte: es un registro dentro de `riscv_pipeline`, porque para saber si
avanza necesita señales de casi todo el pipeline. En cada ciclo pasa a:
- el destino del salto, si en EX hay un salto tomado (`redirect`);
- PC + 4, en cualquier otro caso.

Y **no cambia** si el CPU está pausado (`i_enable = 0`), si hay un stall de load-use o si
la instrucción de EX detiene el CPU. Arranca en 0 con el reset.

## `imem` — memoria de instrucciones

```
              ┌───────────────────────────────────┐
clk      1 ──▶│                                   │──▶ instr 32  C
addr    32 ──▶│                imem               │
wr_en    1 ──▶│              [mixto]              │
wr_addr 10 ──▶│  lee comb., escribe en el flanco  │
wr_data  8 ──▶│                                   │
              └───────────────────────────────────┘
```

- **Lectura** combinacional: la instrucción está disponible en el mismo ciclo en que se
  presenta el PC, así IF entra en un ciclo.
- **Escritura** de a un byte en el flanco del reloj: es el puerto por el que la debug unit
  carga el programa, con el CPU en reset.
- Al configurar la FPGA arranca llena de NOP (`addi x0, x0, 0`).

| Parámetro | En el sistema | Para qué |
|---|---|---|
| `ADDR_W` | 10 | tamaño en bytes: 2^10 = 1 KB = 256 instrucciones; `wr_addr` tiene `ADDR_W` bits |
| `INIT_FILE` | "" | `.hex` para precargarla (solo simulación) |

De `addr` se usan los bits que direccionan una palabra dentro de la memoria. Que el PC
quede fuera de la imem no lo resuelve la memoria sino ID: la instrucción traída desde
ahí es una excepción (causa 1).
