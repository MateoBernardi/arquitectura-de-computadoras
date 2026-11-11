# sim/ — simulación del CPU con Verilator

Corre el RTL real (`riscv_pipeline` y todos sus módulos, sin cambios) con
[Verilator](https://verilator.org). No hace falta Vivado.

```bash
./build.sh [variante]   # compila build/<base|variante>/Vtb
./run_act.sh            # suite oficial riscv-arch-test (ACT4) contra Sail
./run_traps.sh          # tests dirigidos de excepciones
./bench.py              # tabla de rendimiento: diseño base contra cada variante
./run_system.sh         # sistema completo (UART + debug unit + CPU), con Icarus
./run_elf.sh prog.elf   # un programa cualquiera
```

`VARIANT=<nombre>` antes de `run_act.sh`, `run_traps.sh` o `run_elf.sh` usa el simulador
de esa variante, por ejemplo `VARIANT=hazard_unit_nostall ./run_act.sh`.

## Cómo funciona

`tb.sv` instancia `riscv_pipeline` con memorias de **8 MB**, solo en simulación
(`IMEM_ADDR_W = 23`, `DMEM_DEPTH = 2^21`; en la FPGA siguen siendo de 1 KB). La imagen del
programa se carga igual en la imem y en la dmem, porque el código y los datos de un ELF
comparten el espacio de direcciones. El CPU corre hasta que se detiene (`o_halt`).

| Dirección | Uso |
|---|---|
| `0x007FFFF0` (TOHOST) | el programa escribe 1 (PASS) o 3 (FAIL) antes de `ebreak` |
| `0x007FFFF4` (CONSOLE) | un store escribe un carácter en la salida |

El simulador termina con código 0 (PASS) si `TOHOST = 1` al detenerse. Con
`+expect-cause=N [+expect-pc=X]`, en cambio, decide la causa y el PC del trap.

Al detenerse informa:
- **ciclos**: los ciclos en los que el CPU avanzó, como los cuenta la debug unit en la
  placa;
- **instrucciones** retiradas: las cuenta con `rvfi_valid`, la misma interfaz que usa
  riscv-formal;
- una **firma** del estado final (x1..x31 y las 256 palabras de la dmem).

La criba (`host/criba.s`) da 322 instrucciones y 457 ciclos, exactamente lo medido en
la placa (`../BENCHMARK_ANALYSIS.md`).

## Variantes y rendimiento (`bench.py`)

Una variante (`../verif/variants/<nombre>.v`) declara un módulo con el mismo nombre y los
mismos puertos que uno del RTL, y `build.sh <nombre>` la compila en lugar del archivo
original. `bench.py` compila el diseño base y cada variante, corre los mismos programas
y arma la tabla (también en `work/bench.md`). Para cada programa, una variante tiene que
terminar con **la misma firma y la misma cantidad de instrucciones** que el diseño base.
Si no, se marca INCORRECTA. Se probó con una `forward_unit` sin forwarding desde MEM:
queda marcada en todos los programas, aunque en varios "gana" ciclos.

| Programa | Instrucciones | `base` ciclos (CPI) | `hazard_unit_nostall` | `hazard_unit_precise` |
|---|---|---|---|---|
| criba | 322 | 457 (1.419) | 453 (1.407) −0.9 % | 457 (1.419) +0.0 % |
| criba_opt | 322 | 453 (1.407) | 453 (1.407) +0.0 % | 453 (1.407) +0.0 % |
| criba_unroll | 277 | 378 (1.365) | 378 (1.365) +0.0 % | 378 (1.365) +0.0 % |
| suma_arreglo | 518 | 837 (1.616) | 773 (1.492) −7.6 % | 837 (1.616) +0.0 % |
| pipeline_test | 61 | 83 (1.361) | 82 (1.344) −1.2 % | 83 (1.361) +0.0 % |
| test_bypass | 6 | 9 (1.500) | 9 (1.500) +0.0 % | 9 (1.500) +0.0 % |
| ACT (39 tests) | 124 057 | 165 575 (1.335) | 153 382 (1.236) −7.4 % | 165 285 (1.332) −0.2 % |

`bench/suma_arreglo.s` usa cada dato justo después de cargarlo: es el caso que la
variante sin stall acelera. En las cribas, el load-use es raro (criba_opt y
criba_unroll ya reordenaron el código para evitarlo).

## riscv-arch-test (ACT4)

[riscv-arch-test](https://github.com/riscv/riscv-arch-test) es la suite oficial de
RISC-V International. Cada test es un ELF **autoverificado**. ACT corre el programa en
[Sail](https://github.com/riscv/sail-riscv), el modelo de referencia formal de la ISA,
guarda los resultados y los compila dentro del ELF. En el CPU, el test compara cada
resultado con el esperado e imprime `RVCP-SUMMARY: TEST PASSED` o `TEST FAILED`, con el
detalle de la primera diferencia.

La configuración del DUT está en `act/tp4-rv32i/` y se basa en la de **picorv32**, que
también es un core sin CSRs:

| Archivo | Contenido |
|---|---|
| `tp4-rv32i.yaml` | qué implementa el CPU (UDB): RV32I, sin Zicsr, excepciones precisas, load/store desalineado = excepción |
| `sail.json` | la misma configuración, para Sail; memoria de 8 MB en `0x0` |
| `link.ld` | el programa empieza en `0x0` (el PC de reset) |
| `rvmodel_macros.h` | PASS/FAIL (TOHOST + `ebreak`) y consola |
| `test_config.yaml` | compilador (GCC 15) y Sail |

Sin la arquitectura privilegiada, ACT selecciona la suite **I**: 39 tests que cubren
las 37 instrucciones de cómputo, memoria y saltos, además de FENCE, con los casos borde
de cada una. Las excepciones no están en esta suite, porque ACT las prueba con un
manejador de traps en M-mode. Las cubren riscv-formal (`../verif/rvfi/`) y
`run_traps.sh`.

**Resultado: 39/39 PASS.** La suite detecta errores reales: con SLTU invertido en la ALU,
fallan `I-sltu-00` e `I-sltiu-00`.

## Tests de excepciones (`tests/traps/`)

Cada test declara en su primera línea la causa y la instrucción esperadas
(`# expect: <causa> <pc>`). Cubren todas las causas: ilegales (cero, `csrr`, `fence.i`,
`mret`, `funct7` inválido, comprimida), `ecall`, `ebreak`, loads y stores desalineados o
fuera de la dmem, saltos (JALR y branch) a direcciones no alineadas, un salto fuera de la
imem, y dos casos en los que **no** tiene que haber trap: una instrucción ilegal y un load
desalineado en el camino equivocado de un salto tomado.

## Sistema completo (`run_system.sh`)

Corre el testbench de Vivado `../project_4.srcs/sim_1/new/tb_top_riscv.v` con Icarus
Verilog. Maneja `top_riscv` por la línea serie, igual que el host de Python:
- carga el programa y verifica la imem;
- step, run hasta el halt, dump;
- compara registros y dmem contra el modelo, y la causa del halt (`ebreak` en su PC);
- trap por instrucción ilegal: la instrucción anterior se retira y la posterior no;
- pausa, reset, programa demasiado grande y comando desconocido.

**46 chequeos, PASS.**

## Instalación

Además de `.tools/oss-cad-suite` (Verilator):

```bash
cd .tools
# Sail (modelo de referencia)
mkdir -p sail && curl -L https://github.com/riscv/sail-riscv/releases/download/0.16/sail-riscv-Linux-x86_64.tar.gz \
    | tar xz -C sail --strip-components=1
# GCC 15 (ACT4 lo exige; xPack trae multilib rv32i)
curl -L https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz | tar xz
# riscv-arch-test y sus dependencias (uv, Ruby, vía mise)
git clone https://github.com/riscv/riscv-arch-test.git
cd riscv-arch-test && mise trust .mise.toml && mise install
```
