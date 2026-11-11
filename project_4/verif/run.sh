#!/usr/bin/env bash
# Verificación del proyecto por capas, en el orden de las etapas del flujo:
#   RTL (formal, rvfi, act, traps, rendimiento, sistema) → síntesis (sintesis)
#   → implementación (implementacion) → bitstream (bitstream) → placa (programar, placa).
#   host prueba el software de la PC, fuera del flujo.
#
#   ./run.sh                     todas las capas
#   ./run.sh act traps           solo esas capas
#   ./run.sh rapido              grupo: todo menos riscv-formal (la capa más larga)
#   ./run.sh programar placa     programar la FPGA con el último bitstream y probarla
#   ./run.sh --variante <nombre> rvfi, act y traps con una variante de variants/
#   ./run.sh --lista             las capas, qué prueba cada una y si están sus herramientas
#
# Cada prueba escribe un renglón "[ok ] ..." o "[MAL] ...". Resultado de una capa:
#   PASS  corrió al menos una prueba y todas dieron bien
#   FAIL  alguna falló, el script terminó con error o no corrió ninguna prueba
#   SKIP  falta una herramienta: la capa no se probó (un SKIP nunca es un PASS)
# Código de salida: 0 todo PASS, 1 algún FAIL, 2 sin FAIL pero con algún SKIP.
#
# Reportes (se reescriben en cada corrida): build/reports/<capa>.log y build/reports/resumen.md
#
# sintesis e implementacion reutilizan su última corrida verificada si rtl/, constraints/ y
# verif/fpga/ no cambiaron desde entonces (TP4_REHACER=1 las rehace igual).
#
# Todo el script va entre llaves: bash lo lee completo antes de empezar, así que editarlo
# (o hacer checkout) mientras corre no rompe la corrida en curso.
{
set -u
cd "$(dirname "$0")" || exit 1
source env.sh
REPORTS="$PROJ/build/reports"

# --- capas -------------------------------------------------------------------------
# capa | qué prueba | herramientas (cmd:<programa> o dir:<carpeta de TOOLS_DIR>)
LAYERS=(
"formal|propiedades formales por módulo: forward_unit, hazard_unit, pipeline_control, datapath (con mutantes)|cmd:yosys cmd:sby cmd:bitwuzla"
"rvfi|el CPU completo contra la ISA RV32I con riscv-formal, incluidas las excepciones (con mutantes)|cmd:yosys cmd:sby cmd:boolector cmd:bitwuzla dir:riscv-formal"
"act|suite oficial riscv-arch-test (ACT4), autoverificada contra Sail: las instrucciones RV32I|cmd:verilator cmd:riscv-none-elf-gcc cmd:sail_riscv_sim cmd:mise dir:riscv-arch-test dir:riscv-formal"
"traps|tests propios: causa y PC que reporta cada trap (ACT, sin CSRs, no prueba excepciones)|cmd:verilator cmd:riscv-none-elf-gcc dir:riscv-formal"
"rendimiento|ciclos y CPI del diseño base y cada variante; cada variante debe dar el mismo resultado|cmd:verilator cmd:riscv-none-elf-gcc dir:riscv-formal"
"sistema|el sistema completo (UART + debug unit + CPU) manejado por la línea serie|cmd:iverilog cmd:vvp"
"host|el software de la PC: protocolo UART, desensamblador y GUI|cmd:python3 py:tkinter"
"sintesis|Vivado: el netlist es lo que pide el RTL (avisos justificados, sin latches, memorias), con mutantes|cmd:vivado"
"implementacion|Vivado: STA completo (nada sin restringir; setup, hold, pulso), cruces de reloj, ruteo, DRC|cmd:vivado"
"bitstream|Vivado: el bitstream sale de la implementación verificada del hardware actual (con su DRC)|cmd:vivado"
"programar|programa la FPGA por JTAG con ese bitstream y verifica que terminó de configurarse|cmd:vivado dev:placa"
"placa|la FPGA real por la UART: versión, programas y traps comparados contra la simulación, comandos|cmd:verilator cmd:riscv-none-elf-gcc dir:riscv-formal py:serial dev:placa"
)
declare -A LAYER_GROUPS=(
    [todo]="formal rvfi act traps rendimiento sistema host sintesis implementacion bitstream programar placa"
    [rtl]="formal rvfi act traps rendimiento"
    [rapido]="formal act traps rendimiento sistema host"
    [fpga]="sintesis implementacion bitstream programar placa"
)

layer_field() {   # layer_field <capa> <n>
    local l; for l in "${LAYERS[@]}"; do
        [ "${l%%|*}" = "$1" ] && { echo "$l" | cut -d'|' -f"$2"; return 0; }
    done; return 1
}

missing_tools() {   # imprime lo que falta para la capa
    local need miss=()
    for need in $(layer_field "$1" 3); do
        case $need in
            cmd:*) command -v "${need#cmd:}" > /dev/null || miss+=("${need#cmd:}") ;;
            dir:*) [ -d "$TOOLS_DIR/${need#dir:}" ] || miss+=("$TOOLS_DIR/${need#dir:}") ;;
            py:*)  python3 -c "import ${need#py:}" 2> /dev/null || miss+=("python3-${need#py:}") ;;
            dev:placa) [ -e "$PLACA_PUERTO" ] || miss+=("placa conectada en $PLACA_PUERTO (PLACA_PUERTO=...)") ;;
        esac
    done
    echo "${miss[*]}"
}

