#!/usr/bin/env bash
# Mutantes de los traps: copias del RTL con un error inyectado. Cada una tiene que
# hacer FALLAR el chequeo de riscv-formal indicado (así se comprueba que esos
# chequeos realmente miran las excepciones y el mapa de memoria).
set -u
source "$(dirname "$0")/core.sh"
RTL="$RTL_DIR/pipeline"
MUT="$PROJ/build/formal/rvfi/mutants"; mkdir -p "$MUT"
STATUS=0

# mutant <nombre> <archivo del RTL, relativo a pipeline/> <expr sed> <chequeo>
mutant() {
    local name=$1 file=$2 expr=$3 check=$4
    local out="$MUT/$(basename "${file%.v}")_mut_$name.v"
    sed "$expr" "$RTL/$file" > "$out"
    if cmp -s "$RTL/$file" "$out"; then echo "ERROR: el mutante '$name' no cambió nada"; exit 1; fi
    local cfg="mut_$name"
    make_cfg "$cfg" "$file" "$out"
    gen "$cfg"
    make -C "$CORE/$cfg" "$check/status" > /dev/null 2>&1
    local result
    result=$(cut -d' ' -f1 "$CORE/$cfg/$check/status" 2>/dev/null)
    local mark="ok "
    [ "$result" = FAIL ] || { mark="MAL"; STATUS=1; }
    printf '[%s] %-15s %-14s → %-5s (esperado FAIL)\n' "$mark" "$name" "$check" "${result:-ERROR}"
}

mutant no_dmem_range  flow/trap_unit.v  's/wire mem_fault      = .*/wire mem_fault      = 1'"'"'b0;/' insn_lw_ch0
mutant no_imem_range  riscv_pipeline.v  's/wire       id_fetch_fault = .*/wire       id_fetch_fault = 1'"'"'b0;/' insn_addi_ch0
mutant no_misjump     flow/trap_unit.v  's/wire pc_misaligned  = .*/wire pc_misaligned  = 1'"'"'b0;/' insn_beq_ch0
mutant writes_on_trap riscv_pipeline.v  's/\.ex_reg_write(ex_reg_write & ~ex_exc)/.ex_reg_write(ex_reg_write)/' insn_lw_ch0
mutant no_illegal     2_decode/illegal_check.v 's/default:    illegal = 1'"'"'b1;/default:    illegal = 1'"'"'b0;/' ill_ch0
mutant deadlock       flow/hazard_unit.v "0,/        stall = 1'b0;/s//        stall = (id_rs1 == 5'd1);/" liveness_ch0  # se traba para siempre si ID lee x1
exit $STATUS
