# expect: 1 0x00800000
.option norvc
.globl _start
_start:
  li a0, 0x00800000
  jalr x0, 0(a0)
  ebreak
