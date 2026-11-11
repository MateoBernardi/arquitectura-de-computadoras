# expect: 4 fault
.option norvc
.globl _start
_start:
  li a0, 3
fault: lh a1, 0(a0)
  ebreak
