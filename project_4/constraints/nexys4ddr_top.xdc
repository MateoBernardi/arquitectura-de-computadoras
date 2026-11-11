## TP2 - Nexys4 DDR constraints for `top` (i_clk, i_reset, i_rx, o_tx)
## Pins verified against the Digilent Nexys4-DDR-Master.xdc.

## Clock: on-board 100MHz oscillator. Matches top's default CLK_FREQ=100_000_000 --
## if you ever instantiate top with a different CLK_FREQ, update the period below too.
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { i_clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { i_clk }];

## Reset: BTNC (center pushbutton), NOT CPU_RESETN.
## BTNC is active-high (pressed = 1), matching i_reset directly -- CPU_RESETN
## is active-low (the "N" suffix) and would need an inverter to use safely.
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { i_reset }];

## USB-UART bridge (FTDI, connector J6) -- talks to the PC as a virtual COM port,
## no external hardware or cables needed.
## Signal names are from the PC's point of view: UART_TXD_IN is the PC's TX
## arriving at the FPGA (so it's our i_rx); UART_RXD_OUT is what the FPGA
## drives for the PC to receive (so it's our o_tx).
set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports { i_rx }];
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports { o_tx }];

## LEDs: LD0 = CPU enabled, LD1 = CPU in reset (loading), LD2 = halt
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { o_led[0] }];
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { o_led[1] }];
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { o_led[2] }];
