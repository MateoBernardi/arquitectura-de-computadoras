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

## LEDs (ver rtl/top/README.md): LD0 = CPU habilitado, LD1 = CPU en reset (carga),
## LD2 = halt, LD3..LD7 = registro de la última escritura, LD10 = forwarding A,
## LD11 = forwarding B, LD12 = stall, LD13 = flush, LD14 = excepción, LD15 = halt
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { o_led[0] }];
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { o_led[1] }];
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { o_led[2] }];
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports { o_led[3] }];
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { o_led[4] }];
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { o_led[5] }];
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { o_led[6] }];
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports { o_led[7] }];
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { o_led[8] }];
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports { o_led[9] }];
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { o_led[10] }];
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { o_led[11] }];
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { o_led[12] }];
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports { o_led[13] }];
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { o_led[14] }];
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports { o_led[15] }];

## SW0: prende el display de 7 segmentos
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { i_sw[0] }];

## Display de 7 segmentos (activos en bajo): segmentos {g,f,e,d,c,b,a} y ánodos AN0..AN7
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { o_seg[0] }];
set_property -dict { PACKAGE_PIN R10 IOSTANDARD LVCMOS33 } [get_ports { o_seg[1] }];
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { o_seg[2] }];
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports { o_seg[3] }];
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { o_seg[4] }];
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports { o_seg[5] }];
set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports { o_seg[6] }];
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports { o_an[0] }];
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { o_an[1] }];
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { o_an[2] }];
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 } [get_ports { o_an[3] }];
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports { o_an[4] }];
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports { o_an[5] }];
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports { o_an[6] }];
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports { o_an[7] }];

## Configuración del banco 0 (la del XDC maestro de Digilent para la Nexys4 DDR)
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Puertos asíncronos: no tienen relación de fase con el reloj, así que no se les da un
## retardo de entrada/salida sino que se excluyen del análisis de timing. El RTL los trata así:
## - i_rx, i_reset e i_sw entran por un sincronizador sync_2ff (flip-flops con ASYNC_REG);
## - o_tx sale de un registro (uart_tx_regs) y la UART es asíncrona: un bit dura ~52 us;
## - los LED y el display los mira una persona.
set_false_path -from [get_ports { i_rx i_reset i_sw[*] }]
set_false_path -to   [get_ports { o_tx o_led[*] o_an[*] o_seg[*] }]
