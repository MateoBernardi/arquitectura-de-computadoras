#!/usr/bin/env bash
# Potencia estimada con actividad real: simula el sistema (RTL, xsim) corriendo una carga
# en bucle, registra la conmutación de cada señal (SAIF) y se la da a report_power sobre
# la implementación de build/vivado/ (correr antes la capa implementacion).
#
#   verif/fpga/potencia/potencia.sh
#
# La carga es criba.s con el ebreak final cambiado por un salto al principio: ALU,
# loads, stores y branches, sin detenerse. La ventana es de 2 ms de CPU corriendo
# (140 000 ciclos a 70 MHz). La simulación es del RTL, no del netlist: Vivado aparea las
# señales del SAIF con las del netlist por nombre (registros, puertos) y propaga el
# resto; report_power dice qué parte de las redes quedó apareada.
# Tarda unos minutos. Deja potencia_saif.rpt en build/reports/implementacion/.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../env.sh"
WORK="$PROJ/build/potencia"; REP="${TP4_REPORT_DIR:-$PROJ/build/reports/implementacion}"
rm -rf "$WORK"; mkdir -p "$WORK" "$REP"
cd "$WORK"

# carga: criba en bucle
{ echo ".globl _start"; echo "_start:"; sed 's/^\(\s*\)ebreak\b.*/\1j _start/' "$PROJ/programs/criba.s"; echo; } > carga.s
grep -q "j _start" carga.s || { echo "no encontré el ebreak de criba.s"; exit 1; }
riscv-none-elf-as -march=rv32i -mabi=ilp32 -o carga.o carga.s
riscv-none-elf-ld -m elf32lriscv -Ttext=0 -o carga.elf carga.o
riscv-none-elf-objcopy -O binary carga.elf carga.bin
python3 -c "
import struct,sys; d=open('carga.bin','rb').read(); d+=b'\0'*(-len(d)%4)
open('carga.hex','w').write(''.join('%08x\n'%w for w in struct.unpack('<%dI'%(len(d)//4),d)))"

# simulación del RTL con xsim
# xvlog / xelab / xsim vienen con Vivado; si no están en el PATH, se buscan en la
# instalación (vivado puede ser un script que la llama, VIVADO_DIR la fija a mano)
if [ -z "${VIVADO_DIR:-}" ]; then
    echo 'puts "DIR=$::env(XILINX_VIVADO)"' > vivado_dir.tcl
    VIVADO_DIR=$(vivado -mode batch -nojournal -nolog -source vivado_dir.tcl | sed -n 's/^DIR=//p')
fi
[ -d "$VIVADO_DIR/bin" ] || { echo "no encuentro la instalación de Vivado (VIVADO_DIR=...)"; exit 1; }
PATH="$VIVADO_DIR/bin:$PATH"
mapfile -t SRC < <(find "$RTL_DIR" -name '*.v' | sort)
xvlog -i "$RTL_DIR/pipeline/3_execute" "${SRC[@]}" "$HERE/tb_potencia.v" \
      "$VIVADO_DIR/data/verilog/src/glbl.v" > xvlog.log
xelab -L unisims_ver -debug typical -timescale 1ns/1ps tb_potencia glbl -s tbp > xelab.log
cat > saif.tcl <<'TCL'
run -all
open_saif actividad.saif
log_saif [get_objects -r /tb_potencia/dut/*]
run -all
close_saif
quit
TCL
xsim tbp -tclbatch saif.tcl > xsim.log
grep "tb_potencia" xsim.log
[ -s actividad.saif ] || { echo "no se generó el SAIF"; tail -20 xsim.log; exit 1; }

TP4_SAIF="$WORK/actividad.saif" TP4_REPORT_DIR="$REP" \
    vivado -mode batch -nojournal -log "$WORK/vivado_potencia.log" -source "$HERE/potencia.tcl" > /dev/null
echo "informe: $REP/potencia_saif.rpt"
