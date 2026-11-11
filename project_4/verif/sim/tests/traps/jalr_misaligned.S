# expect: 0 fault
.option norvc
.globl _start
_start:
  la a0, target
  addi a0, a0, 2
fault: jalr ra, 0(a0)
  nop
target: nop
  ebreak
