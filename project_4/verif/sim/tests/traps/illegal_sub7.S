# expect: 2 fault
.option norvc
.globl _start
_start:
fault: .word 0x40001033 | (1<<25) # funct7 inválido en OP
  ebreak
