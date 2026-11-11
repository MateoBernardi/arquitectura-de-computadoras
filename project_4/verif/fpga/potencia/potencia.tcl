# potencia.tcl — potencia estimada con la actividad simulada (la llama potencia.sh).
#   TP4_SAIF        el archivo de actividad de tb_potencia
#   TP4_REPORT_DIR  dónde escribir potencia_saif.rpt
#   TP4_PROJECT_DIR el proyecto con la implementación (por defecto build/vivado/)
set root [file normalize [file join [file dirname [info script]] .. .. ..]]
proc env_or {name default} { expr {[info exists ::env($name)] ? $::env($name) : $default} }
open_project [env_or TP4_PROJECT_DIR $root/build/vivado]/tp4.xpr
open_run impl_1
read_saif -strip_path tb_potencia/dut $::env(TP4_SAIF)
report_power -file $::env(TP4_REPORT_DIR)/potencia_saif.rpt
close_project
