// rvmodel_macros.h: macros de ACT para el CPU de project_4 en el simulador (sim/tb.sv).
// Basadas en config/cores/picorv32 de riscv-arch-test.
// SPDX-License-Identifier: Apache-2.0

#ifndef _RVMODEL_MACROS_H
#define _RVMODEL_MACROS_H

// STANDARD_SM_SUPPORTED queda sin definir: el CPU no tiene CSRs ni modos de privilegio,
// así que no se genera código de arranque ni manejador de traps.

#define RVMODEL_DATA_SECTION

// Direcciones del testbench (sim/tb.sv), al final de los 8 MB de RAM.
#define TP4_TOHOST  0x007FFFF0
#define TP4_CONSOLE 0x007FFFF4

// PASS: TOHOST = 1 y ebreak (halt). FAIL: TOHOST = 3 y ebreak.
// El testbench termina al detenerse el CPU y decide por el valor de TOHOST.
#define RVMODEL_HALT_PASS  \
  li x1, 1                ;\
  li t0, TP4_TOHOST       ;\
  sw x1, 0(t0)            ;\
  self_loop_pass:         ;\
    ebreak                ;\
    j self_loop_pass      ;

#define RVMODEL_HALT_FAIL  \
  li x1, 3                ;\
  li t0, TP4_TOHOST       ;\
  sw x1, 0(t0)            ;\
  self_loop_fail:         ;\
    ebreak                ;\
    j self_loop_fail      ;

// Un store a TP4_CONSOLE escribe un carácter (el byte bajo) en la salida del simulador.
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) \
1:                           ;                        \
  lbu  _R1, 0(_STR_PTR)      ;                        \
  beqz _R1, 3f               ;                        \
  li   _R2, TP4_CONSOLE      ;                        \
  sw   _R1, 0(_R2)           ;                        \
  addi _STR_PTR, _STR_PTR, 1 ;                        \
  j 1b                       ;                        \
3:

// Requeridas por tests/env/check_defines.h aunque no haya interrupciones.
#define RVMODEL_INTERRUPT_LATENCY 10
#define RVMODEL_TIMER_INT_SOON_DELAY 10000

#endif // _RVMODEL_MACROS_H
