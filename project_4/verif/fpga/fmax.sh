#!/usr/bin/env bash
# Busca la frecuencia máxima del sistema en pasos de 10 MHz: sintetiza e implementa el
# diseño a 60, 70, 80, 90 y 100 MHz, en ese orden, y se detiene en la primera que no pasa
# los chequeos de la implementación (check_impl.py: STA completo, ruteo, DRC). Pasos más
# chicos no valen la pena: solo interesa una mejora significativa sobre los 50 MHz que ya
# funcionan. No es una capa de verificación: es una búsqueda; el resultado se fija en los
# parámetros MMCM_MULT / MMCM_DIV_X8 de top_riscv.
#
#   verif/fpga/fmax.sh
#
# Frecuencias exactas del MMCM: divisor 10 (MMCM_DIV_X8 = 80) y MMCM_MULT = f / 10 MHz,
# así el VCO va de 600 a 1000 MHz (el rango del Artix-7 -1 es 600-1200).
# La estimación por el margen de setup no sirve para decidir: cada frecuencia da otra
# ubicación y otro ruteo. Por eso cada punto se implementa.
# Cada punto tarda unos 8 minutos. Todo queda en build/vivado_fmax/ y build/reports/fmax/.
# Necesita Vivado.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../env.sh"
WORK="$PROJ/build/vivado_fmax"; REP="$PROJ/build/reports/fmax"
rm -rf "$WORK" "$REP"; mkdir -p "$WORK" "$REP"
export TP4_PROJECT_DIR="$WORK/proyecto" TP4_MMCM_DIV_X8=80 TP4_BUILD_ID=0
(cd "$WORK" && vivado -mode batch -nojournal -log "$WORK/proyecto.log" -source "$HERE/create_project.tcl" > /dev/null) || exit 1

TABLE="$REP/fmax.md"
printf '| Frecuencia | MMCM_MULT | WNS (ns) | WHS (ns) | Resultado |\n|---|---|---|---|---|\n' > "$TABLE"
best=50
for mult in 6 7 8 9 10; do
    f=$((mult * 10)); rep="$REP/${f}mhz"
    export TP4_MMCM_MULT=$mult TP4_REPORT_DIR="$rep"
    (cd "$WORK" && vivado -mode batch -nojournal -log "$WORK/${f}mhz.log" -source "$HERE/synth.tcl" > /dev/null &&
                   vivado -mode batch -nojournal -log "$WORK/${f}mhz.log" -source "$HERE/impl.tcl" > /dev/null)
    python3 "$HERE/check_impl.py" "$WORK/proyecto/tp4.runs/impl_1/runme.log" "$rep" "$HERE/waivers.txt" > "$rep.check" 2>&1
    ok=$?; res=PASS; [ $ok -eq 0 ] || res=FAIL
    wns=$(sed -n 's/.*setup: WNS = \([-+0-9.]*\).*/\1/p' "$rep.check"); whs=$(sed -n 's/.*hold: WHS = \([-+0-9.]*\).*/\1/p' "$rep.check")
    printf '| %d MHz | %d | %s | %s | %s |\n' "$f" "$mult" "${wns:-?}" "${whs:-?}" "$res" | tee -a "$TABLE"
    [ $ok -eq 0 ] || break
    best=$f
done
printf '\nFrecuencia máxima que cierra (en pasos de 10 MHz): %d MHz\n' "$best" | tee -a "$TABLE"
