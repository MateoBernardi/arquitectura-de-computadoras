# `sim_1/new/` — testbenches

Testbenches de simulación y los archivos de referencia.

| Archivo | Qué es |
|---|---|
| `tb_top_riscv.v` | **el principal**: testbench autoverificado del sistema completo (`top_riscv`) |
| `tb_pipeline.v` | testbench autoverificado del pipeline solo (`riscv_pipeline`) |
| `tb_riscv_core.v` | testbench del core single-cycle (`riscv_core.v`) — **sin usar** |
| `tb_full.v` | **sin usar** |
| `pipeline_prog.hex` | programa de prueba (`$readmemh`) |
| `pipeline_exp.hex` | resultado esperado: 32 palabras de registros + 16 de dmem |
| `program.mem` | programa en formato `.mem` |

> En Vivado el top de simulación es `tb_top_riscv` (lo define `add_sources.tcl`).

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
   `pipeline_exp.hex`.
5. `pause`.
6. `reset`.
7. Recarga con **relleno de NOP** (programa más corto que el declarado).
8. Programa **demasiado grande**.
9. **Comando desconocido**.

**Notas**

- El `BAUD_RATE` de simulación es alto para que corra rápido (un bit = 128 clocks).
- Los `.hex` tienen que estar en el directorio de simulación.
- En XSIM: `run -all`.

---

## `tb_pipeline.v` — el testbench del pipeline

Prueba el `riscv_pipeline` **directamente**, sin la UART.

**Qué verifica**

1. Carga `PROG_FILE` en la `imem`.
2. Corre hasta `o_halt`.
3. Compara x0..x31 y las primeras 16 palabras de la dmem contra `EXP_FILE`
   (32 + 16 palabras, formato `$readmemh`).
4. Que **nada después del EBREAK** se haya ejecutado (se verifica a través del
   `EXP_FILE`).
5. Que la **pausa** (`i_enable = 0`) congele el pipeline.

**De dónde salen los archivos de referencia**

Los `.hex` de referencia los genera el **modelo en Python de RV32I** que está en
`host/tests/rv32i_model.py`. Es la misma fuente de verdad que usan los tests del
host, así que si cambia el CPU hay que regenerar los `.hex`.

---

## `tb_riscv_core.v` y `tb_full.v`

Testbenches de restos de TP1: `riscv_core.v` es el core **single-cycle** y `tb_full.v`
no lo usa nadie. Ambos están en el proyecto pero **no participan** de nada.

Si se limpian los archivos muertos (ver la sección de estructura del
[README general](../../../../../README.md)), estos dos también se van.
