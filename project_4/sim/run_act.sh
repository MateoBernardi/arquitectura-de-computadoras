#!/usr/bin/env bash
# Suite oficial riscv-arch-test (ACT4) en el simulador.
#
#   ./run_act.sh                 compila los tests (ELFs autoverificados contra Sail) y los corre
#   EXTENSIONS=I ./run_act.sh    solo una suite
#
# Los ELFs y los logs quedan en work/tp4-rv32i/ (elfs/, logs/, summary.log).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ACT="$ROOT/.tools/riscv-arch-test"
source "$HERE/../verif/env.sh"
export PATH="$(echo "$ROOT"/.tools/xpack-riscv-none-elf-gcc-*/bin):$ROOT/.tools/sail/bin:$HOME/.local/bin:$PATH"
eval "$(mise env -C "$ACT" -s bash)"

[ -x "$HERE/build/Vtb" ] || "$HERE/build.sh"

make -C "$ACT" CONFIG_FILES="$HERE/act/tp4-rv32i/test_config.yaml" WORKDIR="$HERE/work" \
    ${EXTENSIONS:+EXTENSIONS=$EXTENSIONS}
cd "$ACT"
mise exec -- ./run_tests.py "$HERE/run_elf.sh --elf" "$HERE/work/tp4-rv32i/elfs" --timeout 60