# Puerto serie de la placa: el segundo canal del FTDI de la Nexys4 DDR (el primero es JTAG)
PLACA_PUERTO=${PLACA_PUERTO:-/dev/ttyUSB1}

# --- comandos de cada capa ------------------------------------------------------------
VARIANT=""
run_formal() {
    local s rc=0
    for s in forward_unit hazard_unit pipeline_control datapath; do
        echo "== $s"; formal/$s/run.sh || rc=1
    done
    return $rc
}
run_rvfi() {
    if [ -n "$VARIANT" ]; then formal/rvfi/run.sh "$VARIANT"; return; fi
    local rc=0
    echo "== chequeos"; formal/rvfi/run.sh || rc=1
    echo "== mutantes (cada uno tiene que hacer fallar su chequeo)"; formal/rvfi/mutants.sh || rc=1
    return $rc
}
run_act()         { VARIANT="$VARIANT" sim/run_act.sh; }
run_traps()       { VARIANT="$VARIANT" sim/run_traps.sh; }
run_rendimiento() {
    sim/bench.py || return 1
    # información, no es un chequeo: el desglose del CPI de cada programa
    python3 sim/perfil.py > /dev/null && echo "      desglose del CPI: $REPORTS/perfil.md"
}
run_sistema()     { system/run.sh; }
run_host()        { python3 tools/pyunit.py "$PROJ/host/tests"; }

# version_of <rutas...>: el último commit que cambió esas rutas (8 dígitos hex), o 0 si
# tienen cambios sin commitear (no hay un commit al que atribuírselos).
version_of() {
    if [ -z "$(git -C "$PROJ" status --porcelain -- "$@" 2>/dev/null)" ]; then
        git -C "$PROJ" log -1 --format=%H -- "$@" | cut -c1-8
    else echo 0; fi
}
# Versión del hardware que va al dump (BUILD_ID): el último commit que cambió algo de lo que
# entra al bitstream. Un commit que solo toca documentación, tests o el host no la cambia.
HW_FILES=(':(glob)rtl/**/*.v' ':(glob)rtl/**/*.vh' ':(glob)constraints/*.xdc'
          verif/fpga/create_project.tcl verif/fpga/synth.tcl verif/fpga/impl.tcl)
build_id() { version_of "${HW_FILES[@]}"; }

