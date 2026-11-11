# suma_arreglo.s — suma un arreglo de 64 palabras: cada elemento se usa justo
# después de cargarlo (load-use en cada iteración). Resultado en x10 y en dmem[64].
        addi x1, x0, 0          # puntero
        addi x2, x0, 256        # fin (64 palabras)
init:   srli x3, x1, 2          # dmem[i] = i
        sw   x3, 0(x1)
        addi x1, x1, 4
        blt  x1, x2, init

        addi x1, x0, 0
        addi x10, x0, 0
loop:   lw   x4, 0(x1)
        add  x10, x10, x4       # usa el dato recién cargado
        addi x1, x1, 4
        blt  x1, x2, loop
        sw   x10, 0(x2)         # 0+1+...+63 = 2016
        ebreak
