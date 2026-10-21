# Uso (desde project_4/):  vivado -mode batch -source add_sources.tcl
# Agrega los fuentes al proyecto, pone top_riscv como top y saca csr.v (eliminado).
#
# El RTL esta ordenado en carpetas (pipeline/1_fetch, pipeline/2_decode, ...,
# uart, debug, top, common), asi que hay que agregar los .v/.vh que estan
# en distintos niveles de subcarpeta.

open_project project_4.xpr

# --- 1. limpiar ---
# csr.v se elimino del proyecto.
set old [get_files -quiet csr.v]
if {[llength $old]} { remove_files -quiet $old }

# La version anterior del proyecto tenia todos los fuentes planos en new/.
# Hay que sacar esas referencias: los archivos ya no estan en disco y dejarlas
# daria el mismo modulo dos veces (ruta vieja + ruta nueva).
#
# En Vivado el NAME de un archivo es la ruta absoluta, asi que se compara
# contra la ruta normalizada de new/. El * de string match de Tcl si cruza
# el separador de directorios, a diferencia del de glob.
set norm [file normalize project_4.srcs/sources_1/new]
set old {}
foreach f [get_files -quiet] {
    if {[string match "$norm/*" [get_property NAME $f]]} {
        lappend old $f
    }
}
if {[llength $old]} { remove_files -quiet $old }

# --- 2. agregar los .v/.vh ---
# El RTL llega hasta dos niveles de subcarpeta (pipeline/3_execute/alu.v), asi
# que se agregan tres niveles: la raiz de new/, las subcarpetas y las
# sub-subcarpetas.
#
# En Vivado el * de glob no cruza el separador de directorios, asi que cada
# patron cubre un nivel distinto y ningun archivo entra dos veces.
set src_root project_4.srcs/sources_1/new
set all {}
foreach ext {.v .vh} {
    foreach depth {"" "/*" "/*/*"} {
        foreach f [glob -nocomplain "$src_root$depth/*$ext"] {
            lappend all $f
        }
    }
}
set all [lsort -unique $all]

set n_v 0
set n_vh 0
foreach f $all {
    # Si ya estaba en el proyecto (el script se puede correr mas de una vez)
    # se saca primero, para no duplicarlo.
    set fl [get_files -quiet $f]
    if {[llength $fl]} { remove_files -quiet $fl }

    add_files -fileset sources_1 $f
    if {[file extension $f] eq ".vh"} {
        set_property file_type {Verilog Header} [get_files -quiet $f]
        incr n_vh
    } else {
        incr n_v
    }
}
puts "  fuentes agregadas: $n_v .v + $n_vh .vh"

# --- 3. include path ---
# alu_ops.vh lo usan dos etapas distintas: alu.v (3_execute) y control.v
# (2_decode). El header esta en una sola carpeta, asi que su directorio
# tiene que estar en el include path para que los dos lo encuentren.
set hdir project_4.srcs/sources_1/new/pipeline/3_execute
set hnorm [file normalize $hdir]
set inc [get_property include_dirs [get_filesets sources_1]]
set new {}
set found 0
foreach d $inc {
    if {[file normalize $d] eq $hnorm} {
        if {!$found} { lappend new $hdir ; set found 1 }
    } else {
        lappend new $d
    }
}
if {!$found} { lappend new $hdir }
set_property include_dirs $new [get_filesets sources_1]
# Tambien el fileset de simulacion, que compila el RTL aparte.
set_property include_dirs $new [get_filesets sim_1]

# --- 4. simulacion y top ---
foreach pat {*.v *.hex} {
    foreach f [glob -nocomplain project_4.srcs/sim_1/new/$pat] {
        set fl [get_files -quiet $f]
        if {[llength $fl]} { remove_files -quiet $fl }
        add_files -fileset sim_1 $f
    }
}
set_property top top_riscv [get_filesets sources_1]
set_property top tb_top_riscv [get_filesets sim_1]
update_compile_order -fileset sources_1
close_project
