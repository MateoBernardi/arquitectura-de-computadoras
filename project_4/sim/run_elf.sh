#!/usr/bin/env bash
# Corre un ELF en el simulador. Uso: run_elf.sh [--elf] <archivo.elf> [+max-cycles=N]
# Código de salida 0 = PASS. Es el comando que usa run_act.sh.
# VARIANT=<nombre> usa el simulador de esa variante (./build.sh <nombre>).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ "${1:-}" = "--elf" ] && shift
ELF="$1"; shift
export PATH="$(echo "$HERE"/../../.tools/xpack-riscv-none-elf-gcc-*/bin):$PATH"
CROSS="${CROSS:-riscv-none-elf}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
"$CROSS-objcopy" -O binary "$ELF" "$TMP/img.bin" || exit 2
python3 - "$TMP/img.bin" "$TMP/img.hex" <<'PY' || exit 2
import struct, sys
d = open(sys.argv[1], "rb").read()
d += b"\0" * (-len(d) % 4)
open(sys.argv[2], "w").write("".join("%08x\n" % w for w in struct.unpack("<%dI" % (len(d) // 4), d)))
PY
"$HERE/build/${VARIANT:-base}/Vtb" "+hex=$TMP/img.hex" "$@"
