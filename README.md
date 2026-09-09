# Trabajo Práctico N° 1: ALU Parametrizable y Banco de Registros

**Materia:** Arquitectura de Computadoras
**Carrera:** Ingeniería en Computación
**Institución:** Facultad de Ciencias Exactas, Físicas y Naturales (Universidad Nacional de Córdoba)

### Integrantes
* Mateo Bernardi
* Pablo Castilla

---

## Herramientas y Entorno

* Entorno EDA: AMD Xilinx Vivado
* Lenguaje HDL: Verilog (IEEE 1364-2001)
* Placa Objetivo: Digilent Basys 3 (Xilinx Artix-7 XC7A35T-1CPG236C)
* Control de Versiones: Git & GitHub


---

## Descripción del Diseño

Implementación en FPGA de una Unidad Aritmético Lógica (ALU) con bus de datos parametrizable (NB_DATA), acompañada de un banco de registros para la captura secuencial de datos mediante la interfaz física de la placa.

### 1. Operaciones Soportadas
La ALU decodifica operaciones mediante un bus de control de 6 bits (NB_OP = 6):

| Operación | Código (Binario) | Descripción |
| :--- | :---: | :--- |
| ADD | 100000 | Suma aritmética con signo (A + B) |
| SUB | 100010 | Resta aritmética con signo (A - B) |
| AND | 100100 | Operación lógica bit a bit AND (A y B) |
| OR  | 100101 | Operación lógica bit a bit OR (A o B) |
| XOR | 100110 | Operación lógica bit a bit XOR (A xor B) |
| SRA | 000011 | Desplazamiento aritmético a la derecha (Shift Right Arithmetic) |
| SRL | 000010 | Desplazamiento lógico a la derecha (Shift Right Logical) |
| NOR | 100111 | Operación lógica bit a bit NOR (not (A o B)) |

### 2. Banderas de Estado (Flags)
* Zero Flag (f_z): Se pone en alto (1) cuando el resultado de la operación actual es idéntico a cero.
* Overflow Flag (f_o): Detecta desbordamiento aritmético con signo en operaciones de suma y resta (ADD y SUB).

### 3. Asignación de Hardware (Basys 3)
* Bus de Entrada (switch[7:0]): 8 interruptores (SW0 a SW7) para ingresar operandos y códigos de operación.
* Pulsadores de Carga de Registros:
  * button[0] (T18): Registra el valor de los switches en el Operando A.
  * button[1] (U18): Registra el valor de los switches en el Operando B.
  * button[2] (U17): Registra los switches en el Código de Operación.
* Reset (i_reset): Botón derecho (T17).
* Reloj del Sistema (i_clk): Oscilador interno de 100 MHz (W5).
* Visualización:
  * LEDs LD0 a LD7: Muestran el resultado de la ALU de 8 bits.
  * LED LD14 (f_o): Indicador de Overflow.
  * LED LD15 (f_z): Indicador de Cero.

---

## Verificación y Simulación

El diseño fue validado mediante simulación conductual utilizando testbenches con generación de entradas pseudoaleatorias y comprobación automática de resultados (self-checking testbench):

* Casos ejecutados: 177 tests
* Resultado: 177/177 OK (0 fallos) — RESULTADO: PASS

---

