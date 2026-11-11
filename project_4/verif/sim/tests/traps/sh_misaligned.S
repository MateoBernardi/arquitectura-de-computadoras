# expect: 6 fault
.option norvc
.globl _start
_start:
  li a0, 5
fault: sh a1, 0(a0)
  ebreak
