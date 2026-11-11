# `flow/` — el control de flujo entre etapas

Los módulos que no pertenecen a una sola etapa: cada uno mira dos o tres etapas a la vez y
decide algo sobre el pipeline entero. Los cuatro son combinacionales; sus decisiones las
aplican los registros de pipeline y el PC en el flanco siguiente.

| Módulo | Mira | Decide |
|---|---|---|
| `hazard_unit` | ID y EX | frenar un ciclo por un load-use |
| `forward_unit` | EX, MEM y WB | de dónde sale cada operando de EX |
| `flush_unit` | EX | descartar las instrucciones detrás de un salto tomado |
| `trap_unit` | EX | si el salto o el acceso a memoria de EX es una excepción |

Diagramas: entradas a la izquierda y salidas a la derecha, con su ancho en bits. En cada salida, **R** = sale de un registro (cambia en el flanco del reloj) y **C** = combinacional (cambia apenas cambian las entradas).

## `hazard_unit` — stall de load-use

Un load recién tiene su dato al final de MEM, después de leer la dmem. Adelantarlo de ahí a
EX en el mismo ciclo encadenaría la lectura de la dmem, el forwarding y la ALU: era el camino
crítico del CPU, y con él el sistema no pasaba de 50 MHz. Por eso el dato de un load solo
se adelanta desde WB, y si la instrucción que viene detrás lo usa, tiene que esperar: el
pipeline frena IF e ID un ciclo y mete una burbuja en EX. Cuando la instrucción llega a EX,
el load ya está en WB. (La evaluación que llevó a esto, con la otra opción, que era sacar el
stall, está en [`verif/README.md`](../../../verif/README.md#variantes-probar-ideas-sin-vivado).)

```
lw   x5, 0(x6)     ← en EX: es un load y escribe x5
add  x7, x5, x1    ← en ID: lee x5  →  stall
```

```
                 ┌──────────────────────┐
ex_mem_read 1 ──▶│                      │──▶ stall 1  C
ex_rd       5 ──▶│     hazard_unit      │
id_rs1      5 ──▶│   [combinacional]    │
id_rs2      5 ──▶│                      │
id_opcode   7 ──▶│                      │
                 └──────────────────────┘
```

`stall` = la instrucción de EX es un load, su destino no es x0 y coincide con `rs1` o `rs2`
de la de ID. La política base frena aunque la instrucción de ID no use realmente ese campo
(por ejemplo, el `rs2` de una instrucción con inmediato): es conservadora, nunca incorrecta.
`id_opcode` no lo usa la política base; está para las variantes de `verif/variants/`, que
proponen otras políticas y se evalúan con la misma verificación.

## `forward_unit` — forwarding

Una instrucción en EX puede necesitar un registro que una instrucción anterior todavía no
escribió en el regfile, porque está en MEM o en WB. En vez de esperar, se le pasa el valor
directamente desde ahí.

```
                   ┌──────────────────────┐
ex_rs1        5 ──▶│                      │──▶ forward_a 2  C
ex_rs2        5 ──▶│                      │──▶ forward_b 2  C
mem_rd        5 ──▶│     forward_unit     │
mem_reg_write 1 ──▶│   [combinacional]    │
wb_rd         5 ──▶│                      │
wb_reg_write  1 ──▶│                      │
                   └──────────────────────┘
```

| `forward_a` / `forward_b` | El operando sale de |
|---|---|
| `00` | el regfile (no hay dependencia) |
| `10` | EX/MEM: la instrucción inmediatamente anterior (su resultado de la ALU, pc+4 o el inmediato de LUI; nunca el dato de un load, ver `hazard_unit`) |
| `01` | MEM/WB: la de dos instrucciones antes |

Si las dos escriben el registro, gana EX/MEM: es el valor más reciente. x0 nunca se reenvía.

## `flush_unit` — salto tomado

Los saltos se resuelven en EX. Cuando uno se toma, las dos instrucciones que entraron detrás
(en IF y en ID) son del camino equivocado y se descartan: IF/ID pasa a NOP e ID/EX a burbuja.
Por eso un salto tomado cuesta 2 ciclos.

```
              ┌──────────────────────┐
redirect 1 ──▶│                      │──▶ flush_if_id 1  C
              │      flush_unit      │──▶ flush_id_ex 1  C
              │   [combinacional]    │
              │                      │
              └──────────────────────┘
```

Hoy las dos salidas son `redirect`: el módulo deja explícita la decisión y el lugar donde
cambiarla. El pipeline les suma los otros motivos para vaciar esas etapas: el stall
(burbuja en ID/EX) y el CPU deteniéndose (nada posterior se ejecuta).

## `trap_unit` — excepciones de EX

Las excepciones que dependen de valores calculados en EX: el destino de un salto y la
dirección de un load o store. Las de ID (ilegal, `ecall`, `ebreak`, fuera de la imem) llegan
con la instrucción.

```
                      ┌──────────────────────┐
redirect         1 ──▶│                      │──▶ exc    1  C
redirect_target 32 ──▶│                      │──▶ cause  4  C
mem_read         1 ──▶│      trap_unit       │──▶ tval  32  C
mem_write        1 ──▶│   [combinacional]    │
funct3           3 ──▶│                      │
addr            32 ──▶│                      │
                      └──────────────────────┘
```

| Condición | Causa |
|---|---|
| salto tomado a una dirección no múltiplo de 4 | 0 (el trap es del salto: el PC nunca queda desalineado) |
| media palabra en dirección impar, palabra en dirección no múltiplo de 4 | 4 (load) / 6 (store) |
| dirección fuera de la dmem | 5 (load) / 7 (store) |

Desalineado tiene prioridad sobre fuera de rango. `tval` es la dirección que falló.

| Parámetro | En el sistema | Para qué |
|---|---|---|
| `DMEM_BYTES` | 1024 | las direcciones válidas de la dmem son [0, `DMEM_BYTES`) |
