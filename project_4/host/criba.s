# criba.s — Marca números primos del 2 al 31 en dmem[0..31]
# dmem[k] = 0 -> PRIMO | dmem[k] = 1 -> COMPUESTO

        addi x1, x0, 32         # N = 32
        addi x2, x0, 2          # i = 2

init_loop:                      # Inicializa dmem[2..31] en 0
        slli x3, x2, 2
        sw   x0, 0(x3)
        addi x2, x2, 1
        blt  x2, x1, init_loop

        addi x2, x0, 2          # i = 2
outer_loop:
        slli x3, x2, 2
        lw   x4, 0(x3)          # x4 = dmem[i]
        bne  x4, x0, next_i     # si no es primo, continuar
        
        add  x5, x2, x2         # j = 2 * i
inner_loop:
        bge  x5, x1, next_i     # si j >= N, fin inner
        slli x6, x5, 2
        addi x7, x0, 1
        sw   x7, 0(x6)          # dmem[j] = 1 (marcar compuesto)
        add  x5, x5, x2         # j += i
        j    inner_loop

next_i:
        addi x2, x2, 1
        addi x8, x0, 6          # corte en sqrt(32) aprox 6
        blt  x2, x8, outer_loop

        ebreak                  # HALT -> señaliza fin del benchmark