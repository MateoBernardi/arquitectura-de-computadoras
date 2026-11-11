#!/usr/bin/env bash
# Suite oficial riscv-arch-test (ACT4) en el simulador.
#
#   ./run_act.sh                 compila los tests (ELFs autoverificados contra Sail) y los corre
#   EXTENSIONS=I ./run_act.sh    solo una suite
#
# Los ELFs y los logs quedan en build/sim/act/tp4-rv32i/ (elfs/, logs/, summary.log).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../env.sh"
ACT="$TOOLS_DIR/riscv-arch-test"
WORK="$PROJ/build/sim/act"
eval "$(mise env -C "$ACT" -s bash)"

"$HERE/build.sh" ${VARIANT:-} > /dev/null    # siempre: así nunca se corre un binario viejo

make -C "$ACT" CONFIG_FILES="$HERE/act/tp4-rv32i/test_config.yaml" WORKDIR="$WORK" \
    ${EXTENSIONS:+EXTENSIONS=$EXTENSIONS}
SUMMARY="$WORK/tp4-rv32i/summary.log"
rm -rf "$SUMMARY" "$WORK/tp4-rv32i/logs"     # nunca leer el resultado de una corrida anterior
STATUS=0
(cd "$ACT" && mise exec -- ./run_tests.py "$HERE/run_elf.sh --elf" "$WORK/tp4-rv32i/elfs" --timeout 60) || STATUS=$?

# Un renglón por test, en el formato común: [ok ] / [MAL]
[ -f "$SUMMARY" ] || { echo "[MAL] no se generó $SUMMARY"; exit 1; }
awk '{ t = $1; sub(/.*\//, "", t); sub(/\.log$/, "", t)
       if ($0 ~ /RVCP-SUMMARY: TEST PASSED/) print "[ok ] " t; else print "[MAL] " t ": " substr($0, index($0, $2)) }' "$SUMMARY"
exit $STATUS
