# Helper compartido por los run.sh de cada suite (se carga con `source`).
#
# Antes de cargarlo, el run.sh define:
#   NAME — nombre base del .sby (ej.: forward_unit → forward_unit.sby)
#
# Funciones:
#   mutate <rtl.v> <nombre> <expr sed>   copia el RTL con un error inyectado
#                                        en build/mutants/<base>_mut_<nombre>.v
#   expect <tarea> <PASS|FAIL|UNKNOWN> [brief]
#                                        corre la tarea y compara con lo esperado.
#                                        Si falla muestra el contraejemplo; con
#                                        "brief" lista solo los covers alcanzados.
# Al final, el run.sh termina con:  exit $STATUS

_TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # antes del cd: la ruta puede ser relativa
source "$_TOOLS/../env.sh"
cd "$(dirname "$0")" || exit 1
BUILD="$PROJ/build/formal/$(basename "$(pwd)")"   # todo lo generado (los .sby apuntan acá)
STATUS=0
mkdir -p "$BUILD/mutants"

mutate() {
    local rtl=$1 name=$2 expr=$3
    local out="$BUILD/mutants/$(basename "${rtl%.v}")_mut_$name.v"
    sed "$expr" "$rtl" > "$out"
    if cmp -s "$rtl" "$out"; then
        echo "ERROR: el mutante '$name' no cambió nada (¿cambió el RTL?)"
        exit 1
    fi
}

expect() {
    local task=$1 want=$2 mode=${3:-full}
    sby --prefix "$BUILD/$NAME" -f "$NAME.sby" "$task" > /dev/null 2>&1
    local result
    result=$(cut -d' ' -f1 "$BUILD/${NAME}_$task/status" 2>/dev/null)
    local mark="ok "
    if [ "$result" != "$want" ]; then mark="MAL"; STATUS=1; fi
    printf '[%s] %-12s → %-5s (esperado %s)\n' "$mark" "$task" "${result:-ERROR}" "$want"
    if [ "$result" = FAIL ] || [ "$result" = UNKNOWN ] || [ "$mode" = brief ]; then
        local flag=""
        [ "$mode" = brief ] && flag="--brief"
        python3 "$_TOOLS/show_trace.py" $flag "$BUILD/${NAME}_$task" | sed 's/^/        /'
    fi
}
