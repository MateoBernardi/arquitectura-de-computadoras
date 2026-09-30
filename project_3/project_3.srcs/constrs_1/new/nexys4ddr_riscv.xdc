## Nexys4 DDR (XC7A100T-1CSG324C) - top_riscv

## Reloj 100 MHz
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { i_clk }]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports { i_clk }]

## Reset: BTNC (activo en alto)
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { i_reset }]

## USB-UART (i_rx = UART_TXD_IN, o_tx = UART_RXD_OUT)
set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports { i_rx }]
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports { o_tx }]

## LEDs: LD0 CPU habilitado, LD1 CPU en reset (carga), LD2 halt
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { o_led[0] }]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { o_led[1] }]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { o_led[2] }]

## Entradas asincronicas (pasan por sincronizadores) y salidas lentas
set_false_path -from [get_ports { i_reset i_rx }]
set_false_path -to   [get_ports { o_tx o_led[*] }]

## Configuracion
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
