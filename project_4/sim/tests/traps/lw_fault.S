# expect: 5 fault
.option norvc
.globl _start
_start:
  li a0, 0x00800000
fault: lw a1, 0(a0)
  ebreak
