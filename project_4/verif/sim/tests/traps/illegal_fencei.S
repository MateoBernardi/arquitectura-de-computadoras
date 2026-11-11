# expect: 2 fault
.option norvc
.globl _start
_start:
fault: .word 0x0000100f          # fence.i (sin Zifencei)
  ebreak
