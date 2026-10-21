# `top/` — `top_riscv`

**Qué hace:** el top del hardware para la **Nexys4 DDR**. Une la UART, la debug
unit y el CPU, y maneja el reloj y el reset.

```
                        ┌──────────────┐
        i_clk ─────────▶│  MMCM (opcional) │──▶ clk (50 MHz)
                        └──────┬───────┘
                               │
        i_reset ──▶ reset_gen ─┴──▶ sys_reset
                               │
        i_rx ─────▶ sync_2ff ─────┐
                                  ▼
                            uart_core ──▶ o_tx
                                  │
                                  ▼
                            debug_unit ──▶ o_cpu_enable, o_cpu_reset
                                  │
                                  ▼
                            riscv_pipeline ──▶ o_halt
                                  │
        o_led = {cpu_halt, cpu_reset, cpu_enable}
```

---

## `top_riscv.v` — `top_riscv`

**Entradas / salidas**

| Puerto | Ancho | Descripción |
|---|---|---|
| `i_clk` | 1 | reloj de la placa (100 MHz) |
| `i_reset` | 1 | botón de reset |
| `i_rx` | 1 | línea RX del puerto serie |
| `o_tx` | 1 | línea TX del puerto serie |
| `o_led` | 3 | `[0]` CPU habilitado, `[1]` CPU en reset (carga), `[2]` halt |

**Parámetros**

| Parámetro | Default | Para qué |
|---|---|---|
| `CLK_FREQ` | 100_000_000 | frecuencia de `i_clk` |
| `USE_MMCM` | 1 | 1 → el sistema corre a `CLK_FREQ/2`; 0 → usa `i_clk` directo (simulación) |
| `BAUD_RATE` | 19_200 | |
| `N_TICKS` | 16 | sobremuestreo del UART |
| `PTR_LEN` | 2 | profundidad de los FIFOs (4 palabras) |
| `IMEM_ADDR_W` | 10 | imem de 1 KB = 256 instrucciones |

---

## El reloj: por qué el MMCM

El camino crítico del pipeline (`dmem` → forwarding → ALU → branch → flush) **no
cierra a 100 MHz** (WNS ≈ −5 ns post-ruteo). Con `USE_MMCM = 1` (default) todo el
sistema corre a **`CLK_FREQ/2` = 50 MHz**, generado con un `MMCME2_BASE`:

```verilog
MMCME2_BASE #(
    .CLKIN1_PERIOD  (1.0e9 / CLK_FREQ),
    .CLKFBOUT_MULT_F(10.0),        // VCO = CLK_FREQ * 10
    .CLKOUT0_DIVIDE_F(20.0),       // CLK_FREQ / 2
    .DIVCLK_DIVIDE  (1)
) u_mmcm (...);
```

- El VCO va a 1000 MHz y la salida dividida por 20 → **50 MHz**.
- `BUFG` (`u_fb`, `u_out`) entre el MMCM y el resto del diseño, como pide Vivado.
- El **baud rate se calcula con la frecuencia interna** (`SYS_FREQ`), no con
  `CLK_FREQ`, así que el UART sigue funcionando a 19200 baud.

Con `USE_MMCM = 0` el reloj es `i_clk` directo: es lo que se usa en simulación.

`locked` se mete al reset: si el MMCM todavía no enganchó, el sistema está en reset.

---

## El reset

```
reset_gen u_reset (
    .i_clk      (clk),
    .i_btn_reset(i_reset | ~locked),
    .o_reset    (sys_reset)
);
```

- `reset_gen` (en [`../common/`](../common/README.md)) genera el reset de power-on y
  sincroniza el botón.
- El reset del **sistema** (`sys_reset`) resetea la UART y la debug unit.
- El **CPU** no recibe `sys_reset` directamente: su reset viene de la debug unit
  (`o_cpu_reset`), que lo incluye. Así la debug unit puede resetear el CPU sola con
  el comando `X`.

---

## La línea RX

```
sync_2ff #(.INIT(1'b1)) u_rx_sync (.i_clk(clk), .i_async(i_rx), .o_sync(rx_sync));
```

Dos flip-flops para sincronizar la línea asíncrona de la UART con el reloj del
sistema. `INIT = 1'b1` porque en reposo la línea UART está en 1.

---

## Las conexiones

**`uart_core`** → la debug unit:

```verilog
.i_read_uart   (rx_read),   .i_write_uart  (tx_write),
.i_data_to_write(tx_data),  .o_tx_full     (tx_full),
.o_rx_empty    (rx_empty),  .o_data_to_read(rx_data),
```

**`debug_unit`** → el CPU:

```verilog
.o_cpu_enable (cpu_enable), .o_cpu_reset (cpu_reset), .i_cpu_halt (cpu_halt),
.o_imem_write_enable(imem_we), .o_imem_write_addr(imem_waddr), .o_imem_write_data(imem_wdata),
.o_dbg_addr   (dbg_addr),   .i_dbg_data (dbg_data),   .i_dbg_count(dbg_count),
```

**`riscv_pipeline`** ← el CPU:

```verilog
.i_rst (cpu_reset), .i_enable(cpu_enable), .o_halt(cpu_halt),
```

---

## Los LEDs

```verilog
assign o_led = {cpu_halt, cpu_reset, cpu_enable};
```

| LED | Significado |
|---|---|
| `[0]` | el CPU está habilitado (corriendo o en pause) |
| `[1]` | el CPU está en reset (cargando o reseteado) |
| `[2]` | el CPU llegó a un halt |
