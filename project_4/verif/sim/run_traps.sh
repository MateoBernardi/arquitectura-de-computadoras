#!/usr/bin/env bash
# Tests propios de traps (tests/traps/*.S). Existen porque la suite oficial
# (riscv-arch-test), tal como la corremos, no prueba las excepciones: lo hace con un
# manejador en M-mode que necesita CSRs, y este CPU no los tiene. Que haya trap lo
# verifica riscv-formal; acá se verifica la causa y el PC que reporta el CPU.
# Cada test declara en la primera línea "# expect: <causa> <pc>", donde <pc> es el
# símbolo 'fault' o una dirección.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../env.sh"
"$HERE/build.sh" ${VARIANT:-} > /dev/null    # siempre: así nunca se corre un binario viejo
OUT="$PROJ/build/sim/traps"; mkdir -p "$OUT"
fail=0; n_run=0
for s in "$HERE"/tests/traps/*.S; do
    n=$(basename "$s" .S); n_run=$((n_run + 1))
    read -r _ _ cause pc < "$s"
    riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Ttext=0 -o "$OUT/$n.elf" "$s" || { fail=1; continue; }
    [ "$pc" = fault ] && pc=$(riscv-none-elf-nm "$OUT/$n.elf" | awk '$3=="fault"{print $1}')
    if "$HERE/run_elf.sh" "$OUT/$n.elf" "+expect-cause=$cause" "+expect-pc=${pc#0x}" > "$OUT/$n.log" 2>&1; then
        printf '[ok ] %-16s causa %-2s\n' "$n" "$cause"
    else
        printf '[MAL] %-16s %s\n' "$n" "$(grep -m1 'tb:' "$OUT/$n.log")"; fail=1
    fi
done
[ "$n_run" -gt 0 ] || { echo "no se encontró ningún test en tests/traps/"; exit 1; }
echo "$n_run tests"
exit $fail
