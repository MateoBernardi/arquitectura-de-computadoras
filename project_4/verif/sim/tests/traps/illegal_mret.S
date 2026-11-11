# expect: 2 fault
.option norvc
.globl _start
_start:
fault: .word 0x30200073          # mret
  ebreak
