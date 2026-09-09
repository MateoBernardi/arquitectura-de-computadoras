## Clock signal (100 MHz oscillator)
set_property PACKAGE_PIN W5 [get_ports i_clk]							
	set_property IOSTANDARD LVCMOS33 [get_ports i_clk]
	create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports i_clk]

## Switches (SW0 - SW7)
set_property PACKAGE_PIN V17 [get_ports {switch[0]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {switch[0]}]
set_property PACKAGE_PIN V16 [get_ports {switch[1]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {switch[1]}]
set_property PACKAGE_PIN W16 [get_ports {switch[2]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {switch[2]}]
set_property PACKAGE_PIN W17 [get_ports {switch[3]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {switch[3]}]
set_property PACKAGE_PIN W15 [get_ports {switch[4]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {switch[4]}]
set_property PACKAGE_PIN V15 [get_ports {switch[5]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {switch[5]}]
set_property PACKAGE_PIN W14 [get_ports {switch[6]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {switch[6]}]
set_property PACKAGE_PIN W13 [get_ports {switch[7]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {switch[7]}]

## Buttons
# button[0] -> btnU (Cargar Dato A)
set_property PACKAGE_PIN T18 [get_ports {button[0]}]						
	set_property IOSTANDARD LVCMOS33 [get_ports {button[0]}]
# button[1] -> btnC (Cargar Dato B)
set_property PACKAGE_PIN U18 [get_ports {button[1]}]						
	set_property IOSTANDARD LVCMOS33 [get_ports {button[1]}]
# button[2] -> btnD (Cargar Operacion)
set_property PACKAGE_PIN U17 [get_ports {button[2]}]						
	set_property IOSTANDARD LVCMOS33 [get_ports {button[2]}]
## Reset (btnR - Boton Derecho)
set_property PACKAGE_PIN T17 [get_ports i_reset]						
    set_property IOSTANDARD LVCMOS33 [get_ports i_reset]

## LEDs (LD0 - LD7 para resultado)
set_property PACKAGE_PIN U16 [get_ports {led[0]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property PACKAGE_PIN E19 [get_ports {led[1]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property PACKAGE_PIN U19 [get_ports {led[2]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property PACKAGE_PIN V19 [get_ports {led[3]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]
set_property PACKAGE_PIN W18 [get_ports {led[4]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]
set_property PACKAGE_PIN U15 [get_ports {led[5]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]
set_property PACKAGE_PIN U14 [get_ports {led[6]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]
set_property PACKAGE_PIN V14 [get_ports {led[7]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]

## Flags (LD14 y LD15)
# f_o -> LD14 (Overflow flag)
set_property PACKAGE_PIN P1 [get_ports {f_o}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {f_o}]
# f_z -> LD15 (Zero flag)
set_property PACKAGE_PIN L1 [get_ports {f_z}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {f_z}]
	
## Configuration Voltage & Bank settings for Basys 3
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]