# Reutilización de sintesis e implementacion: la huella es el último commit que cambió el
# hardware o los chequeos de FPGA (verif/fpga/, sin contar los .md). Si la última corrida
# verificada (PASS) de la capa tiene la misma huella, se muestra su resultado en lugar de
# volver a correr Vivado. FPGA_KEY se toma al empezar cada capa (ver la corrida).
FPGA_FILES=("${HW_FILES[@]}" verif/fpga ':(exclude,glob)verif/fpga/**/*.md')
VERIFICADO="$PROJ/build/verificado"
FPGA_KEY=0
reused() {   # reused <capa>: 0 (y muestra el resultado anterior) si se puede reutilizar
    [ "${TP4_REHACER:-0}" = 1 ] && return 1
    [ "$FPGA_KEY" != 0 ] && [ -f "$VERIFICADO/$1.clave" ] && [ -f "$VERIFICADO/$1.log" ] \
        && [ "$(cat "$VERIFICADO/$1.clave")" = "$FPGA_KEY" ] || return 1
    echo "== sin cambios en rtl/, constraints/ ni verif/fpga/ desde la última $1 verificada"
    echo "== ($FPGA_KEY): se muestra su resultado (TP4_REHACER=1 para rehacerla)"
    cat "$VERIFICADO/$1.log"
}
save_verified() {   # save_verified <capa> <log>: la capa dio PASS con la huella FPGA_KEY
    [ "$FPGA_KEY" = 0 ] && return
    mkdir -p "$VERIFICADO"
    grep -v '^== sin cambios en rtl/\|^== (.*): se muestra su resultado' "$2" > "$VERIFICADO/$1.log"
    echo "$FPGA_KEY" > "$VERIFICADO/$1.clave"
}
forget_verified() { local l; for l in "$@"; do rm -f "$VERIFICADO/$l".*; done; }
vivado_batch() {   # vivado_batch <script.tcl> <log>
    (cd "$PROJ/build/vivado" && vivado -mode batch -nojournal -log "$2" -source "$1" > /dev/null)
}
run_sintesis() {
    reused sintesis && return 0
    forget_verified sintesis implementacion; rm -rf "$PROJ/build/bitstream"
    export TP4_BUILD_ID; TP4_BUILD_ID=$(build_id)
    echo "BUILD_ID = $TP4_BUILD_ID"
    mkdir -p "$PROJ/build/vivado" "$VERIFICADO"
    echo "$TP4_BUILD_ID" > "$VERIFICADO/sintesis.build_id"   # el que quedó en el netlist
    vivado_batch "$PWD/fpga/create_project.tcl" "$REPORTS/vivado_proyecto.log" || return 1
    vivado_batch "$PWD/fpga/synth.tcl" "$REPORTS/vivado_sintesis.log" || return 1
    cp "$PROJ/build/vivado/tp4.runs/synth_1/runme.log" "$REPORTS/sintesis_vivado.log"
    local rc=0
    python3 fpga/check_synth.py "$REPORTS/sintesis_vivado.log" "$RTL_DIR" fpga/waivers.txt || rc=1
    echo "== mutantes (cada uno tiene que ser detectado)"
    fpga/synth_mutants.sh || rc=1
    # al final, como información (no es un chequeo): los recursos del netlist
    local inf="$REPORTS/sintesis"; rm -rf "$inf"; mkdir -p "$inf"
    cp "$PROJ/build/vivado/informes/"*.rpt "$inf/" 2> /dev/null
    echo "== utilización del netlist sintetizado (información, no es un chequeo)"
    python3 fpga/informe.py utilizacion "$inf/utilizacion_sintesis.rpt" \
        "$inf/utilizacion_sintesis_jerarquica.rpt" | tee "$inf/utilizacion.md" | sed 's/^/      /'
    return $rc
}
run_bitstream() {
    # Solo de una implementación verificada (PASS de la capa implementacion) del hardware
    # actual: así el bitstream que se programa es el que pasó el STA.
    local want have bit
    want=$(build_id); have=$(cat "$VERIFICADO/implementacion.build_id" 2>/dev/null || echo ninguna)
    if [ "$want" = 0 ]; then
        echo "[MAL] el hardware (RTL, constraints o tcl de verif/fpga/) tiene cambios sin commitear: no hay versión"
        return 1
    elif [ "$have" = "$want" ]; then
        echo "[ok ] hay una implementación verificada del hardware actual (BUILD_ID $want)"
    else
        echo "[MAL] la implementación verificada es de $have y el hardware actual es $want: correr sintesis e implementacion"
        return 1
    fi
    vivado_batch "$PWD/fpga/bitstream.tcl" "$REPORTS/vivado_bitstream.log"
    sed -n 's/^TP4_OK: /[ok ] /p; s/^TP4_ERROR: /[MAL] /p' "$REPORTS/vivado_bitstream.log"
    bit=$(sed -n 's/^TP4_BIT: //p' "$REPORTS/vivado_bitstream.log")
    [ -n "$bit" ] && [ -f "$bit" ] || return 1
    rm -rf "$PROJ/build/bitstream"; mkdir -p "$PROJ/build/bitstream"
    cp "$bit" "$PROJ/build/bitstream/top_riscv.bit"
    echo "$want" > "$PROJ/build/bitstream/build_id"
    echo "      bitstream: $PROJ/build/bitstream/top_riscv.bit (BUILD_ID $want)"
}
run_programar() {
    local want have
    want=$(build_id); have=$(cat "$PROJ/build/bitstream/build_id" 2>/dev/null || echo ninguno)
    if [ "$want" != 0 ] && [ "$have" = "$want" ]; then
        echo "[ok ] el bitstream es del hardware actual (BUILD_ID $want)"
    else
        [ "$want" = 0 ] && want="sin versión (cambios sin commitear)"
        echo "[MAL] el bitstream es de $have y el hardware actual es $want: correr la capa bitstream (o fpga)"
        return 1
    fi
    TP4_BIT="$PROJ/build/bitstream/top_riscv.bit" \
        vivado_batch "$PWD/placa/program.tcl" "$REPORTS/vivado_programa.log"
    if grep -q "^TP4_PROGRAMADA" "$REPORTS/vivado_programa.log"; then
        echo "[ok ] FPGA programada por JTAG ($(sed -n 's/^TP4_DONE: /DONE = /p' "$REPORTS/vivado_programa.log"))"
    else
        echo "[MAL] no se pudo programar la FPGA: $(grep -m1 TP4_ERROR "$REPORTS/vivado_programa.log")"
        return 1
    fi
}
run_placa() {
    # prueba lo que tenga cargado la FPGA (capa programar, o la GUI de Vivado); el chequeo
    # de versión de run.py falla si no es el hardware actual
    sim/build.sh placa > /dev/null || return 1
    echo "BUILD_ID esperado = $(build_id)   puerto = $PLACA_PUERTO"
    python3 placa/run.py --puerto "$PLACA_PUERTO" --build-id "$(build_id)" --sim "$PROJ/build/sim/placa/Vtb"
}
run_implementacion() {
    reused implementacion && return 0
    forget_verified implementacion; rm -rf "$PROJ/build/bitstream"
    [ -f "$PROJ/build/vivado/tp4.xpr" ] || { echo "no hay proyecto: correr antes la capa sintesis"; return 1; }
    local rep="$REPORTS/implementacion"; rm -rf "$rep"
    TP4_REPORT_DIR="$rep" vivado_batch "$PWD/fpga/impl.tcl" "$REPORTS/vivado_implementacion.log" || return 1
    python3 fpga/check_impl.py "$PROJ/build/vivado/tp4.runs/impl_1/runme.log" "$rep" fpga/waivers.txt
    local rc=$?
    # la versión que tiene esta implementación (la de la síntesis que usó)
    [ $rc -eq 0 ] && cp "$VERIFICADO/sintesis.build_id" "$VERIFICADO/implementacion.build_id" 2> /dev/null
    # resumen para la presentación (información, no es un chequeo): recursos, camino
    # crítico y potencia, sin actividad simulada y con la de fpga/potencia/ (si se puede
    # simular con xsim; si no, queda solo la primera)
    TP4_REPORT_DIR="$rep" fpga/potencia/potencia.sh > "$REPORTS/potencia.log" 2>&1 \
        || echo "      (sin potencia con actividad simulada: ver $REPORTS/potencia.log)"
    python3 fpga/informe.py implementacion "$rep" "$rep/potencia_saif.rpt" > "$rep/informe.md" \
        && echo "      informe (recursos, camino crítico, potencia): $rep/informe.md"
    return $rc
}

