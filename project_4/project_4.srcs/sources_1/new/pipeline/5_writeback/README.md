# `5_writeback/` — etapa WB

**Qué hace:** escribe en el banco de registros el valor que produce la instrucción.

En este diseño **no hay un módulo `wb`**: la etapa de writeback está repartida en
tres lugares, y este README los junta para que se entienda el camino completo.

```
                 ┌─────────────────────────────────────────────┐
                 │  mux wb_sel  (en riscv_pipeline.v)         │
                 └─────────────────────────────────────────────┘
                                    │
   mem_alu_out ─┐                   │
   mem_rdata    ─┼──▶ mem_result ───┴──▶ mem_wb_reg ──▶ wb_result ──▶ regfile.we
   mem_pc4      ─┤                        (regs/)                      (2_decode/)
   mem_imm      ─┘
```

---

## Las 3 partes

### 1. El mux `wb_sel` — en `riscv_pipeline.v`

```verilog
always @(*) begin
    case (mem_wb_sel)
        2'b00:   mem_result_r = mem_alu_out;   // resultado de la ALU
        2'b01:   mem_result_r = mem_rdata;      // dato leído de la dmem (load)
        2'b10:   mem_result_r = mem_pc4;        // PC+4 (JAL / JALR)
        default: mem_result_r = mem_imm;        // LUI
    endcase
end
```

`wb_sel` lo genera la `control` en la etapa ID y viaja con la instrucción.

| `wb_sel` | Fuente | Instrucciones |
|---|---|---|
| `00` | ALU | R, I-ALU, AUIPC, branches |
| `01` | dmem | load |
| `10` | `pc + 4` | JAL, JALR |
| `11` | inmediato U | LUI |

> `mem_result` también es la fuente del **forwarding** desde EX/MEM (`2'b10`):
> el valor que la instrucción de MEM produce se le reenvía a la de EX.

### 2. El registro `mem_wb_reg` — en [`regs/`](../regs/README.md)

Es el último registro de pipeline: retiene `mem_result`, `mem_rd` y `mem_reg_write`
un ciclo más.

### 3. La escritura al regfile — en [`2_decode/regfile.v`](../2_decode/README.md)

```verilog
regfile #(.BYPASS(1)) u_rf (
    .clk(clk), .rst(rst), .we(wb_reg_write & en),
    .waddr(wb_rd), .wdata(wb_result), ...
);
```

- El write enable es `wb_reg_write & en`: si la debug unit pausó el CPU, no se escribe.
- `BYPASS=1` hace que el write-through interno del regfile sea visible en el mismo
  ciclo en que se escribe (necesario porque el ID lee en paralelo al WB).

---

## El `halt` también pasa por acá

`mem_halt` viaja desde EX → EX/MEM → MEM/WB, y en WB:

```verilog
assign o_halt = wb_halt;
```

`o_halt` es un **nivel**: cuando vale 1, la debug unit lo ve y frena el CPU. Todo lo
anterior ya se retiró y ninguna instrucción posterior llegó a ejecutarse.

En paralelo, `halting_r` (en `riscv_pipeline.v`) es un flag **pegajoso** que se
enciende en el momento en que un halt llega a EX, para que el `fetch` pare
inmediatamente y no se ejecute ninguna instrucción posterior.

---

## Resumen del camino WB

| señal | de | a |
|---|---|---|
| `mem_alu_out` | EX | mux `wb_sel` |
| `mem_rdata` | dmem (MEM) | mux `wb_sel` |
| `mem_result` | mux `wb_sel` | `mem_wb_reg` **y** forwarding a EX |
| `wb_result` | `mem_wb_reg` | `regfile.wdata` |
| `wb_rd` | `mem_wb_reg` | `regfile.waddr` |
| `wb_reg_write` | `mem_wb_reg` | `regfile.we` |
| `wb_halt` | `mem_wb_reg` | `o_halt` |
