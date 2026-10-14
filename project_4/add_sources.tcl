# Uso (desde project_4/):  vivado -mode batch -source add_sources.tcl
# Agrega los fuentes nuevos al proyecto, pone top_riscv como top y saca csr.v (eliminado).
open_project project_4.xpr
remove_files -quiet [get_files -quiet csr.v]
add_files -fileset sources_1 [glob project_4.srcs/sources_1/new/*.v]
add_files -fileset sources_1 project_4.srcs/sources_1/new/alu_ops.vh
set_property file_type {Verilog Header} [get_files alu_ops.vh]
add_files -fileset sim_1 [glob project_4.srcs/sim_1/new/*.v]
add_files -fileset sim_1 [glob project_4.srcs/sim_1/new/*.hex]
set_property top top_riscv [get_filesets sources_1]
set_property top tb_top_riscv [get_filesets sim_1]
update_compile_order -fileset sources_1
close_project
