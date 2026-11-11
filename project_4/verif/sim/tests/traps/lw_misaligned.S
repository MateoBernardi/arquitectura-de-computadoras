# expect: 4 fault
.option norvc
.globl _start
_start:
  li a0, 2
fault: lw a1, 0(a0)
  ebreak
