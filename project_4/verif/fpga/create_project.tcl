# Crea el proyecto de Vivado desde cero, a partir de los fuentes del repo.
# Uso (desde cualquier carpeta):
#   vivado -mode batch -source verif/fpga/create_project.tcl
# El proyecto queda en build/vivado/tp4.xpr (generado, no se versiona): se puede
# borrar y volver a crear en cualquier momento.
# Variables de entorno opcionales (las usan los mutantes de síntesis):
#   TP4_RTL_DIR       el RTL a usar (por defecto rtl/)
#   TP4_PROJECT_DIR   dónde crear el proyecto (por defecto build/vivado/)

set root  [file normalize [file join [file dirname [info script]] .. ..]]
set part  xc7a100tcsg324-1          ;# Nexys4 DDR (Artix-7 100T)
set rtl   [expr {[info exists ::env(TP4_RTL_DIR)] ? $::env(TP4_RTL_DIR) : "$root/rtl"}]
set dir   [expr {[info exists ::env(TP4_PROJECT_DIR)] ? $::env(TP4_PROJECT_DIR) : "$root/build/vivado"}]

create_project tp4 $dir -part $part -force
set_property target_language Verilog [current_project]

# RTL: todos los .v/.vh de rtl/, en cualquier nivel de subcarpeta
proc rglob {d pat} {
    set out [glob -nocomplain -directory $d -types f $pat]
    foreach sub [glob -nocomplain -directory $d -types d *] { lappend out {*}[rglob $sub $pat] }
    return $out
}
add_files -fileset sources_1 [rglob $rtl *.v]
add_files -fileset sources_1 [rglob $rtl *.vh]
set_property file_type {Verilog Header} [get_files *.vh]
# alu_ops.vh lo incluyen alu.v (3_execute) y control.v (2_decode)
set_property include_dirs [list $rtl/pipeline/3_execute] [get_filesets sources_1]
set_property top top_riscv [get_filesets sources_1]

# Restricciones de la placa (pines y reloj de 100 MHz)
add_files -fileset constrs_1 $root/constraints/nexys4ddr_top.xdc

# Simulación: el testbench del sistema completo y sus vectores
add_files -fileset sim_1 [list $root/verif/system/tb_top_riscv.v \
                              $root/verif/system/pipeline_prog.hex \
                              $root/verif/system/pipeline_exp.hex]
set_property include_dirs [list $rtl/pipeline/3_execute] [get_filesets sim_1]
set_property top tb_top_riscv [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Proyecto creado: $dir/tp4.xpr"
close_project
