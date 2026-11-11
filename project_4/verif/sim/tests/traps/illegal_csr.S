# expect: 2 fault
.option norvc
.globl _start
_start:
fault: .word 0x30002573          # csrr a0, mstatus (sin Zicsr)
  ebreak
