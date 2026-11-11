#!/usr/bin/env bash
# Genera y corre los chequeos de riscv-formal sobre el CPU.
#   ./run.sh                          el diseño, todos los chequeos (checks.cfg)
#   ./run.sh hazard_unit_precise      con una variante de verif/variants/
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

# Un renglón por chequeo: [ok ] si dio PASS, [MAL] si no (FAIL, ERROR o no corrió)
checks=("$@"); [ $# -gt 0 ] || checks=($(cd "$CORE/$CFG" && ls -d */ | tr -d /))
for c in "${checks[@]}"; do
    d="$CORE/$CFG/$c"
    r=$(cut -d' ' -f1 "$d/status" 2>/dev/null || echo '?')
    [ "$r" = PASS ] && m="ok " || m="MAL"
    printf '[%s] %-18s %s\n' "$m" "$(basename "$d")" "$r"
done | sort -k1,1r -k2
echo "(resultados completos en $CORE/$CFG/)"
exit $STATUS
