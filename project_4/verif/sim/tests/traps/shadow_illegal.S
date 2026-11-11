# expect: 3 fault
.option norvc
.globl _start
_start:
  j 1f
  .word 0
  .word 0
1:
fault: ebreak
  ebreak
