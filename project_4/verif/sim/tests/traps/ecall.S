# expect: 11 fault
.option norvc
.globl _start
_start:
fault: ecall
  ebreak
