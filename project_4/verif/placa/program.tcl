# Genera el bitstream a partir de la implementación ya verificada (capa implementacion)
# y programa la FPGA por JTAG. Es lo mismo que hacer "Generate Bitstream" y "Program
# Device" en la GUI de Vivado; cualquiera de las dos sirve antes de la capa placa.
#   vivado -mode batch -source verif/placa/program.tcl
# Si impl_1 no está completa o quedó desactualizada, falla: no implementa de nuevo.
set root [file normalize [file join [file dirname [info script]] .. ..]]
open_project $root/build/vivado/tp4.xpr
set impl [get_runs impl_1]
if {[get_property PROGRESS $impl] ne "100%" || [get_property NEEDS_REFRESH $impl]} {
    puts "TP4_ERROR: impl_1 no está completa o está desactualizada: correr antes verif/run.sh fpga"
    exit 1
}
if {![string match "write_bitstream Complete*" [get_property STATUS $impl]]} {
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1
}
set bit [lindex [glob -nocomplain [get_property DIRECTORY $impl]/*.bit] 0]
if {$bit eq ""} { puts "TP4_ERROR: no se generó el bitstream"; exit 1 }
puts "TP4_BIT: $bit"
close_project

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} { puts "TP4_ERROR: no se encontró la FPGA (xc7a100t) por JTAG"; exit 1 }
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "TP4_PROGRAMADA: $dev"
close_hw_manager
