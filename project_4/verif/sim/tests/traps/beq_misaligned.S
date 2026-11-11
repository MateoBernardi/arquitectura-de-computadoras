# expect: 0 fault
.option norvc
.globl _start
_start:
fault: .word 0x00000363          # beq x0, x0, +6
  ebreak
