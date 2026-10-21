# project_4 — CPU RV32I de 5 etapas con debug unit por UART

Núcleo RISC-V RV32I con pipeline de 5 etapas, pensado para correr en la Nexys4 DDR.
Se lo puede controlar y depurar desde la PC por el puerto serie, con la GUI de `host/`.

---

## 1. Estructura de carpetas

```
project_4/
├── README.md                 ← este archivo (mapa general del proyecto)
├── add_sources.tcl           ← script de Vivado que arma el proyecto
├── NOTAS_REVISION.md         ← notas de revisión (NO versionado)
├── host/                     ← lado PC (Python)
│   ├── gui.py                ← GUI de debug (tema oscuro)
│   ├── debug_protocol.py     ← cliente del protocolo UART + decodificación del dump
│   ├── debug_host.py         ← CLI para hablar con la FPGA
│   ├── assemble.py           ← wrapper de binutils (ensambla .s → .hex)
│   └── tests/                ← tests del host
└── project_4.srcs/
    ├── constrs_1/            ← restricciones de la placa (xdc)
    ├── sim_1/new/            ← testbenches de simulación
    └── sources_1/new/        ← RTL
        ├── pipeline/         ← el CPU
        │   ├── 1_fetch/      ← IF
        │   ├── 2_decode/     ← ID
        │   ├── 3_execute/    ← EX
        │   ├── 4_memory/     ← MEM
        │   ├── 5_writeback/  ← WB
        │   ├── regs/         ← los 4 registros de pipeline
        │   └── flow/         ← stall / forwarding / flush
        ├── uart/             ← UART TX + RX con FIFOs
        ├── debug/            ← debug unit (comandos por UART)
        ├── top/              ← top_riscv
        ├── common/           ← reset y sincronizador
        ├── pc.v              ← sin usar (resto de TP1)
        ├── if_stage.v        ← sin usar (resto de TP1)
        └── riscv_core.v      ← sin usar (resto de TP1, CPU single-cycle)
```

**Cada carpeta del RTL tiene su propio `README.md`** con el detalle de sus módulos
(qué hace, puertos, registros y wires). Para el índice completo de archivos:

| Carpeta | Contenido | README |
|---|---|---|
| `pipeline/` | el CPU de 5 etapas + el bus de debug | [pipeline/README.md](project_4.srcs/sources_1/new/pipeline/README.md) |
| `pipeline/1_fetch/` | `imem` — memoria de instrucciones | [1_fetch](project_4.srcs/sources_1/new/pipeline/1_fetch/README.md) |
| `pipeline/2_decode/` | `control`, `immgen`, `regfile` | [2_decode](project_4.srcs/sources_1/new/pipeline/2_decode/README.md) |
| `pipeline/3_execute/` | `alu`, `alu_ops.vh`, `branch_unit` | [3_execute](project_4.srcs/sources_1/new/pipeline/3_execute/README.md) |
| `pipeline/4_memory/` | `dmem` — memoria de datos | [4_memory](project_4.srcs/sources_1/new/pipeline/4_memory/README.md) |
| `pipeline/5_writeback/` | el camino de escritura al regfile | [5_writeback](project_4.srcs/sources_1/new/pipeline/5_writeback/README.md) |
| `pipeline/regs/` | `pipe_reg` — if_id / id_ex / ex_mem / mem_wb | [regs](project_4.srcs/sources_1/new/pipeline/regs/README.md) |
| `pipeline/flow/` | `hazard_unit`, `forward_unit`, `flush_unit` | [flow](project_4.srcs/sources_1/new/pipeline/flow/README.md) |
| `uart/` | `uart_core` + TX/RX + FIFOs | [uart](project_4.srcs/sources_1/new/uart/README.md) |
| `debug/` | `debug_unit` + FSM/registros/combinacional | [debug](project_4.srcs/sources_1/new/debug/README.md) |
| `top/` | `top_riscv` — une todo | [top](project_4.srcs/sources_1/new/top/README.md) |
| `common/` | `reset_gen`, `sync_2ff` | [common](project_4.srcs/sources_1/new/common/README.md) |
| `sim_1/new/` | testbenches | [sim_1](project_4.srcs/sim_1/new/README.md) |

---

## 2. Jerarquía del hardware

```
top_riscv
├── reset_gen ................ power-on reset + botón de reset sincronizado
├── sync_2ff ................. sincronizador de la línea RX
├── uart_core
│   ├── baud_rate_gen ........ generador de tick de baud
│   ├── uart_rx
│   │   ├── uart_rx_comb ..... datapath combinacional
│   │   ├── uart_rx_fsm ...... máquina de estados
│   │   └── uart_rx_regs ..... estado + contadores + byte recibido
│   ├── fifo (rx) ............ cola de recepción
│   ├── uart_tx
│   │   ├── uart_tx_comb
│   │   ├── uart_tx_fsm
│   │   └── uart_tx_regs
│   └── fifo (tx) ............ cola de envío
├── debug_unit ............... comandos por UART, control del CPU y bus de debug
│   ├── debug_unit_comb
│   ├── debug_unit_fsm
│   └── debug_unit_regs
└── riscv_pipeline ........... el CPU de 5 etapas
    ├── imem ................. (1_fetch)
    ├── if_id_reg ............ (regs)
    ├── control .............. (2_decode)
    ├── immgen ............... (2_decode)
    ├── regfile .............. (2_decode)
    ├── id_ex_reg ............ (regs)
    ├── hazard_unit .......... (flow)
    ├── alu_tp1 .............. (3_execute)
    ├── branch_unit .......... (3_execute)
    ├── forward_unit ......... (flow)
    ├── flush_unit ........... (flow)
    ├── ex_mem_reg ........... (regs)
    ├── dmem ................. (4_memory)
    └── mem_wb_reg ........... (regs)
```

