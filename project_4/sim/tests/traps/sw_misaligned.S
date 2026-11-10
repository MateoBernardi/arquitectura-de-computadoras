# expect: 6 fault
.option norvc
.globl _start
_start:
  li a0, 1
fault: sw a1, 0(a0)
  ebreak
