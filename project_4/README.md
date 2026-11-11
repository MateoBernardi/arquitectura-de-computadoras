# project_4 — CPU RV32I de 5 etapas con debug unit por UART

Núcleo RISC-V RV32I con pipeline de 5 etapas, pensado para correr en la Nexys4 DDR.
Se lo puede controlar y depurar desde la PC por el puerto serie, con la GUI de `host/`.

---

## 1. Estructura de carpetas

```
project_4/
├── README.md        ← este archivo (mapa general del proyecto)
├── rtl/             ← el hardware (Verilog), con un README por carpeta
│   ├── pipeline/    ← el CPU: 1_fetch … 5_writeback, regs/, flow/
│   ├── uart/        ← UART TX + RX con FIFOs
│   ├── debug/       ← debug unit (comandos por UART)
│   ├── top/         ← top_riscv
│   └── common/      ← reset y sincronizador
├── constraints/     ← pines y reloj de la Nexys4 DDR (xdc)
├── programs/        ← programas en assembly (benchmarks y pruebas)
├── host/            ← lado PC (Python): GUI, CLI, benchmark en la placa
│   ├── lib/         ← protocolo UART y ensamblador
│   └── tests/
├── verif/           ← verificación: RTL (formal, simulación), sistema, síntesis → implementación → bitstream → placa
└── build/           ← todo lo generado (no se versiona)
```

**Cada carpeta del RTL tiene su propio `README.md`** con el detalle de sus módulos
(qué hace, puertos, registros y wires). Para el índice completo de archivos:

| Carpeta | Contenido | README |
|---|---|---|
| `pipeline/` | el CPU de 5 etapas + el bus de debug | [pipeline/README.md](rtl/pipeline/README.md) |
| `pipeline/1_fetch/` | `imem` — memoria de instrucciones | [1_fetch](rtl/pipeline/1_fetch/README.md) |
| `pipeline/2_decode/` | `control`, `immgen`, `regfile` | [2_decode](rtl/pipeline/2_decode/README.md) |
| `pipeline/3_execute/` | `alu`, `alu_ops.vh`, `branch_unit` | [3_execute](rtl/pipeline/3_execute/README.md) |
| `pipeline/4_memory/` | `dmem` — memoria de datos | [4_memory](rtl/pipeline/4_memory/README.md) |
| `pipeline/5_writeback/` | el camino de escritura al regfile | [5_writeback](rtl/pipeline/5_writeback/README.md) |
| `pipeline/regs/` | `pipe_reg` — if_id / id_ex / ex_mem / mem_wb | [regs](rtl/pipeline/regs/README.md) |
| `pipeline/flow/` | `hazard_unit`, `forward_unit`, `flush_unit` | [flow](rtl/pipeline/flow/README.md) |
| `uart/` | `uart_core` + TX/RX + FIFOs | [uart](rtl/uart/README.md) |
| `debug/` | `debug_unit` + FSM/registros/combinacional | [debug](rtl/debug/README.md) |
| `top/` | `top_riscv` — une todo | [top](rtl/top/README.md) |
| `common/` | `reset_gen`, `sync_2ff` | [common](rtl/common/README.md) |
| `verif/system/` | testbench del sistema completo | [system](verif/system/README.md) |

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
completo está en el encabezado de [`riscv_pipeline.v`](rtl/pipeline/riscv_pipeline.v)
y lo decodifica el host en `host/lib/debug_protocol.py` (`decode_dump`).

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
| `host/lib/debug_protocol.py` | protocolo UART de la debug unit + `decode_dump` / `disasm` |
| `host/debug_host.py` | CLI para hablar con la FPGA (necesita `pyserial`) |
| `host/lib/assemble.py` | wrapper de binutils: `.s` → `.hex`/`.bin` |
| `host/tests/` | tests del protocolo y de la GUI |

Protocolo UART (ver `host/lib/debug_protocol.py`):

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

El proyecto de Vivado **no se versiona**: lo genera un script a partir de los fuentes.

```bash
vivado -mode batch -source verif/fpga/create_project.tcl    # → build/vivado/tp4.xpr
```

El top de hardware es `top_riscv` y el de simulación es `tb_top_riscv`. El script
agrega `rtl/pipeline/3_execute` al include path, porque `alu_ops.vh` lo usan `alu.v`
y `control.v`.

---

## 7. Tests del host

```bash
cd project_4/host
py -m unittest discover -s tests -v
```

No necesitan la FPGA: el puerto serie y el assembler están simulados.

---

## 8. Verificación formal

`verif/` verifica formalmente el CPU con herramientas libres (Yosys, SymbiYosys,
[riscv-formal](https://github.com/YosysHQ/riscv-formal)), sin Vivado: el CPU completo contra
la ISA RV32I, y contratos de módulos individuales (forwarding, hazards, control del
pipeline, ALU, memoria de datos). Ver [verif/README.md](verif/README.md).

`riscv_pipeline.v` tiene un bloque `ifdef RISCV_FORMAL` con la interfaz RVFI que usa
riscv-formal. Vivado no define esa macro, así que no forma parte del hardware sintetizado.

`verif/sim/` simula el RTL con Verilator y corre la suite oficial **riscv-arch-test** (ACT4),
autoverificada contra Sail, el modelo de referencia de la ISA. Ver [verif/sim/README.md](verif/sim/README.md).

**Cumplimiento:** el CPU implementa RV32I sin la arquitectura privilegiada (sin CSRs).
Toda excepción (instrucción ilegal, salto a una dirección no alineada, load/store
desalineado o fuera de memoria) es un *fatal trap*: el CPU se detiene sin que la
instrucción escriba nada, y la debug unit muestra la causa y el PC. Resultados:
riscv-formal 45/45, riscv-arch-test 39/39.

riscv-arch-test, tal como lo corremos, **no prueba las excepciones**: lo hace con un
manejador de traps en M-mode, que necesita CSRs. Que haya trap donde el estándar lo pide
lo verifica riscv-formal. La causa y el PC que reporta el CPU los verifican tests propios
(`verif/sim/run_traps.sh`), que existen por esa razón.
