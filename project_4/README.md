# project_4 — CPU RV32I de 5 etapas en FPGA, con debug unit por UART

Un procesador RISC-V **RV32I** con pipeline de 5 etapas, para la placa **Nexys4 DDR**
(Artix-7). Desde la PC, por el cable USB, se le cargan programas, se lo corre, y se lee su estado interno: los registros de cada etapa del pipeline, el
banco de registros y la memoria de datos.

```
        PC                                       FPGA (top_riscv, 70 MHz)
 ┌──────────────┐   USB   ┌──────┐   UART   ┌───────────┐   ┌─────────────┐   ┌────────────────┐
 │ host/        │◀───────▶│ FTDI │◀────────▶│ uart_core │◀─▶│ debug_unit  │◀─▶│ riscv_pipeline │
 │ GUI, CLI     │ 19200   └──────┘  8N1     └───────────┘   └─────────────┘   └────────────────┘
 └──────────────┘                                    bytes      comandos       enable, reset, halt,
                                                                               carga de la imem,
                                                                               bus de debug
```

- **`riscv_pipeline`** es el CPU: recibe reloj, reset y enable, y
  avisa cuando se detiene con una salida LED.
- **`debug_unit`** traduce comandos de un byte que llegan por la UART (cargar, correr, un
  ciclo, pausar, reset, leer el estado) en acciones sobre el CPU. Funciona con una máquina de estados.
- **`uart_core`** convierte esos bytes en la señal serie que viaja por el cable USB. 19200 bps.
- **`host/`**, habla el protocolo establecido por **`uart_core`**: usa la GUI y la línea de comandos.

## Cumplimiento de RV32I

El CPU implementa RV32I **sin la arquitectura privilegiada** (sin CSRs). Toda excepción
(instrucción ilegal, salto a una dirección no alineada, load/store desalineado o fuera de
la memoria, `ecall`, `ebreak`) es un *fatal trap*, como lo permite la especificación: el
CPU se detiene sin que la instrucción escriba nada, y la debug unit informa la causa (con
los códigos estándar de `mcause`) y el PC.

| Verificación | Resultado |
|--------------|-----------|
| riscv-formal: el CPU contra la ISA, para cualquier programa, incluidas las excepciones | 45/45 |
| riscv-arch-test: la suite oficial (las instrucciones; sin CSRs que se asume que nunca llegan en los tests) | 39/39 |
| en la placa: programas y traps iguales a la simulación del RTL, ciclo a ciclo | 41/41 |

El detalle, y por qué riscv-arch-test no alcanza para las excepciones, está en
[`verif/README.md`](verif/README.md).

## Estructura

```
project_4/
├── rtl/            el hardware (Verilog), con un README por carpeta
│   ├── top/        top_riscv: une todo y lo conecta a la placa
│   ├── pipeline/   el CPU: 1_fetch … 5_writeback, regs/, flow/
│   ├── debug/      la debug unit
│   ├── uart/       la UART con sus colas
│   └── common/     reset y sincronizador
├── constraints/    pines y reloj de la Nexys4 DDR
├── programs/       programas en assembly (benchmarks y pruebas)
├── host/           la PC: GUI, línea de comandos, benchmark en la placa
├── verif/          la verificación, en el orden del flujo: RTL → sistema → FPGA → placa
└── build/          todo lo generado (no se versiona)
```

| README | Contenido |
|---|---|
| [`rtl/top/`](rtl/top/README.md) | el sistema, los pines, los parámetros y el reloj |
| [`rtl/pipeline/`](rtl/pipeline/README.md) | el CPU: las etapas, los riesgos, las excepciones y el mapa del bus de debug |
| [`rtl/pipeline/1_fetch/`](rtl/pipeline/1_fetch/README.md) … [`5_writeback/`](rtl/pipeline/5_writeback/README.md), [`regs/`](rtl/pipeline/regs/README.md), [`flow/`](rtl/pipeline/flow/README.md) | cada etapa y los módulos que la forman |
| [`rtl/debug/`](rtl/debug/README.md) | la debug unit y el protocolo |
| [`rtl/uart/`](rtl/uart/README.md) | la UART |
| [`rtl/common/`](rtl/common/README.md) | reset y sincronización |
| [`verif/`](verif/README.md) | la verificación |

Cada README del RTL tiene un diagrama por módulo con sus entradas y salidas, el ancho en
bits de cada una, y qué es combinacional y qué es secuencial.