---

## 3. El pipeline de 5 etapas

```
    IF                ID                EX                MEM              WB
 ┌─────────┐     ┌─────────┐      ┌─────────┐      ┌─────────┐     ┌─────────┐
 │  imem   │     │ control │      │  alu    │      │  dmem   │     │ regfile │
 │   PC    │────▶│ immgen  │─────▶│ branch  │─────▶│         │────▶│ (write) │
 │         │     │ regfile │      │ fwd mux │      │         │     │         │
 └─────────┘     └─────────┘      └─────────┘      └─────────┘     └─────────┘
      │                │                │                │                │
      └─ if_id_reg ────┴─ id_ex_reg ────┴─ ex_mem_reg ──┴─ mem_wb_reg ──┘
```

- **IF** — el PC lee la instrucción de la `imem` (lectura combinacional).
- **ID** — `control` la decodifica y genera las señales de control, `immgen` arma el
  inmediato, `regfile` lee los dos operandos.
- **EX** — la `alu` opera; `branch_unit` evalúa la condición de salto y calcula el destino.
- **MEM** — la `dmem` lee o escribe el dato.
- **WB** — el mux final (`wb_sel`) elige el valor y se escribe en el `regfile`.

**Control de flujo entre etapas** (carpeta `flow/`):

| Situación | Qué pasa | Dónde |
|---|---|---|
| Dependencia RAW | se reenvía el valor desde EX/MEM o MEM/WB | `forward_unit` |
| load-use | se congela 1 ciclo el pipeline | `hazard_unit` |
| Salto tomado / JAL / JALR | se descartan las 2 instrucciones que van detrás del salto | `flush_unit` |

Los saltos se resuelven **en EX**, así que un salto taken cuesta 2 burbujas.

---

## 4. Bus de debug

La debug unit lee un mapa de palabras de 32 bits del CPU (combinacional). El mapa
completo está en el encabezado de [`riscv_pipeline.v`](project_4.srcs/sources_1/new/pipeline/riscv_pipeline.v)
y lo decodifica el host en `host/debug_protocol.py` (`decode_dump`).

| Dirección | Contenido |
|---|---|
| 0 | PC (IF) |
| 1–2 | IF/ID: pc, instrucción |
| 3–8 | ID/EX: control, campos, pc, rdata1, rdata2, imm |
| 9–13 | EX: alu_a, alu_b, alu_out, destino del salto, flags |
| 14–17 | EX/MEM: control, alu_out, rdata2, campos |
| 18 | MEM: dato leído de la dmem |
| 19–21 | MEM/WB: control, resultado, rd |
| 22–53 | x0..x31 del regfile |
| 54–85 | 32 palabras de la dmem |

---

## 5. El lado host (Python)

| Archivo | Qué hace |
|---|---|
| `host/gui.py` | GUI de debug: conectar, cargar programa, correr/paso a paso, ver registros y memoria |
| `host/debug_protocol.py` | protocolo UART de la debug unit + `decode_dump` / `disasm` |
| `host/debug_host.py` | CLI para hablar con la FPGA (necesita `pyserial`) |
| `host/assemble.py` | wrapper de binutils: `.s` → `.hex`/`.bin` |
| `host/tests/` | tests del protocolo y de la GUI |

Protocolo UART (ver `host/debug_protocol.py`):

```
'L' n_lo n_hi + 4n bytes LE  -> 'K' | 'E'   carga de programa
'S' -> 'K' | 'H'              un ciclo
'R' -> 'K' | 'H'              ejecución continua
'P' -> 'K'                    pausa
'X' -> 'K'                    reset del CPU
'D' -> count + count palabras de 32 bits LE
'H' espontáneo cuando el CPU llega a halt durante 'R'
```

---

## 6. Compilar y simular

El proyecto de Vivado (`.xpr`) **no se versiona** (está en `.gitignore`): cada uno lo
arma con el script, que ya busca los fuentes en todas las subcarpetas:

```bash
cd project_4
vivado -mode batch -source add_sources.tcl
```

Después se abre `project_4.xpr`. El top de hardware es `top_riscv` y el de simulación
es `tb_top_riscv`.

> Si ya tenías un `.xpr` viejo con los fuentes en plano, el script borra esas
> referencias y agrega las nuevas. Si preferís empezar de cero, borrá `project_4.xpr`
> (y su carpeta `project_4.cache`) y corré el script de nuevo.

El único header del proyecto es `alu_ops.vh`, y lo usan dos etapas: `alu.v`
(`3_execute/`) y `control.v` (`2_decode/`). Como el header está en una sola carpeta,
el script agrega `pipeline/3_execute` al `include_dirs` del fileset `sources_1` para
que los dos lo encuentren.

---

## 7. Tests del host

```bash
cd project_4/host
py -m unittest discover -s tests -v
```

No necesitan la FPGA: el puerto serie y el assembler están simulados.
