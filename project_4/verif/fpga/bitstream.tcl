# Genera el bitstream a partir de la implementación ya verificada (capa implementacion).
# Es lo mismo que "Generate Bitstream" en la GUI de Vivado.
#   vivado -mode batch -source verif/fpga/bitstream.tcl
# Si impl_1 no está completa o quedó desactualizada, falla: no implementa de nuevo.
# Variables de entorno: TP4_PROJECT_DIR (carpeta del proyecto, por defecto build/vivado/).
# Escribe TP4_OK / TP4_ERROR / TP4_BIT en el log para que run.sh arme los chequeos.
set root [file normalize [file join [file dirname [info script]] .. ..]]
proc env_or {name default} { expr {[info exists ::env($name)] ? $::env($name) : $default} }

open_project [env_or TP4_PROJECT_DIR $root/build/vivado]/tp4.xpr
set impl [get_runs impl_1]
if {[get_property PROGRESS $impl] ne "100%" || [get_property NEEDS_REFRESH $impl]} {
    puts "TP4_ERROR: impl_1 no está completa o está desactualizada: correr antes las capas sintesis e implementacion"
    exit 1
}
puts "TP4_OK: impl_1 completa y al día con los fuentes"
if {![string match "write_bitstream Complete*" [get_property STATUS $impl]]} {
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1
}
if {![string match "write_bitstream Complete*" [get_property STATUS $impl]]} {
    puts "TP4_ERROR: write_bitstream no terminó: [get_property STATUS $impl]"
    exit 1
}
puts "TP4_OK: write_bitstream terminó (incluye el DRC del bitstream)"
set bit [lindex [glob -nocomplain [get_property DIRECTORY $impl]/*.bit] 0]
if {$bit eq ""} { puts "TP4_ERROR: write_bitstream terminó pero no hay .bit"; exit 1 }
puts "TP4_BIT: $bit"
close_project
