# expect: 3 fault
.option norvc
.globl _start
_start:
fault: ebreak
  ebreak
