# `4_memory/` — etapa MEM

**Qué hace:** accede a la memoria de datos: escribe el dato en un store, o devuelve
el dato leído en un load.

```
mem_alu_out ──▶ addr      (la ALU calculó la dirección)
mem_rdata2  ──▶ wdata     (el dato a escribir)
                         ──▶ rdata ──▶ al mux de writeback
```

---

## `dmem.v` — `dmem`

Memoria de datos: **1 KB** (`DEPTH = 256` palabras de 32 bits), byte-addressable.
Escritura **sincrónica**, lectura **asincrónica**.

**Entradas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `clk` | 1 | |
| `we` | 1 | habilita la escritura |
| `addr` | 32 | dirección en bytes (sale de la ALU) |
| `wdata` | 32 | dato a escribir |
| `funct3` | 3 | `funct3` del store/load: define el tamaño y el signo |
| `dbg_addr` | 8 | índice de palabra para el puerto de debug |

**Salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `rdata` | 32 | dato leído, ya extendido según `funct3` |
| `dbg_data` | 32 | palabra cruda para el debug unit |

**Organización interna**

La memoria está partida en **4 carriles de 8 bits** (`lane0..lane3`), en vez de un
array de bytes plano:

```
lane0[k] lane1[k] lane2[k] lane3[k]   →   {lane3, lane2, lane1, lane0} = palabra
```

Con un array de bytes plano, un store de 4 bytes desalineado se convierte en 8 KB de
flip-flops. Con los 4 carriles, Vivado lo mapea a **RAM distribuida**.

**Wires internas**

- `widx` — `addr[AW+1:2]`, el índice de palabra.
- `boff` — `addr[1:0]`, el offset dentro de la palabra.
- `be` — enables por byte, según el tamaño del acceso:
  - `SB` → `4'b0001 << boff` (un byte)
  - `SH` → `4'b1100` o `4'b0011` (medio palabra)
  - `SW` → `4'b1111` (palabra completa)
- `sw` / `sb` — flags del tamaño de acceso.
- `d0..d3` — el byte que va a cada carril, **reposicionado** según el offset:
  - `d0 = wdata[7:0]`
  - `d1 = sb ? wdata[7:0] : wdata[15:8]`
  - `d2 = sw ? wdata[23:16] : wdata[7:0]`
  - `d3 = sw ? wdata[31:24] : wdata[15:8]`
- `word` — la palabra completa leída (`{lane3, lane2, lane1, lane0}`).
- `b` — el byte pedido: `word[boff*8 +: 8]`.
- `h` — la media palabra: `boff[1] ? word[31:16] : word[15:0]`.

**Lecturas**

| `funct3` | Instrucción | `rdata` |
|---|---|---|
| `000` | LB | byte con signo |
| `001` | LH | media palabra con signo |
| `010` | LW | palabra completa |
| `100` | LBU | byte sin signo |
| `101` | LHU | media palabra sin signo |
| `111` | SW | — (es un store) |

---

## Notas

- **Los accesos desalineados no están soportados** (como corresponde a RV32I, donde
  un acceso desalineado debería trapear). LH/LHU/SH en direcciones pares, LW/SW en
  múltiplos de 4.
- La dmem **no se borra** con el reset: el reset del CPU no la toca (sí la imem se
  conserva, y la dmem tampoco).
