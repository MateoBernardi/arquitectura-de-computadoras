# host/ — el lado de la PC

El software que habla con la placa por el puerto serie, con el protocolo de la debug unit
(ver [`../rtl/debug/README.md`](../rtl/debug/README.md)).

```
 gui.py ─────────────┐
 debug_host.py ──────┼──▶ lib/debug_protocol.py ──▶ pyserial ──▶ /dev/ttyUSB1 ──▶ placa
 benchmark_runner.py ┘    lib/assemble.py (binutils: .s → palabras)
```

| Archivo | Qué es |
|---|---|
| `gui.py` | la GUI: conectar, cargar un programa, correrlo o avanzarlo ciclo a ciclo, y ver el pipeline, los registros, la memoria y la causa del halt. *Medir* compara el rendimiento de la placa con el del modelo (ver abajo) |
| `lib/medir.py` | corre un programa en la placa (contadores de hardware) y en el modelo (`build/sim/placa/Vtb`) y los compara; lo usan la GUI y `verif/placa` |
| `debug_host.py` | lo mismo por línea de comandos, para usarlo desde scripts |
| `benchmark_runner.py` | corre un programa en la placa contando los ciclos (de a uno) y calcula el CPI |
| `lib/debug_protocol.py` | el protocolo: los comandos, la lectura del dump (`decode_dump`) y un desensamblador para mostrar las instrucciones del pipeline |
| `lib/assemble.py` | ensambla un `.s` con binutils (no hay ensamblador propio) y devuelve las palabras a cargar |
| `tests/` | tests del protocolo y de la GUI, sin placa: el puerto serie y el ensamblador se reemplazan por versiones falsas |

## Requisitos

- Python 3 con `pyserial`, y `python3-tk` para la GUI.
- Un ensamblador RISC-V de binutils. Sirve el de `verif/tools/install.sh` (`riscv-none-elf-`)
  o el del sistema (`sudo apt install binutils-riscv64-unknown-elf`).

## Uso

```bash
python3 host/gui.py
python3 host/debug_host.py --port /dev/ttyUSB1 asm programs/criba.s run wait dump
python3 host/debug_host.py --port /dev/ttyUSB1 reset step 3 dump
python3 host/benchmark_runner.py --port /dev/ttyUSB1 --asm programs/criba.s
```

Las acciones de `debug_host.py` (`asm`, `load`, `step`, `run`, `wait`, `pause`, `reset`,
`dump`) se ejecutan en orden, en una sola conexión. El baud rate por defecto (19200) está
en `DEFAULT_BAUD`, en `lib/debug_protocol.py`, y tiene que coincidir con el `BAUD_RATE`
del hardware.

## Medir: placa contra modelo

El botón **Medir** de la GUI ensambla el programa del editor y:

1. en la **placa**: pone la dmem en cero, lo carga, lo corre con `R` hasta el halt y lee los
   contadores de rendimiento del hardware (ciclos e instrucciones retiradas, palabras 90 y
   91 del dump, ver `rtl/top/README.md`);
2. en el **modelo**: lo corre en la simulación del RTL con las memorias de la placa
   (`build/sim/placa/Vtb`; se compila con `verif/sim/build.sh placa`; otra ruta con
   `TP4_SIM=...`).

La solapa *Rendimiento* muestra ciclos, instrucciones, CPI, tiempo a 70 MHz y causa del halt
de los dos lados, con la diferencia, dice si el estado final (registros y dmem) es el mismo
y guarda un historial de las mediciones. Si el modelo no está compilado, muestra solo la
placa. Los contadores también aparecen arriba de la solapa *Pipeline* en cada lectura, así
que con *Step* se ven avanzar ciclo a ciclo.

Los tests corren con `verif/run.sh host`, o con `python3 -m unittest discover -s tests`
desde `host/`.
