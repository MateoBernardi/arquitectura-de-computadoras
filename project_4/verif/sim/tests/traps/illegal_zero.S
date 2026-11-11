# expect: 2 fault
.option norvc
.globl _start
_start:
fault: .word 0x00000000
  ebreak
