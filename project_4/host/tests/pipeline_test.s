addi x1,x0,5
addi x2,x0,10
add x3,x1,x2
sub x4,x3,x1
sw x3,0(x0)
lw x5,0(x0)
add x6,x5,x5
beq x6,x3,skip1
addi x7,x0,1
bne x6,x3,L1
addi x7,x0,99
L1: addi x7,x7,2
lui x8,0x12345
addi x8,x8,0x678
jal x9,F
addi x10,x0,77
F: auipc x11,0
addi x12,x0,80
jalr x13,0(x12)
addi x14,x0,55
T: slt x15,x2,x1
sltu x16,x1,x2
sll x17,x2,x1
srl x18,x17,x1
addi x19,x0,-8
sra x20,x19,x1
srai x21,x19,1
xori x22,x19,255
sb x19,5(x0)
sh x8,8(x0)
lb x23,5(x0)
lbu x24,5(x0)
lh x25,8(x0)
lhu x26,8(x0)
addi x27,x0,0
addi x28,x0,1
loop: add x27,x27,x28
addi x28,x28,1
addi x29,x28,-7
blt x29,x0,loop
bge x27,x28,skip1
sw x27,12(x0)
skip1: add x30,x27,x27
sw x30,16(x0)
ebreak
addi x31,x0,1
sw x31,20(x0)
