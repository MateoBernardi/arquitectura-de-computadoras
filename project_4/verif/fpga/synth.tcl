# Síntesis del proyecto (Vivado en modo batch). Los chequeos los hace check_synth.py
# sobre el log; este script solo sintetiza.
#   vivado -mode batch -source verif/fpga/synth.tcl
# Parámetros, por variables de entorno (los pone verif/run.sh):
#   TP4_BUILD_ID     versión del RTL que queda en el dump (8 dígitos hex; 0 = sin versión)
#   TP4_MMCM_MULT    multiplicador del MMCM (por defecto 10)
#   TP4_MMCM_DIV_X8  divisor de salida del MMCM × 8 (por defecto 160 → 50 MHz)
#   TP4_PROJECT_DIR  carpeta del proyecto (por defecto build/vivado/)
set root [file normalize [file join [file dirname [info script]] .. ..]]
proc env_or {name default} { expr {[info exists ::env($name)] ? $::env($name) : $default} }

open_project [env_or TP4_PROJECT_DIR $root/build/vivado]/tp4.xpr
set generics [list "BUILD_ID=32'h[env_or TP4_BUILD_ID 0]" \
                   "MMCM_MULT=[env_or TP4_MMCM_MULT 10]" \
                   "MMCM_DIV_X8=[env_or TP4_MMCM_DIV_X8 160]"]
set_property generic $generics [get_filesets sources_1]
puts "generics: $generics"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "synth_1: [get_property STATUS [get_runs synth_1]] ([get_property PROGRESS [get_runs synth_1]])"
close_project
