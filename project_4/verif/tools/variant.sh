# Helper de variantes (se carga con `source`).
#
# Una variante (verif/variants/<nombre>.v) declara un módulo con el MISMO nombre y
# los MISMOS puertos que uno del RTL, y reemplaza entero al archivo del RTL que lo
# declara. (Si ese archivo tiene varios módulos, la variante tiene que traerlos todos.)
#
#   variant_file <nombre>     ruta absoluta de la variante (o error)
#   variant_target <nombre>   ruta del archivo del RTL que reemplaza, relativa a pipeline/

source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
VARIANTS_DIR="$PROJ/verif/variants"
PIPELINE_RTL="$RTL_DIR/pipeline"

variant_file() {
    local f="$VARIANTS_DIR/$1.v"
    [ -f "$f" ] || { echo "no existe la variante '$1' (opciones: $(cd "$VARIANTS_DIR" && ls *.v | sed 's/\.v$//' | tr '\n' ' '))" >&2; return 1; }
    echo "$f"
}

variant_target() {
    local f mod hits
    f=$(variant_file "$1") || return 1
    mod=$(sed -n 's/^module[[:space:]]\+\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' "$f" | head -1)
    hits=$(cd "$PIPELINE_RTL" && grep -rl --include='*.v' "^module[[:space:]]\+$mod\b" .)
    [ "$(echo "$hits" | grep -c .)" = 1 ] || { echo "variante '$1': el módulo '$mod' no está en exactamente un archivo del RTL" >&2; return 1; }
    echo "${hits#./}"
}