# --- argumentos ---------------------------------------------------------------------
list_layers() {
    local l name miss
    printf 'TOOLS_DIR = %s\n\n' "$TOOLS_DIR"
    for l in "${LAYERS[@]}"; do
        name=${l%%|*}; miss=$(missing_tools "$name")
        printf '%-15s %s\n' "$name" "$(echo "$l" | cut -d'|' -f2)"
        if [ -n "$miss" ]; then printf '%-15s   falta: %s\n' "" "$miss"; else printf '%-15s   herramientas: ok\n' ""; fi
    done
    printf '\nGrupos:\n'
    for g in todo rtl rapido fpga; do printf '  %-8s %s\n' "$g" "${LAYER_GROUPS[$g]}"; done
    printf '\nPara instalar las herramientas: tools/install.sh (ver verif/README.md).\n'
}

SELECTED=()
while [ $# -gt 0 ]; do
    case $1 in
        --lista|-l) list_layers; exit 0 ;;
        --variante) VARIANT=${2:?falta el nombre de la variante}; shift ;;
        -h|--help)  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)  if [ -n "${LAYER_GROUPS[$1]:-}" ]; then SELECTED+=(${LAYER_GROUPS[$1]})
            elif layer_field "$1" 1 > /dev/null; then SELECTED+=("$1")
            else echo "capa o grupo desconocido: $1 (ver ./run.sh --lista)"; exit 1; fi ;;
    esac
    shift
