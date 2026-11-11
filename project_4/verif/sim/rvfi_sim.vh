// Interfaz RVFI en simulación: la misma que usa riscv-formal (riscv_pipeline.v,
// bloque `ifdef RISCV_FORMAL`). tb.sv cuenta con ella las instrucciones retiradas.
`define RISCV_FORMAL
`define RISCV_FORMAL_NRET 1
`define RISCV_FORMAL_XLEN 32
`define RISCV_FORMAL_ILEN 32
`include "rvfi_macros.vh"
