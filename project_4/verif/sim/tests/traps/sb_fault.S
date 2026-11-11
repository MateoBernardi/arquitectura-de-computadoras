# expect: 7 fault
.option norvc
.globl _start
_start:
  li a0, -1
fault: sb a1, 0(a0)
  ebreak
