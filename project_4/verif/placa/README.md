# verif/placa/ — el sistema en la FPGA real

La última etapa del flujo: el bitstream cargado en la Nexys4 DDR, manejado por la UART
igual que lo hace el host. Se corre con `verif/run.sh placa`.

| Archivo | Qué hace |
|---|---|
| `program.tcl` | genera el bitstream desde la implementación ya verificada y configura la FPGA por JTAG (lo mismo que "Generate Bitstream" + "Program Device" en la GUI) |
| `run.py` | las pruebas, por la UART |

## Antes de correr la capa

La FPGA se configura por **JTAG** (la UART del diseño existe recién después de cargar el
bitstream). Las dos formas sirven:

```bash
verif/run.sh fpga                                               # síntesis + implementación verificadas
vivado -mode batch -source verif/placa/program.tcl              # bitstream + programar
```

o, en la GUI, abrir `build/vivado/tp4.xpr` → *Generate Bitstream* → *Program Device*.
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
| versión | `BUILD_ID` (última palabra del dump) es el commit que se está probando; si el RTL tiene cambios sin commitear, falla: no hay con qué comparar |
| programas (`programs/*.s`) | ciclos, x1..x31, las 32 palabras de la dmem que muestra el dump, y causa, PC y dirección del halt |
| traps (`verif/sim/tests/traps/*.S`) | lo mismo, para cada causa de trap |
| comandos de la debug unit | step, run, reset (borra registros, conserva el programa), pausa, trap por instrucción ilegal, programa demasiado grande (`E`), comando desconocido (`?`): los escenarios de `verif/system/`, ahora en hardware |

Los ciclos se cuentan con `S` (un ciclo por comando), igual que en la placa los cuenta el
host. La placa conserva la dmem entre programas y el reset del CPU no la borra, así que antes
de cada programa se corre uno que la pone en cero; la simulación arranca con la dmem en cero
(`+dmem-en-cero`).

Se comprobó que la comparación detecta diferencias: contra la simulación de la variante
`hazard_unit_nostall` marca los programas en los que esa variante tarda otros ciclos, y con
un commit distinto falla la versión.
