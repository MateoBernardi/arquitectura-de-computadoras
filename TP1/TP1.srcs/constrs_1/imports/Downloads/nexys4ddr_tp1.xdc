## Constraints para Nexys4 DDR (XC7A100T-1CSG324C)
## Adaptado de: https://github.com/Digilent/digilent-xdc/blob/master/Nexys-4-DDR-Master.xdc
## Pines verificados contra el master XDC oficial de Digilent (Rev. C).
##
## Mapeo de botones asumido (uno de los 5 pushbuttons por bit del vector "button"):
##   button[0] = BTN_DATA_A  -> BTNL
##   button[1] = BTN_DATA_B  -> BTNR
##   button[2] = BTN_DATA_OP -> BTNU
##   i_reset                 -> BTNC   (activo en alto, igual que en el RTL)
## BTND queda libre. Si tu mapeo de botones en el Basys3 era otro, solo hace
## falta reordenar estas lineas: no afecta al Verilog, es puramente fisico.

## Clock signal (100 MHz)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { i_clk }]; #Sch=clk100mhz
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { i_clk }];

## Switches -> switch[7:0]
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { switch[0] }]; #Sch=sw[0]
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { switch[1] }]; #Sch=sw[1]
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { switch[2] }]; #Sch=sw[2]
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { switch[3] }]; #Sch=sw[3]
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { switch[4] }]; #Sch=sw[4]
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { switch[5] }]; #Sch=sw[5]
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { switch[6] }]; #Sch=sw[6]
set_property -dict { PACKAGE_PIN R13   IOSTANDARD LVCMOS33 } [get_ports { switch[7] }]; #Sch=sw[7]

## Buttons -> button[2:0] (one-hot) y reset
set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { button[0] }]; #Sch=btnl (BTN_DATA_A)
set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports { button[1] }]; #Sch=btnr (BTN_DATA_B)
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { button[2] }]; #Sch=btnu (BTN_DATA_OP)
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { i_reset }];   #Sch=btnc (reset, activo alto)
# BTND (P18) libre para uso futuro.

## LEDs -> led[7:0], f_z, f_o
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { led[0] }]; #Sch=led[0]
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { led[1] }]; #Sch=led[1]
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { led[2] }]; #Sch=led[2]
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }]; #Sch=led[3]
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { led[4] }]; #Sch=led[4]
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { led[5] }]; #Sch=led[5]
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { led[6] }]; #Sch=led[6]
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { led[7] }]; #Sch=led[7]
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { f_z }];    #Sch=led[8]
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { f_o }];    #Sch=led[9]
