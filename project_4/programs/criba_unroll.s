# criba_unroll.s — Criba de Eratóstenes con Instruction Scheduling + Loop Unrolling (Factor 2)
# Reduce la sobrecarga de saltos y flushes inicializando 2 palabras por iteración

        addi x1, x0, 32         # N = 32
        addi x2, x0, 2          # i = 2

init_loop:                      # LOOP UNROLLING (Factor 2): 15 iteraciones en vez de 30
        slli x3, x2, 2
        sw   x0, 0(x3)          # dmem[i] = 0
        sw   x0, 4(x3)          # dmem[i+1] = 0
        addi x2, x2, 2          # i += 2
        blt  x2, x1, init_loop  # 14 saltos tomados en lugar de 29

        addi x2, x0, 2          # i = 2
outer_loop:
        slli x3, x2, 2
        lw   x4, 0(x3)          # x4 = dmem[i]
        addi x8, x0, 6          # Instruction Scheduling (0 stalls)
        bne  x4, x0, next_i     
        
        add  x5, x2, x2         # j = 2 * i
inner_loop:
        bge  x5, x1, next_i     
        slli x6, x5, 2
        addi x7, x0, 1
        sw   x7, 0(x6)          
        add  x5, x5, x2         
        j    inner_loop

next_i:
        addi x2, x2, 1
        blt  x2, x8, outer_loop 

        ebreak                  # HALT -> fin del benchmark
