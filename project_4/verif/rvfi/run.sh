#!/usr/bin/env bash
# Genera y corre los chequeos de riscv-formal sobre el CPU de project_4.
#   ./run.sh                          el diseño, todos los chequeos (checks.cfg)
#   ./run.sh hazard_unit_nostall      con una variante de ../variants/
#   ./run.sh checks reg_ch0           un solo chequeo
set -u
cd "$(dirname "$0")"
source ../env.sh
source ../tools/variant.sh
CFG=${1:-checks}; shift || true
HERE=$(pwd)
RF=$(cd ../../../.tools 2>/dev/null && pwd)/riscv-formal
[ -d "$RF" ] || { echo "falta riscv-formal en .tools/ (ver README.md)"; exit 1; }

# riscv-formal espera el core en cores/<nombre>/ y deduce las rutas del
# directorio real, así que ahí armamos una carpeta con enlaces a estos archivos.
CORE="$RF/cores/tp4"
mkdir -p "$CORE"
for f in checks.cfg wrapper.sv imem_anyseq.v pma.sv; do ln -sfn "$HERE/$f" "$CORE/$f"; done
# Con una variante: la misma configuración, con el archivo del RTL reemplazado.
if [ "$CFG" != checks ]; then
    target=$(variant_target "$CFG") || exit 1
    sed "s|^@basedir@/../../project_4/project_4.srcs/sources_1/new/pipeline/$target\$|$(variant_file "$CFG")|" \
        checks.cfg > "$CORE/$CFG.cfg"
    grep -q "$(variant_file "$CFG")" "$CORE/$CFG.cfg" || { echo "no se pudo reemplazar $target"; exit 1; }
    rm -rf "${CORE:?}/$CFG"
fi
(cd "$CORE" && python3 ../../checks/genchecks.py "$CFG") || exit 1

targets=()
for t in "$@"; do targets+=("$t/status"); done
make -C "$CORE/$CFG" -j"$(nproc)" -k "${targets[@]}" > "$CORE/$CFG/make.log" 2>&1

# Resumen: un renglón por chequeo
for d in "$CORE/$CFG"/*/; do
    printf '%-18s %s\n' "$(basename "$d")" "$(cut -d' ' -f1 "$d/status" 2>/dev/null || echo '?')"
done | sort -k2 -k1
echo "(resultados completos en $CORE/$CFG/)"