## Configuración

| Qué | Valor | Dónde se cambia |
|---|---|---|
| reloj del sistema | **70 MHz**, generados por un MMCM desde los 100 MHz de la placa | `MMCM_MULT` / `MMCM_DIV_X8` de `top_riscv` ([por qué 70 MHz](rtl/top/README.md#el-reloj)) |
| UART | **19200 baudios, 8N1** | `BAUD_RATE` de `top_riscv` y `DEFAULT_BAUD` del host ([por qué 19200](rtl/uart/README.md)) |
| memoria de instrucciones | 1 KB = 256 instrucciones | `IMEM_ADDR_W` de `top_riscv` |
| memoria de datos | 1 KB = 256 palabras | `DMEM_DEPTH` de `riscv_pipeline` |
| puerto serie en la PC | `/dev/ttyUSB1` | `--port` del host |
| LEDs y display | LD10..LD15: forwarding A/B, stall, flush, excepción, halt; con SW0, el display muestra la última escritura en un registro | [`rtl/top/README.md`](rtl/top/README.md#leds-y-display) |

La restricción del reloj está en `constraints/nexys4ddr_top.xdc` y es la del oscilador de
100 MHz: Vivado deriva de ella la del reloj del sistema, así que cambiar la frecuencia no
requiere tocar el XDC.

## Uso

**1. Crear el proyecto de Vivado y programar la placa.** El proyecto no se versiona: lo
genera un script desde los fuentes.

```bash
verif/run.sh fpga      # crea build/vivado/tp4.xpr, sintetiza, implementa, verifica y programa la placa
```

También se puede abrir `build/vivado/tp4.xpr` en la GUI y usar *Generate Bitstream* y
*Program Device*. La configuración por JTAG se pierde al apagar la placa.

**2. Hablar con la placa desde la PC** (necesita `pyserial` y un ensamblador RISC-V; ver
`host/`):

```bash
python3 host/gui.py                                                 # la GUI
python3 host/debug_host.py --port /dev/ttyUSB1 asm programs/criba.s run wait dump
python3 host/benchmark_runner.py --port /dev/ttyUSB1 --asm programs/criba.s
```

Los programas arrancan en la dirección 0 y terminan con `ebreak`. Cada uno es una
secuencia de instrucciones (no hay sección de datos): los datos los escribe el programa en
la dmem.

## Resultados

| | |
|---|---|
| Frecuencia | 70 MHz (cierra timing en el peor caso; 80 MHz no) |
| CPI medido en la placa | 1,36 a 1,62 (ideal 1); 43 a 51 MIPS |
| Recursos | 3222 LUT (5 %), 1863 FF (1,5 %), sin BRAM ni DSP |
| Potencia estimada | 0,22 W en el chip, ~0,025 W del diseño |

El análisis completo (camino crítico, desglose del CPI por categoría y por causa, recursos
por módulo, potencia y eficiencia) está en [`RESULTADOS.md`](RESULTADOS.md).

## Verificación

Un solo comando corre la verificación por capas, en el orden del flujo, y deja un resumen
en `build/reports/resumen.md`:

```bash
verif/tools/install.sh        # instala las herramientas (una vez)
verif/run.sh --lista          # las capas y qué herramienta le falta a cada una
verif/run.sh                  # todo
verif/run.sh rapido           # sin riscv-formal ni Vivado (~6 min)
verif/run.sh fpga             # síntesis, implementación y placa
verif/run.sh act traps        # capas sueltas
```

| Capa | Qué prueba |
|---|---|
| `formal` | propiedades formales de los módulos del pipeline |
| `rvfi` | el CPU completo contra la ISA (riscv-formal) |
| `act` | la suite oficial riscv-arch-test |
| `traps` | la causa y el PC de cada excepción |
| `rendimiento` | ciclos y CPI, y las variantes del diseño |
| `sistema` | el sistema completo simulado, manejado por la UART |
| `host` | el software de la PC |
| `sintesis`, `implementacion` | Vivado: que el netlist sea lo que pide el RTL, y el timing |
| `placa` | la FPGA real, comparada contra la simulación |

Cada capa da PASS solo si corrió al menos una prueba y todas dieron bien; si falta una
herramienta da SKIP, que nunca cuenta como PASS. Ver [`verif/README.md`](verif/README.md).
