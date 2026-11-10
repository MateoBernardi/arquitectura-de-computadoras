# expect: 3 fault
.option norvc
.globl _start
_start:
  li a0, 1
  beq x0, x0, 1f
  lw a1, 0(a0)
  sw a1, 0(a0)
1:
fault: ebreak
  ebreak
