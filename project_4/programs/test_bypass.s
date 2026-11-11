# test_bypass.s - Demuestra el riesgo de lectura/escritura simultánea en el banco de registros
# Distancia 3: Inst 1 escribe x1; Inst 2 y 3 no lo tocan; Inst 4 lee x1.

        addi x1, x0, 100        # Inst 1: escribe x1 = 100 (estará en WB cuando Inst 4 esté en ID)
        addi x3, x0, 1          # Inst 2 (en MEM cuando Inst 4 esté en ID)
        addi x4, x0, 2          # Inst 3 (en EX cuando Inst 4 esté en ID)
        add  x5, x1, x1         # Inst 4: lee x1 en ID (con BYPASS=1 lee 100 -> x5=200; con BYPASS=0 lee 0 -> x5=0!)
        sw   x5, 0(x0)          # Guarda x5 en dmem[0]
        ebreak                  # Halt
