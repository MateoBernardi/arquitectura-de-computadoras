# Tiny RV32I encoder + reference simulator used to generate the test vectors of tb_pipeline.
# Usage: python3 rv32i_model.py pipeline_test.s   -> writes pipeline_prog.hex / pipeline_exp.hex
# (copy them to project_4.srcs/sim_1/new/). exp = x0..x31 then dmem words 0..15.
import re,sys
M=0xFFFFFFFF
def sx(v,b): v&=(1<<b)-1; return v-(1<<b) if v>>(b-1) else v
R={'add':(0,0),'sub':(0,0x20),'sll':(1,0),'slt':(2,0),'sltu':(3,0),'xor':(4,0),'srl':(5,0),'sra':(5,0x20),'or':(6,0),'and':(7,0)}
I={'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7}
SH={'slli':(1,0),'srli':(5,0),'srai':(5,0x20)}
L={'lb':0,'lh':1,'lw':2,'lbu':4,'lhu':5}
S={'sb':0,'sh':1,'sw':2}
B={'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}
def reg(s): return int(s[1:])
def enc(ins,pc,labels):
    p=re.split(r'[,\s()]+',ins.strip()); p=[x for x in p if x]; op=p[0]
    def t(x): return labels[x]-pc if x in labels else int(x,0)
    if op in R: f3,f7=R[op]; return f7<<25|reg(p[3])<<20|reg(p[2])<<15|f3<<12|reg(p[1])<<7|0x33
    if op in I: return (int(p[3],0)&0xFFF)<<20|reg(p[2])<<15|I[op]<<12|reg(p[1])<<7|0x13
    if op in SH: f3,f7=SH[op]; return f7<<25|int(p[3],0)<<20|reg(p[2])<<15|f3<<12|reg(p[1])<<7|0x13
    if op in L: return (int(p[2],0)&0xFFF)<<20|reg(p[3])<<15|L[op]<<12|reg(p[1])<<7|0x03
    if op in S: i=int(p[2],0)&0xFFF; return (i>>5)<<25|reg(p[1])<<20|reg(p[3])<<15|S[op]<<12|(i&31)<<7|0x23
    if op in B:
        i=t(p[3])&0x1FFF; return (i>>12&1)<<31|(i>>5&63)<<25|reg(p[2])<<20|reg(p[1])<<15|B[op]<<12|(i>>1&15)<<8|(i>>11&1)<<7|0x63
    if op=='lui': return (int(p[2],0)&0xFFFFF)<<12|reg(p[1])<<7|0x37
    if op=='auipc': return (int(p[2],0)&0xFFFFF)<<12|reg(p[1])<<7|0x17
    if op=='jal':
        i=t(p[2])&0x1FFFFF; return (i>>20&1)<<31|(i>>1&0x3FF)<<21|(i>>11&1)<<20|(i>>12&0xFF)<<12|reg(p[1])<<7|0x6F
    if op=='jalr': return (int(p[2],0)&0xFFF)<<20|reg(p[3])<<15|reg(p[1])<<7|0x67
    if op=='ebreak': return 0x00100073
    raise Exception(ins)
def assemble(src):
    lines=[];labels={}
    for l in src.strip().splitlines():
        l=l.split('#')[0].strip()
        if not l: continue
        m=re.match(r'(\w+):\s*(.*)',l)
        if m: labels[m.group(1)]=4*len(lines); l=m.group(2)
        if l: lines.append(l)
    return [enc(l,4*i,labels) for i,l in enumerate(lines)],lines
def run(words):
    x=[0]*32; mem=bytearray(1024); pc=0
    for _ in range(10000):
        w=words[pc//4]; op=w&0x7F; rd=w>>7&31; f3=w>>12&7; r1=w>>15&31; r2=w>>20&31; f7=w>>25
        a,b=x[r1],x[r2]; npc=pc+4; res=None
        if op==0x33:
            k=(f3,f7); sh=b&31
            res={(0,0):a+b,(0,0x20):a-b,(1,0):a<<sh,(2,0):int(sx(a,32)<sx(b,32)),(3,0):int(a<b),(4,0):a^b,(5,0):a>>sh,(5,0x20):sx(a,32)>>sh,(6,0):a|b,(7,0):a&b}[k]
        elif op==0x13:
            im=sx(w>>20,12); sh=r2
            res={0:a+im,2:int(sx(a,32)<im),3:int(a<(im&M)),4:a^im,6:a|im,7:a&im,1:a<<sh,5:(sx(a,32)>>sh) if f7==0x20 else a>>sh}[f3]
        elif op==0x03:
            ad=(a+sx(w>>20,12))&M; n={0:1,1:2,2:4,4:1,5:2}[f3]
            v=int.from_bytes(mem[ad:ad+n],'little'); res=sx(v,8*n) if f3<3 else v
        elif op==0x23:
            ad=(a+sx((w>>25<<5)|(w>>7&31),12))&M; n={0:1,1:2,2:4}[f3]
            mem[ad:ad+n]=(b&((1<<8*n)-1)).to_bytes(n,'little')
        elif op==0x63:
            im=sx((w>>31&1)<<12|(w>>7&1)<<11|(w>>25&63)<<5|(w>>8&15)<<1,13)
            t={0:a==b,1:a!=b,4:sx(a,32)<sx(b,32),5:sx(a,32)>=sx(b,32),6:a<b,7:a>=b}[f3]
            if t: npc=(pc+im)&M
        elif op==0x37: res=w&0xFFFFF000
        elif op==0x17: res=pc+(w&0xFFFFF000)
        elif op==0x6F:
            im=sx((w>>31&1)<<20|(w>>12&0xFF)<<12|(w>>20&1)<<11|(w>>21&0x3FF)<<1,21); res=pc+4; npc=(pc+im)&M
        elif op==0x67: res=pc+4; npc=(a+sx(w>>20,12))&~1&M
        elif op==0x73: break
        if res is not None and rd: x[rd]=res&M
        pc=npc
    return x,mem
if __name__=='__main__':
    src=open(sys.argv[1]).read(); words,_=assemble(src)
    x,mem=run(words)
    open('pipeline_prog.hex','w').write(''.join('%08x\n'%w for w in words))
    open('pipeline_exp.hex','w').write(''.join('%08x\n'%v for v in x)+''.join('%08x\n'%int.from_bytes(mem[4*i:4*i+4],'little') for i in range(16)))
    print(len(words),'instrs; x=',[hex(v) for v in x])
