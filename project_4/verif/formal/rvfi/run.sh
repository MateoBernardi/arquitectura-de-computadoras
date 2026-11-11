#!/usr/bin/env bash
# Genera y corre los chequeos de riscv-formal sobre el CPU.
#   ./run.sh                          el diseño, todos los chequeos (checks.cfg)
#   ./run.sh hazard_unit_nostall      con una variante de verif/variants/
#   ./run.sh checks reg_ch0           un solo chequeo
set -u
source "$(dirname "$0")/core.sh"
source "$RVFI_DIR/../../tools/variant.sh"
CFG=${1:-checks}; shift || true

if [ "$CFG" = checks ]; then
    make_cfg checks
else
    target=$(variant_target "$CFG") || exit 1
    make_cfg "$CFG" "$target" "$(variant_file "$CFG")"
fi
gen "$CFG"

targets=()
for t in "$@"; do targets+=("$t/status"); done
make -C "$CORE/$CFG" -j"$(nproc)" -k "${targets[@]}" > "$CORE/$CFG/make.log" 2>&1
STATUS=$?

# Resumen: un renglón por chequeo
for d in "$CORE/$CFG"/*/; do
    printf '%-18s %s\n' "$(basename "$d")" "$(cut -d' ' -f1 "$d/status" 2>/dev/null || echo '?')"
done | sort -k2 -k1
echo "(resultados completos en $CORE/$CFG/)"
exit $STATUS
