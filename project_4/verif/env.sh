# Usage: source verif/env.sh   (adds the OSS CAD Suite tools to PATH)
_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$_root/.tools/oss-cad-suite/bin:$PATH"
unset _root
