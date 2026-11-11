# `4_memory/` — etapa MEM

Accede a la memoria de datos: un store escribe, un load lee. La dirección la calculó la
ALU en EX, y el dato leído va al mux de resultado de WB (y desde ahí al forwarding: no se
adelanta desde MEM, ver [`flow/`](../flow/README.md#hazard_unit--stall-de-load-use)).

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

## `dmem` — memoria de datos

```
               ┌───────────────────────────────────┐
clk       1 ──▶│                                   │──▶ rdata    32  C
we        1 ──▶│                dmem               │──▶ dbg_data 32  C
addr     32 ──▶│              [mixto]              │
wdata    32 ──▶│  lee comb., escribe en el flanco  │
funct3    3 ──▶│                                   │
dbg_addr  8 ──▶│                                   │
               └───────────────────────────────────┘
```

- **Lectura** combinacional: el dato está en el mismo ciclo, así MEM entra en un ciclo. Ya
  sale con el tamaño y el signo del load (`funct3`: byte, media palabra o palabra, con o
  sin signo).
- **Escritura** en el flanco, de 1, 2 o 4 bytes según el store. La memoria está armada como
  4 bancos de un byte; así un store de un byte escribe solo su banco, y Vivado la
  implementa como RAM distribuida. Con lectura combinacional no puede ser una BRAM, que
  solo lee de forma sincrónica.
- Solo recibe accesos válidos: los desalineados y los que caen fuera de la memoria los
  detecta `trap_unit` en EX, y esa instrucción ya no escribe (`we` en 0).
- `dbg_addr` / `dbg_data` es un segundo puerto de lectura, por palabra, para el bus de debug
  (que muestra las primeras 32 palabras).

| Parámetro | En el sistema | Para qué |
|---|---|---|
| `DEPTH` | 256 | palabras de 32 bits: 1 KB |

## La dmem entre programas

La dmem **conserva su contenido** entre un programa y el siguiente: ni la carga (`L`) ni
el reset del CPU (`X`) la borran. Solo arranca en cero al configurar la FPGA.

**Por qué:** es lo que hace un procesador real (el reset deja el CPU en un estado conocido,
pero no la RAM), y borrarla requeriría un puerto de escritura más para la debug unit en un
camino que ya es crítico para el timing.

**Consecuencia:** un programa que depende del contenido inicial de la memoria lo tiene que
escribir él mismo. La capa `placa` de la verificación, por ejemplo, corre antes de cada
programa uno que la pone en cero, para poder comparar contra la simulación.
