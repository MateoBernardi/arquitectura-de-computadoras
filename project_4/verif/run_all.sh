#!/usr/bin/env bash
# Toda la verificación del RTL, de punta a punta, con un resumen por etapa.
#
#   ./run_all.sh              todo (~25 min; riscv-formal es lo más largo)
#   RVFI=0 ./run_all.sh       sin riscv-formal (~5 min)
#   VARIANTS=1 ./run_all.sh   además, riscv-formal con cada variante (~10 min c/u)
#
# Los logs quedan en build/run_all/<etapa>.log.
cd "$(dirname "$0")" || exit 1
source env.sh
source tools/variant.sh
LOG=build/run_all; mkdir -p "$LOG"
STATUS=0

stage() {   # stage <nombre> <comando...>
    local name=$1; shift
    local t0=$SECONDS
    if "$@" > "$LOG/$name.log" 2>&1; then
        printf '[ok ] %-24s %4ds\n' "$name" $((SECONDS - t0))
    else
        printf '[MAL] %-24s %4ds   (ver %s/%s.log)\n' "$name" $((SECONDS - t0)) "$LOG" "$name"
        STATUS=1
    fi
}

# riscv-formal: falla si el script falla, si no corrió ningún chequeo o si alguno no da PASS
rvfi() {
    set -o pipefail
    formal/rvfi/run.sh "$1" | tee /dev/stderr |
        awk 'NF == 2 { n++; if ($2 != "PASS") bad = 1 } END { exit (bad || n == 0) }'
}

stage forward_unit        formal/forward_unit/run.sh
stage hazard_unit         formal/hazard_unit/run.sh
stage pipeline_control    formal/pipeline_control/run.sh
stage datapath            formal/datapath/run.sh
if [ "${RVFI:-1}" != 0 ]; then
    stage rvfi                rvfi checks
    stage rvfi_mutantes       formal/rvfi/mutants.sh
    if [ "${VARIANTS:-0}" = 1 ]; then
        for v in "$VARIANTS_DIR"/*.v; do v=$(basename "$v" .v); stage "rvfi_$v" rvfi "$v"; done
    fi
fi
stage act                 sim/run_act.sh
stage traps               sim/run_traps.sh
stage sistema_uart        system/run.sh
stage host                bash -c 'cd ../host && python3 -m unittest discover -s tests'
stage bench_variantes     sim/bench.py
exit $STATUS
