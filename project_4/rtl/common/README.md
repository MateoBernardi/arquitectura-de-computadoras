# `common/` — reset y sincronización

Dos bloques chicos que resuelven el mismo problema: las señales que llegan de afuera de
la FPGA (el botón de reset, la línea RX de la UART, el switch del display) no tienen relación de fase con el
reloj. Si entraran directo a la lógica, un flip-flop podría muestrearlas justo mientras
cambian y quedar en un estado intermedio (metaestabilidad). Estos módulos las pasan al
dominio del reloj del sistema antes de que las use nadie.

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

## `sync_2ff` — sincronizador

Dos flip-flops en cadena: el primero puede quedar metaestable, el segundo le da un ciclo
entero para resolverse. Los dos llevan `ASYNC_REG`, que le indica a Vivado que son un
sincronizador (los ubica juntos y no los optimiza).

```
             ┌──────────────────────┐
i_clk   1 ──▶│                      │──▶ o_sync 1  R
i_async 1 ──▶│       sync_2ff       │
             │     [secuencial]     │
             │                      │
             └──────────────────────┘
```

| Parámetro | Valor | Para qué |
|---|---|---|
| `INIT` | 0 | valor inicial de los flip-flops; la línea RX usa 1 (en reposo, una UART está en 1) |

Lo usan `top_riscv` (para `i_rx` e `i_sw`) y `reset_gen` (para el botón). La salida llega dos
ciclos después que la entrada.

## `reset_gen` — reset del sistema

Genera el único reset del sistema, a partir de dos fuentes:
- **power-on reset**: activo los primeros `POR_CYCLES` ciclos después de configurar la
  FPGA, así el sistema arranca limpio sin apretar el botón;
- **el botón** (BTNC de la placa), pasado por un `sync_2ff`.

```
                 ┌──────────────────────┐
i_clk       1 ──▶│                      │──▶ o_reset 1  C
i_btn_reset 1 ──▶│      reset_gen       │
                 │     [secuencial]     │
                 │                      │
                 └──────────────────────┘
```

`o_reset` es el OR de dos registros (el contador de power-on y el sincronizador), así que
cambia solo en el flanco del reloj aunque la compuerta final sea combinacional.

| Parámetro | Valor | Para qué |
|---|---|---|
| `POR_CYCLES` | 4 | duración del power-on reset (≥ 2) |

En `top_riscv` la entrada es `i_reset | ~locked`: mientras el MMCM no enganchó el reloj,
el sistema sigue en reset. `o_reset` va a la UART y a la debug unit; el CPU recibe su
reset de la debug unit, que lo combina con el de carga y el del comando `X`.
