# Rutas y herramientas comunes a todos los scripts de verificación (se carga con `source`).
#   PROJ       raíz del proyecto (project_4/)
#   RTL_DIR    el RTL (rtl/)
#   TOOLS_DIR  herramientas instaladas (OSS CAD Suite, riscv-formal, Sail, GCC, ...);
#              por defecto ../.tools, se puede cambiar con la variable de entorno TOOLS_DIR
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTL_DIR="$PROJ/rtl"
TOOLS_DIR="${TOOLS_DIR:-$(cd "$PROJ/.." && pwd)/.tools}"
export PATH="$TOOLS_DIR/oss-cad-suite/bin:$PATH"
