#!/usr/bin/env bash
# Verificación del proyecto por capas, en el orden del flujo:
#   RTL (formal, rvfi, act, traps, rendimiento) → sistema → host
#
#   ./run.sh                     todas las capas
#   ./run.sh act traps           solo esas capas
#   ./run.sh rapido              grupo: todo menos riscv-formal (la capa más larga)
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
)
declare -A LAYER_GROUPS=(
    [todo]="formal rvfi act traps rendimiento sistema host"
    [rtl]="formal rvfi act traps rendimiento"
    [rapido]="formal act traps rendimiento sistema host"
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
        esac
    done
    echo "${miss[*]}"
}

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
run_rendimiento() { sim/bench.py; }
run_sistema()     { system/run.sh; }
run_host()        { python3 tools/pyunit.py "$PROJ/host/tests"; }

# --- argumentos ---------------------------------------------------------------------
list_layers() {
    local l name miss
    printf 'TOOLS_DIR = %s\n\n' "$TOOLS_DIR"
    for l in "${LAYERS[@]}"; do
        name=${l%%|*}; miss=$(missing_tools "$name")
        printf '%-12s %s\n' "$name" "$(echo "$l" | cut -d'|' -f2)"
        if [ -n "$miss" ]; then printf '%-12s   falta: %s\n' "" "$miss"; else printf '%-12s   herramientas: ok\n' ""; fi
    done
    printf '\nGrupos:\n'
    for g in todo rtl rapido; do printf '  %-8s %s\n' "$g" "${LAYER_GROUPS[$g]}"; done
    printf '\nPara instalar las herramientas: tools/install.sh (ver verif/README.md).\n'
}

SELECTED=()
while [ $# -gt 0 ]; do
    case $1 in
        --lista|-l) list_layers; exit 0 ;;
        --variante) VARIANT=${2:?falta el nombre de la variante}; shift ;;
        -h|--help)  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
        [ -t 1 ] && printf '%-12s ...\r' "$layer"
        t0=$SECONDS
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
        fi
    fi
    case ${RESULT[$layer]} in
        FAIL) STATUS=1 ;;
        SKIP) [ $STATUS -eq 0 ] && STATUS=2 ;;
    esac
    printf '%-12s %-4s  %-40s %5ss\n' "$layer" "${RESULT[$layer]}" "${DETAIL[$layer]}" "${TIME[$layer]}"
    if [ "${RESULT[$layer]}" = FAIL ]; then
        grep '^\[MAL\]' "$log" | head -5 | sed 's/^/             /'
        printf '             log: %s\n' "$log"
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
