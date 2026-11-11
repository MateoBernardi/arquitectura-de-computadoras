# verif/placa/ — el sistema en la FPGA real

La última etapa del flujo: el bitstream cargado en la Nexys4 DDR, manejado por la UART
igual que lo hace el host. Son dos capas: `programar` (carga el bitstream por JTAG) y
`placa` (las pruebas). Se corren con `verif/run.sh programar placa`.

| Archivo | Qué hace |
|---|---|
| `program.tcl` | configura la FPGA por JTAG con `build/bitstream/top_riscv.bit` y lee el pin DONE (lo mismo que "Program Device" en la GUI) |
| `run.py` | las pruebas, por la UART |

## Antes de correr la capa

La FPGA se configura por **JTAG** (la UART del diseño existe recién después de cargar el
bitstream). Lo hace la capa `programar`, con el bitstream que dejó la capa `bitstream` en
`build/bitstream/` (generado de la implementación verificada). Solo lo carga si es de la
versión actual del hardware (ver `BUILD_ID` en [`../README.md`](../README.md)).
`verif/run.sh fpga` (o `todo`) va del RTL a la placa probada en un solo comando; si el
hardware no cambió, `verif/run.sh programar placa` alcanza.

También se puede programar con la GUI (abrir `build/vivado/tp4.xpr` → *Generate Bitstream* →
*Program Device*) y después correr solo `verif/run.sh placa`: la capa prueba lo que tenga
cargado la FPGA, y si no es la versión actual del hardware falla el chequeo de versión.
La configuración por JTAG es volátil: no toca la flash y se pierde al apagar la placa.

El puerto serie es el segundo canal del chip USB de la placa: `/dev/ttyUSB1` por defecto
(el primero es JTAG). Se cambia con `PLACA_PUERTO=/dev/... verif/run.sh placa`. Sin placa
conectada, la capa da SKIP.

## Qué prueba

No compara contra valores escritos a mano sino contra **la simulación del RTL con las
memorias de la placa** (`verif/sim/build.sh placa`, 1 KB de imem y de dmem): cada programa
tiene que terminar en el hardware igual que en la simulación.

| Grupo | Qué compara |
|---|---|
| versión | `BUILD_ID` (última palabra del dump) es la versión actual del hardware; si el hardware tiene cambios sin commitear, falla: no hay con qué comparar |
| programas (`programs/*.s`) | ciclos, x1..x31, las 32 palabras de la dmem que muestra el dump, y causa, PC y dirección del halt |
| traps (`verif/sim/tests/traps/*.S`) | lo mismo, para cada causa de trap |
| comandos de la debug unit | step, run, reset (borra registros, conserva el programa), pausa, trap por instrucción ilegal, programa demasiado grande (`E`), comando desconocido (`?`): los escenarios de `verif/system/`, ahora en hardware |

Los ciclos se cuentan con `S` (un ciclo por comando), igual que en la placa los cuenta el
host. La placa conserva la dmem entre programas y el reset del CPU no la borra, así que antes
de cada programa se corre uno que la pone en cero; la simulación arranca con la dmem en cero
(`+dmem-en-cero`).

Se comprobó que la comparación detecta diferencias: contra la simulación de una variante
sin stall de load-use (que hacía otros ciclos) marca los programas en los que difieren, y
con un commit distinto falla la versión.
