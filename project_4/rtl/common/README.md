# `common/` — utilidades compartidas

Módulos chicos que usan varios bloques del diseño.

---

## `reset_gen.v` — `reset_gen`

Genera el **reset de power-on** y sincroniza el botón de reset de la placa.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `i_clk` | 1 | |
| `i_btn_reset` | 1 | botón de reset (asíncrono) |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `o_reset` | 1 | reset del sistema, sincrónico con `i_clk` |

**Cómo funciona**

- Un **contador** que al arrancar fuerza el reset durante unos pocos ciclos
  (power-on reset).
- El botón pasa por un **sincronizador de 2 flip-flops** (el `u_btn_sync` interno)
  para que el reset no sea asíncrono con el reloj.
- La salida se combina: `o_reset` está activo si el botón está apretado **o** si
  todavía no terminó el power-on reset.

En `top_riscv` se le pasa `i_reset | ~locked`: si el MMCM no enganchó, el sistema
queda en reset.

---

## `sync_2ff.v` — `sync_2ff`

Sincronizador de 2 flip-flops para llevar señales asíncronas al dominio del
reloj.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `i_clk` | 1 | |
| `i_async` | 1 | señal asíncrona |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `o_sync` | 1 | la señal, ya sincronizada |

**Parámetro**

| Parámetro | Default | Para qué |
|---|---|---|
| `INIT` | `1'b0` | valor inicial de los 2 flip-flops |

Se usa en `top_riscv` para la línea RX de la UART, con `INIT = 1'b1` (en reposo la
línea UART está en 1).
