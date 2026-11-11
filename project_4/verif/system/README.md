# `verif/system/` — el sistema completo

Testbenches de simulación y los archivos de referencia.

| Archivo | Qué es |
|---|---|
| `tb_top_riscv.v` | **el principal**: testbench autoverificado del sistema completo (`top_riscv`) |
| `pipeline_prog.hex` | programa de prueba (`$readmemh`) |
| `pipeline_exp.hex` | resultado esperado: 32 palabras de registros + 16 de dmem |

> En Vivado el top de simulación es `tb_top_riscv` (lo define `verif/fpga/create_project.tcl`).

---

## `tb_top_riscv.v` — el testbench del sistema completo

Maneja `top_riscv` **desde la línea serie**, tal como lo haría el host de Python.
Para eso incluye un **receptor UART del host concurrente**, que guarda en una cola
todo lo que llega.

**Qué verifica**

1. Carga del programa (`pipeline_prog.hex`) con el comando `L`, comparando la
   `instru_mem` contra un modelo en el propio testbench.
2. `step` (un ciclo).
3. `run` hasta el halt (`ebreak`).
4. `dump` y comparación de x0..x31 y de las primeras 16 palabras de la dmem contra
   `pipeline_exp.hex`, y de la causa del halt (`ebreak`, en su PC).
   Además, un programa con una instrucción ilegal: trap con causa 2 en su PC, la
   instrucción anterior retirada y la posterior descartada.
5. `pause`.
6. `reset`.
7. Recarga con **relleno de NOP** (programa más corto que el declarado).
8. Programa **demasiado grande**.
9. **Comando desconocido**.

**Notas**

- El `BAUD_RATE` de simulación es alto para que corra rápido (un bit = 128 clocks).
- Los `.hex` tienen que estar en el directorio de simulación.
- En XSIM: `run -all`. Fuera de Vivado: `./run.sh` (Icarus).

**De dónde salen los archivos de referencia**

`pipeline_prog.hex` y `pipeline_exp.hex` los genera el **modelo en Python de RV32I**
(`verif/system/rv32i_model.py`) a partir de `programs/pipeline_test.s`. Es la misma
fuente de verdad que usan los tests del host, así que si cambia el CPU hay que
regenerarlos.
