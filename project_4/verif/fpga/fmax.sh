#!/usr/bin/env bash
# Busca la frecuencia máxima del sistema en pasos de 10 MHz: sintetiza e implementa el
# diseño a 50, 60, 70, 80, 90 y 100 MHz, en ese orden, y se detiene en la primera que no
# pasa los chequeos de la implementación (check_impl.py: STA completo, ruteo, DRC). Pasos
# más chicos no valen la pena: solo interesa una mejora significativa. No es una capa de
# verificación: es una búsqueda; el resultado se fija en los parámetros MMCM_MULT /
# MMCM_DIV_X8 de top_riscv.
#
#   verif/fpga/fmax.sh                 el diseño de rtl/
#   verif/fpga/fmax.sh <variante>      con una variante de verif/variants/ (ver tools/variant.sh)
#
# Frecuencias exactas del MMCM: divisor 10 (MMCM_DIV_X8 = 80) y MMCM_MULT = f / 10 MHz,
# así el VCO va de 600 a 1000 MHz (el rango del Artix-7 -1 es 600-1200). 50 MHz usa
# MMCM_MULT = 10 y MMCM_DIV_X8 = 160 (divisor 20): con divisor 10 el VCO quedaría en
# 500 MHz, fuera de rango.
# La estimación por el margen de setup no sirve para decidir: cada frecuencia da otra
# ubicación y otro ruteo. Por eso cada punto se implementa.
# Cada punto tarda unos 8 minutos. Todo queda en build/vivado_fmax/<nombre>/ y
# build/reports/fmax/<nombre>/ (<nombre> = base o la variante): se pueden correr en paralelo.
# Necesita Vivado.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../env.sh"
NAME=${1:-base}
WORK="$PROJ/build/vivado_fmax/$NAME"; REP="$PROJ/build/reports/fmax/$NAME"
rm -rf "$WORK" "$REP"; mkdir -p "$WORK" "$REP"
export TP4_PROJECT_DIR="$WORK/proyecto" TP4_BUILD_ID=0
if [ "$NAME" != base ]; then          # copia del RTL con la variante en su lugar
    source "$HERE/../tools/variant.sh"
    target=$(variant_target "$NAME") || exit 1
    cp -r "$RTL_DIR" "$WORK/rtl" && cp "$(variant_file "$NAME")" "$WORK/rtl/pipeline/$target" || exit 1
    export TP4_RTL_DIR="$WORK/rtl"
    echo "variante $NAME: reemplaza pipeline/$target"
fi
(cd "$WORK" && vivado -mode batch -nojournal -log "$WORK/proyecto.log" -source "$HERE/create_project.tcl" > /dev/null) || exit 1

TABLE="$REP/fmax.md"
printf '| Frecuencia | MMCM_MULT | WNS (ns) | WHS (ns) | Resultado |\n|---|---|---|---|---|\n' > "$TABLE"
best=0
for mult in 5 6 7 8 9 10; do
    f=$((mult * 10)); rep="$REP/${f}mhz"
    if [ $f = 50 ]; then export TP4_MMCM_MULT=10 TP4_MMCM_DIV_X8=160
    else export TP4_MMCM_MULT=$mult TP4_MMCM_DIV_X8=80; fi
    export TP4_REPORT_DIR="$rep"
    (cd "$WORK" && vivado -mode batch -nojournal -log "$WORK/${f}mhz.log" -source "$HERE/synth.tcl" > /dev/null &&
                   vivado -mode batch -nojournal -log "$WORK/${f}mhz.log" -source "$HERE/impl.tcl" > /dev/null)
    python3 "$HERE/check_impl.py" "$WORK/proyecto/tp4.runs/impl_1/runme.log" "$rep" "$HERE/waivers.txt" > "$rep.check" 2>&1
    ok=$?; res=PASS; [ $ok -eq 0 ] || res=FAIL
    wns=$(sed -n 's/.*setup: WNS = \([-+0-9.]*\).*/\1/p' "$rep.check"); whs=$(sed -n 's/.*hold: WHS = \([-+0-9.]*\).*/\1/p' "$rep.check")
    printf '| %d MHz | %d | %s | %s | %s |\n' "$f" "$TP4_MMCM_MULT" "${wns:-?}" "${whs:-?}" "$res" | tee -a "$TABLE"
    [ $ok -eq 0 ] || break
    best=$f
done
[ $best -gt 0 ] || { echo "ni siquiera 50 MHz cierra"; exit 1; }
printf '\nFrecuencia máxima que cierra (en pasos de 10 MHz): %d MHz\n' "$best" | tee -a "$TABLE"
