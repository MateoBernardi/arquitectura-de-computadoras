open_project project_3.xpr
add_files -fileset sources_1 [glob project_3.srcs/sources_1/new/*.v]
add_files -fileset sources_1 project_3.srcs/sources_1/new/riscv_defs.vh
set_property file_type {Verilog Header} [get_files riscv_defs.vh]
add_files -fileset sim_1 [glob project_3.srcs/sim_1/new/*.v]
add_files -fileset constrs_1 [glob project_3.srcs/constrs_1/new/*.xdc]
add_files -fileset sim_1 [glob host/*.hex]
set_property top top_riscv [get_filesets sources_1]
update_compile_order -fileset sources_1
close_project
