#!/usr/bin/env bash
# Busca la frecuencia máxima del sistema: sintetiza e implementa el diseño a frecuencias
# crecientes y se queda con la más alta que pasa todos los chequeos de la implementación
# (check_impl.py: STA completo, ruteo, DRC). No es una capa de verificación: es una
# búsqueda; el resultado se fija en los parámetros MMCM_MULT / MMCM_DIV_X8 de top_riscv.
#
#   verif/fpga/fmax.sh
#
# Método: implementa a 50 MHz (la frecuencia que ya funciona, el piso) y estima la Fmax
# con el margen de setup: Fmax ≈ 1 / (período − WNS). Después prueba, de menor a mayor,
# las frecuencias que el MMCM puede generar hasta un 5 % por encima de esa estimación,
# porque al cambiar la restricción cambian la ubicación y el ruteo y la estimación no
# alcanza: hay que confirmar implementando. Termina tras 2 fallas seguidas.
# Cada punto tarda unos 8 minutos. Todo queda en build/vivado_fmax/ y build/reports/fmax/.
# Necesita Vivado y bc.
set -uo pipefail
export LC_NUMERIC=C      # punto decimal en printf, cualquiera sea el idioma del sistema
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../env.sh"
WORK="$PROJ/build/vivado_fmax"; REP="$PROJ/build/reports/fmax"
rm -rf "$WORK" "$REP"; mkdir -p "$WORK" "$REP"
export TP4_PROJECT_DIR="$WORK/proyecto" TP4_MMCM_MULT=10    # VCO = 1000 MHz
export TP4_BUILD_ID=0
(cd "$WORK" && vivado -mode batch -nojournal -log "$WORK/proyecto.log" -source "$HERE/create_project.tcl" > /dev/null) || exit 1

TABLE="$REP/fmax.md"
printf '| Frecuencia | MMCM_DIV_X8 | WNS (ns) | WHS (ns) | Resultado |\n|---|---|---|---|---|\n' > "$TABLE"
try() {   # try <MMCM_DIV_X8> → imprime "PASS|FAIL <wns> <whs>"
    local d=$1 rep="$REP/div$1"
    export TP4_MMCM_DIV_X8=$d TP4_REPORT_DIR="$rep"
    (cd "$WORK" && vivado -mode batch -nojournal -log "$WORK/div$d.log" -source "$HERE/synth.tcl" > /dev/null &&
                   vivado -mode batch -nojournal -log "$WORK/div$d.log" -source "$HERE/impl.tcl" > /dev/null)
    python3 "$HERE/check_impl.py" "$WORK/proyecto/tp4.runs/impl_1/runme.log" "$rep" "$HERE/waivers.txt" > "$rep.check" 2>&1
    local ok=$? wns whs
    wns=$(sed -n 's/.*setup: WNS = \([-+0-9.]*\).*/\1/p' "$rep.check"); whs=$(sed -n 's/.*hold: WHS = \([-+0-9.]*\).*/\1/p' "$rep.check")
    local res=PASS; [ $ok -eq 0 ] || res=FAIL
    printf '| %.2f MHz | %d | %s | %s | %s |\n' "$(echo "8000 / $d" | bc -l)" "$d" "${wns:-?}" "${whs:-?}" "$res" >> "$TABLE"
    echo "$res ${wns:-nan} ${whs:-nan}"
}

read -r res wns _ < <(try 160)
echo "50.00 MHz: $res (WNS $wns ns)"
[ "$res" = PASS ] || { echo "ni siquiera 50 MHz cierra: ver $REP/div160.check"; cat "$TABLE"; exit 1; }
best=160
limit=$(echo "1000 / (20 - $wns) * 1.05" | bc -l)
echo "Fmax estimada: $(echo "1000 / (20 - $wns)" | bc -l | xargs printf '%.2f') MHz; se prueba hasta $(printf '%.2f' "$limit") MHz"
fails=0
for d in $(seq 159 -1 80); do
    f=$(echo "8000 / $d" | bc -l)
    [ "$(echo "$f > $limit" | bc)" = 1 ] && break
    read -r res wns _ < <(try "$d")
    printf '%.2f MHz: %s (WNS %s ns)\n' "$f" "$res" "$wns"
    if [ "$res" = PASS ]; then best=$d; fails=0; else fails=$((fails + 1)); [ $fails -ge 2 ] && break; fi
done
echo
cat "$TABLE"
printf '\nFrecuencia máxima que cierra: %.2f MHz (MMCM_MULT = 10, MMCM_DIV_X8 = %d)\n' "$(echo "8000 / $best" | bc -l)" "$best" | tee -a "$TABLE"
