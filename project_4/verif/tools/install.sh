#!/usr/bin/env bash
# Instala las herramientas de verificación en TOOLS_DIR (por defecto ../.tools, al lado de
# project_4/; se cambia con la variable de entorno TOOLS_DIR). Linux x86-64.
#
#   verif/tools/install.sh            instala lo que falte
#   verif/tools/install.sh --check    solo dice qué falta (lo mismo que ../run.sh --lista)
#
# Versiones fijas, las mismas con las que se obtuvieron los resultados de verif/README.md.
# Lo que ya está instalado no se toca. Necesita: curl, tar, git, python3.
# Aparte, del sistema: python3-tk (tests de la GUI). Vivado no se instala acá.
set -euo pipefail
source "$(dirname "$0")/../env.sh"

OSS_CAD_DATE=2026-10-27        # OSS CAD Suite: yosys, sby, solvers, verilator, iverilog
RISCV_FORMAL_REV=c992aa61fdfe0846c5ed90324c596202a1c69b76
ARCH_TEST_REV=4b220ad2a4a1c38e296d6def4043f06a9b82fbf2
SAIL_VERSION=0.16              # modelo de referencia de la ISA (lo usa riscv-arch-test)
XPACK_GCC=15.2.0-1             # GCC RISC-V; riscv-arch-test exige GCC 15

if [ "${1:-}" = --check ]; then exec "$PROJ/verif/run.sh" --lista; fi

mkdir -p "$TOOLS_DIR"
cd "$TOOLS_DIR"
echo "TOOLS_DIR = $TOOLS_DIR"

step() { printf '\n== %s\n' "$1"; }

step "OSS CAD Suite $OSS_CAD_DATE"
if [ -x oss-cad-suite/bin/yosys ]; then echo "ya instalada"; else
    curl -fL "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$OSS_CAD_DATE/oss-cad-suite-linux-x64-${OSS_CAD_DATE//-/}.tgz" | tar xz
fi

step "riscv-formal"
if [ -d riscv-formal/checks ]; then echo "ya instalado"; else
    git clone https://github.com/YosysHQ/riscv-formal.git
    git -C riscv-formal checkout -q "$RISCV_FORMAL_REV"
fi

step "Sail $SAIL_VERSION"
if [ -x sail/bin/sail_riscv_sim ]; then echo "ya instalado"; else
    mkdir -p sail
    curl -fL "https://github.com/riscv/sail-riscv/releases/download/$SAIL_VERSION/sail-riscv-Linux-x86_64.tar.gz" \
        | tar xz -C sail --strip-components=1
fi

step "GCC RISC-V (xPack $XPACK_GCC)"
if [ -d "xpack-riscv-none-elf-gcc-$XPACK_GCC" ]; then echo "ya instalado"; else
    curl -fL "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$XPACK_GCC/xpack-riscv-none-elf-gcc-$XPACK_GCC-linux-x64.tar.gz" | tar xz
fi

step "mise (gestor de entornos que usa riscv-arch-test)"
if command -v mise > /dev/null; then echo "ya instalado"; else
    curl -fsSL https://mise.run | sh            # se instala en ~/.local/bin
    export PATH="$HOME/.local/bin:$PATH"
fi

step "riscv-arch-test"
if [ -d riscv-arch-test/.git ]; then echo "ya instalado"; else
    git clone https://github.com/riscv-non-isa/riscv-arch-test.git
    git -C riscv-arch-test checkout -q "$ARCH_TEST_REV"
fi
(cd riscv-arch-test && mise trust .mise.toml && mise install)

step "Resultado"
"$PROJ/verif/run.sh" --lista
