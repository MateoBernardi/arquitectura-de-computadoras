# Implementación (Vivado en modo batch): place & route y los reportes que revisa
# check_impl.py. Usa la síntesis del proyecto (si está desactualizada, Vivado la repite).
#   vivado -mode batch -source verif/fpga/impl.tcl
# Variables de entorno: TP4_PROJECT_DIR (carpeta del proyecto, por defecto build/vivado/),
# TP4_REPORT_DIR (dónde escribir los reportes, por defecto build/reports/implementacion/).
set root [file normalize [file join [file dirname [info script]] .. ..]]
proc env_or {name default} { expr {[info exists ::env($name)] ? $::env($name) : $default} }
set rep [env_or TP4_REPORT_DIR $root/build/reports/implementacion]
file mkdir $rep

open_project [env_or TP4_PROJECT_DIR $root/build/vivado]/tp4.xpr
reset_run impl_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1
puts "impl_1: [get_property STATUS [get_runs impl_1]]"
open_run impl_1

# STA: que no quede nada sin restringir, y los márgenes de setup, hold y ancho de pulso
check_timing -verbose -file $rep/check_timing.rpt
report_timing_summary -max_paths 10 -report_unconstrained -file $rep/timing_summary.rpt
report_clocks -file $rep/clocks.rpt
report_cdc -details -file $rep/cdc.rpt
# físico
report_route_status -file $rep/route_status.rpt
report_drc -file $rep/drc.rpt
report_methodology -file $rep/methodology.rpt
close_project
