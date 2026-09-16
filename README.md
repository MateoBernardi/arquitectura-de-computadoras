# Arquitectura de Computadoras — Trabajos Prácticos de Laboratorio

Repositorio de implementaciones en hardware sobre FPGA para la cátedra de **Arquitectura de Computadoras**, correspondiente a la carrera de **Ingeniería en Computación** de la **Facultad de Ciencias Exactas, Físicas y Naturales (Universidad Nacional de Córdoba)**.

| Información | Detalle |
| :--- | :--- |
| **Institución** | Universidad Nacional de Córdoba (UNC) — FCEFyN |
| **Materia** | Arquitectura de Computadoras |
| **Carrera** | Ingeniería en Computación |
| **Integrantes** | Mateo Bernardi, Pablo Castilla |

---

## Índice
* [Trabajo Práctico N° 1: ALU Parametrizable y Banco de Registros](#trabajo-práctico-n-1-alu-parametrizable-y-banco-de-registros)
* [Trabajo Práctico N° 2: Interfaz UART e Integración con ALU](#trabajo-práctico-n-2-interfaz-uart-e-integración-con-alu)

---

# Trabajo Práctico N° 1: ALU Parametrizable y Banco de Registros

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
# Trabajo Práctico N° 2: Interfaz UART e Integración con ALU


---

## Herramientas y Entorno

* Entorno EDA: AMD Xilinx Vivado
* Lenguaje HDL: Verilog (IEEE 1364-2001)
* Placa Objetivo: Digilent Nexys 4 DDR (Xilinx Artix-7 XC7A100T-1CSG324C)
* Software de Validación: Python 3 con librería `pyserial`
* Control de Versiones: Git & GitHub

---

## Descripción del Diseño

Implementación de un transceptor serie UART (Universal Asynchronous Receiver-Transmitter) sobre FPGA para comandar la ALU desarrollada en el TP1 desde una computadora. El sistema recibe una trama binaria de 3 bytes vía puerto serie, procesa la operación combinacionalmente y responde con 1 byte que contiene el resultado.

### 1. Parámetros de la Comunicación UART
* Baud Rate: 19200 baudios
* Formato de Trama: 8N1 (8 bits de datos, sin paridad, 1 bit de parada)
* Sobremuestreo: 16 ticks por bit
* Generador de Baud Rate: Divisor de frecuencia módulo 325 ($100\,\text{MHz} / (19200 \times 16)$)

### 2. Protocolo de Comunicación
* **Entrada (PC -> FPGA):** Trama secuencial de 3 bytes:
  1. `Byte 1`: Código de Operación (Opcode de 6 bits en `[5:0]`).
  2. `Byte 2`: Operando A (8 bits con signo).
  3. `Byte 3`: Operando B (8 bits con signo).
* **Salida (FPGA -> PC):** 1 byte con el resultado computado por la ALU.
> *Nota sobre Flags:* Las banderas de estado (`o_z` y `o_o`) se computan internamente en la instancia de la ALU pero no son retransmitidas por la UART para mantener el protocolo estricto de 1 byte de respuesta.

### 3. Arquitectura de Módulos
* **`baud_rate_gen.v`:** Genera un pulso (`o_tick`) con una tasa 16 veces superior al baud rate para el sobremuestreo de las líneas serie.
* **`uart_rx.v`:** Receptor serie asíncrono implementado mediante una FSM (IDLE, START, DATA, STOP) con muestreo centrado en el punto medio de cada bit.
* **`uart_tx1.v`:** Transmisor serie asíncrono con serialización de datos de 8 bits y generación de bits de start y stop.
* **`fifo.v`:** Buffer circular reutilizado tanto para la cola de recepción (`RX_FIFO`) como para la de transmisión (`TX_FIFO`) con profundidad parametrizable (`PTR_LEN = 2`, 4 palabras).
* **`uart_core.v`:** Integra el generador de baudios, el receptor, el transmisor y ambas FIFOs.
* **`interface.v` (`uart_interface`):** FSM que orquesta la lectura de los 3 bytes desde la FIFO de recepción, alimenta la ALU de forma combinacional y escribe el resultado en la FIFO de transmisión.
* **`top.v`:** Módulo de jerarquía superior que interconecta `uart_core`, `uart_interface` y `alu_tp1`.

### 4. Asignación de Hardware (Nexys 4 DDR)
* Reloj del Sistema (`i_clk`): Oscilador on-board de 100 MHz (Pin `E3`).
* Reset General (`i_reset`): Pulsador central BTNC (Pin `N17`, activo alto).
* Línea UART RX (`i_rx`): Pin `C4` (Conexión al canal TX del puente USB-UART FTDI).
* Línea UART TX (`o_tx`): Pin `D4` (Conexión al canal RX del puente USB-UART FTDI).

---

## Verificación y Validación en Hardware

La validación funcional de extremo a extremo se realiza conectando la placa mediante el cable USB a la PC y ejecutando el script `hw_validate.py`:

* Comunicación bidireccional sobre el puerto COM virtual asignado por el driver FTDI.
* Generación de vectores de prueba aleatorios (Opcode, Operando A, Operando B).
* Comparación automática en tiempo de ejecución entre la respuesta recibida por UART y el resultado esperado del modelo de referencia en Python.
