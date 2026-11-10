#!/usr/bin/env bash
# Tests dirigidos de traps (tests/traps/*.S): cada uno declara en la primera línea
# "# expect: <causa> <pc>", donde <pc> es el símbolo 'fault' o una dirección.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$(echo "$HERE"/../../.tools/xpack-riscv-none-elf-gcc-*/bin):$PATH"
[ -x "$HERE/build/Vtb" ] || "$HERE/build.sh"
OUT="$HERE/work/traps"; mkdir -p "$OUT"
fail=0
for s in "$HERE"/tests/traps/*.S; do
    n=$(basename "$s" .S)
    read -r _ _ cause pc < "$s"
    riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Ttext=0 -o "$OUT/$n.elf" "$s" || { fail=1; continue; }
    [ "$pc" = fault ] && pc=$(riscv-none-elf-nm "$OUT/$n.elf" | awk '$3=="fault"{print $1}')
    if "$HERE/run_elf.sh" "$OUT/$n.elf" "+expect-cause=$cause" "+expect-pc=${pc#0x}" > "$OUT/$n.log" 2>&1; then
        printf '[ok ] %-16s causa %-2s\n' "$n" "$cause"
    else
        printf '[XX ] %-16s %s\n' "$n" "$(grep -m1 'tb:' "$OUT/$n.log")"; fail=1
    fi
done
exit $fail
