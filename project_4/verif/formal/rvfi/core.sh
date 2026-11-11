# Helper de rvfi/run.sh y rvfi/mutants.sh (se carga con `source`).
#
# riscv-formal espera cada core en <riscv-formal>/cores/<nombre>/, así que ahí se arma
# cores/tp4/ con enlaces a los archivos de esta carpeta.
#
#   make_cfg <nombre> [<archivo de pipeline/> <reemplazo>]
#       escribe cores/tp4/<nombre>.cfg desde checks.cfg, con @rtl@ resuelto y,
#       opcionalmente, un archivo del RTL reemplazado por otro (variante o mutante).
#   gen <nombre>     genera los chequeos en cores/tp4/<nombre>/
source "$(dirname "${BASH_SOURCE[0]}")/../../env.sh"
RVFI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RF="$TOOLS_DIR/riscv-formal"
[ -d "$RF/checks" ] || { echo "falta riscv-formal en $RF (ver verif/README.md)"; exit 1; }
CORE="$RF/cores/tp4"
mkdir -p "$CORE"
for f in wrapper.sv imem_anyseq.v pma.sv; do ln -sfn "$RVFI_DIR/$f" "$CORE/$f"; done

make_cfg() {
    local name=$1 file=${2:-} repl=${3:-}
    local cfg="$CORE/$name.cfg"
    rm -f "$cfg"                     # puede ser un enlace viejo
    if [ -n "$file" ]; then
        sed "s|^@rtl@/pipeline/$file\$|$repl|" "$RVFI_DIR/checks.cfg" > "$cfg"
        grep -qx "$repl" "$cfg" || { echo "no se pudo reemplazar pipeline/$file en checks.cfg"; exit 1; }
    else
        cp "$RVFI_DIR/checks.cfg" "$cfg"
    fi
    sed -i "s|@rtl@|$RTL_DIR|g" "$cfg"
    [ -s "$cfg" ] || { echo "no se pudo escribir $cfg"; exit 1; }
}

gen() {
    rm -rf "${CORE:?}/$1"
    (cd "$CORE" && python3 ../../checks/genchecks.py "$1" > /dev/null) || exit 1
}
