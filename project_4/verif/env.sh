# Rutas y herramientas comunes a todos los scripts de verificación (se carga con `source`).
#   PROJ       raíz del proyecto (project_4/)
#   RTL_DIR    el RTL (rtl/)
#   TOOLS_DIR  herramientas instaladas por tools/install.sh; por defecto ../.tools (al lado
#              de project_4/), se puede cambiar con la variable de entorno TOOLS_DIR.
# Las herramientas de TOOLS_DIR van primero en el PATH; si alguna no está ahí, se usa la
# del sistema (por ejemplo, un Verilator o un GCC RISC-V instalados con el gestor de paquetes).
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTL_DIR="$PROJ/rtl"
TOOLS_DIR="${TOOLS_DIR:-$(cd "$PROJ/.." && pwd)/.tools}"
for _d in "$TOOLS_DIR"/oss-cad-suite/bin "$TOOLS_DIR"/xpack-riscv-none-elf-gcc-*/bin "$TOOLS_DIR"/sail/bin; do
    [ -d "$_d" ] && PATH="$_d:$PATH"
done
PATH="$PATH:$HOME/.local/bin"      # mise (lo usa riscv-arch-test) se instala ahí
export PATH
unset _d