done
[ ${#SELECTED[@]} -gt 0 ] || SELECTED=(${LAYER_GROUPS[todo]})
if [ -n "$VARIANT" ]; then
    source tools/variant.sh
    variant_file "$VARIANT" > /dev/null || exit 1
fi

# --- corrida ------------------------------------------------------------------------
mkdir -p "$REPORTS"
declare -A RESULT DETAIL TIME
STATUS=0
for layer in "${SELECTED[@]}"; do
    [ -n "${RESULT[$layer]:-}" ] && continue          # una capa pedida dos veces corre una vez
    log="$REPORTS/$layer.log"
    miss=$(missing_tools "$layer")
    if [ -n "$miss" ]; then
        RESULT[$layer]=SKIP; DETAIL[$layer]="falta: $miss"; TIME[$layer]=0
        echo "falta: $miss" > "$log"
    else
        [ -t 1 ] && printf '%-15s ...\r' "$layer"
        t0=$SECONDS
        FPGA_KEY=$(version_of "${FPGA_FILES[@]}")
        "run_$layer" > "$log" 2>&1; rc=$?
        TIME[$layer]=$((SECONDS - t0))
        n_ok=$(grep -c '^\[ok \]' "$log"); n_bad=$(grep -c '^\[MAL\]' "$log")
        total=$((n_ok + n_bad))
        if [ "$total" -eq 0 ]; then
            RESULT[$layer]=FAIL; DETAIL[$layer]="no corrió ninguna prueba (código $rc)"
        elif [ "$n_bad" -gt 0 ] || [ "$rc" -ne 0 ]; then
            RESULT[$layer]=FAIL; DETAIL[$layer]="$n_ok/$total"
            [ "$n_bad" -eq 0 ] && DETAIL[$layer]+=" (el script terminó con código $rc)"
        else
            RESULT[$layer]=PASS; DETAIL[$layer]="$n_ok/$total"
            case $layer in sintesis|implementacion) save_verified "$layer" "$log" ;; esac
        fi
    fi
    case ${RESULT[$layer]} in
        FAIL) STATUS=1 ;;
        SKIP) [ $STATUS -eq 0 ] && STATUS=2 ;;
    esac
    printf '%-15s %-4s  %-40s %5ss\n' "$layer" "${RESULT[$layer]}" "${DETAIL[$layer]}" "${TIME[$layer]}"
    if [ "${RESULT[$layer]}" = FAIL ]; then
        grep '^\[MAL\]' "$log" | head -5 | sed 's/^/                /'
        printf '                log: %s\n' "$log"
    fi
done

# --- resumen ------------------------------------------------------------------------
tool_version() { command -v "$1" > /dev/null && "$@" 2>&1 | head -1 || echo "no instalado"; }
{
    echo "# Resumen de la verificación"
    echo
    echo "- Fecha: $(date '+%Y-%m-%d %H:%M')"
    echo "- Commit: $(git -C "$PROJ" rev-parse --short HEAD 2>/dev/null)$(git -C "$PROJ" diff --quiet HEAD -- . 2>/dev/null || echo ' (con cambios sin commitear)')"
    echo "- Variante: ${VARIANT:-ninguna (diseño base)}"
    echo
    echo "| Capa | Resultado | Pruebas | Tiempo | Log |"
    echo "|---|---|---|---|---|"
    for layer in "${SELECTED[@]}"; do
        [ -n "${RESULT[$layer]:-}" ] || continue
        echo "| $layer | ${RESULT[$layer]} | ${DETAIL[$layer]} | ${TIME[$layer]} s | [$layer.log]($layer.log) |"
        RESULT[$layer]=""   # no repetir
    done
    echo
    echo "## Herramientas"
    echo
    echo "- yosys: $(tool_version yosys -V)"
    echo "- verilator: $(tool_version verilator --version)"
    echo "- iverilog: $(tool_version iverilog -V)"
    echo "- riscv-none-elf-gcc: $(tool_version riscv-none-elf-gcc --version)"
    echo "- sail: $(tool_version sail_riscv_sim --version)"
    for d in riscv-formal riscv-arch-test; do
        echo "- $d: $(git -C "$TOOLS_DIR/$d" rev-parse --short HEAD 2>/dev/null || echo 'no instalado')"
    done
} > "$REPORTS/resumen.md"
echo "Resumen: $REPORTS/resumen.md"
exit $STATUS
}
