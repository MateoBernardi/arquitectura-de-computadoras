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
  - `d3 = sw ? wdata[31:24] : (sb ? wdata[7:0] : wdata[15:8])`
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
- La dmem **no se borra** ni con el reset del CPU (`X`) ni al cargar un programa
  (`L`). Solo arranca en cero al configurar la FPGA (el `initial` de `dmem.v`).
  Ver [La dmem entre programas](#la-dmem-entre-programas).

---

## La dmem entre programas

**Decisión:** la dmem conserva su contenido entre una carga y la siguiente. Ni la
debug unit ni el reset del CPU escriben en ella.

**Por qué:**
- Es lo que hace un procesador real: el reset deja el CPU en un estado conocido
  (PC = 0, registros en 0, pipeline vacío), pero la RAM de datos no. Un programa
  que necesita memoria en cero la tiene que inicializar él mismo.
- Borrarla requeriría que la debug unit tuviera su propio puerto de escritura en la
  dmem (un mux en `we`/`addr`/`wdata` mientras el CPU está en reset) y una fase más
  en la FSM de carga que recorra las 256 palabras. Es lógica extra en el camino
  de la dmem, que ya forma parte del camino crítico.

**Consecuencia:** un programa que escribe solo algunos bytes de una palabra ve,
en los bytes que no toca, lo que dejó el programa anterior. Ejemplo real en la
placa: después de correr `host/tests/pipeline_test.s` (que hace
`sb x19,5(x0)` con `x19 = 0xFFFFFFF8`, dejando `[0x04] = 0x0000f800`), el
programa

```
addi x2, x0, 0x55
sb   x2, 4(x0)      # byte 0 de la palabra 1
sb   x2, 6(x0)      # byte 2 de la palabra 1
```

deja `[0x04] = 0x0055f855` y no `0x00550055`: el byte 1 conserva el `0xF8`. El
`sb` funciona bien (escribe solo su carril); lo que se ve es el dato viejo. El
simulador web (visual-riscv) da `0x00550055` porque su dmem arranca en cero al
recargar la página.

Para partir de una dmem en cero hay que reprogramar el bitstream.

**Respuesta a "¿es necesario vaciar la memoria?"** No para que el procesador
funcione: el pipeline y los registros sí se reinician en cada carga (la debug unit
mantiene el CPU en reset durante toda la carga), y eso alcanza para que el programa
nuevo arranque limpio. La dmem queda a cargo del programa: si depende de valores
iniciales, los tiene que escribir.
