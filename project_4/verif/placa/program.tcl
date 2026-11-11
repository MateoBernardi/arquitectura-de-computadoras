# Programa la FPGA por JTAG con un bitstream ya generado (capa bitstream). Es lo mismo que
# "Program Device" en la GUI de Vivado; cualquiera de las dos sirve antes de la capa placa.
#   TP4_BIT=build/bitstream/top_riscv.bit vivado -mode batch -source verif/placa/program.tcl
# Sin TP4_BIT usa build/bitstream/top_riscv.bit.
set root [file normalize [file join [file dirname [info script]] .. ..]]
set bit [expr {[info exists ::env(TP4_BIT)] ? $::env(TP4_BIT) : "$root/build/bitstream/top_riscv.bit"}]
if {![file exists $bit]} { puts "TP4_ERROR: no existe $bit: correr antes la capa bitstream"; exit 1 }

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} { puts "TP4_ERROR: no se encontró la FPGA (xc7a100t) por JTAG"; exit 1 }
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
# DONE: la FPGA terminó de configurarse (registro de estado leído por JTAG)
if {[catch {refresh_hw_device $dev; get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $dev} done]} {
    puts "TP4_DONE: no se pudo leer ($done)"
} else {
    puts "TP4_DONE: $done"
    if {$done ne "1"} { puts "TP4_ERROR: la FPGA no terminó de configurarse (DONE = $done)"; exit 1 }
}
puts "TP4_PROGRAMADA: $dev"
close_hw_manager
