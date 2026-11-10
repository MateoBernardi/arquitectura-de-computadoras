# ==============================================================================
# Pure Synthesis Layer Verification Script (Vivado Batch Mode)
# Usage: vivado -mode batch -source verify_synth_only.tcl
# ==============================================================================

# --- Configuration ---
set proj_path "../../project_4.xpr"
set wns_sanity_threshold -1.0   ;# Slack límite aceptable post-síntesis (ns)
set expected_bram_min 0         ;# Mínimo de Block RAMs esperadas
set expected_dsp_min  0         ;# Mínimo de DSPs esperados

# 1. Open Project and Run Synthesis
open_project $proj_path
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "FAIL \[SYNTH\]: Synthesis run crashed or failed to complete."
    close_project
    exit 1
}

open_run synth_1

# 2. Structural Check A: Zero Critical Warnings
set crit_warns [get_msg_config -severity "CRITICAL WARNING" -count]
if {$crit_warns > 0} {
    puts "FAIL \[LINT\]: Found $crit_warns Critical Warning(s) during synthesis."
    close_project
    exit 1
}

# 3. Structural Check B: Zero Inferred Latches
set latch_msgs  [get_msgs -quiet -filter {ID == "Synth 8-327"}]
set latch_cells [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ REGISTER.LATCH.* || PRIMITIVE_SUBGROUP == latch}]

if {[llength $latch_msgs] > 0 || [llength $latch_cells] > 0} {
    puts "FAIL \[LATCH\]: Unintended latches inferred in synthesized netlist:"
    foreach cell $latch_cells { puts "   -> Latch cell: $cell" }
    close_project
    exit 1
}

# 4. Structural Check C: Macro Inference (BRAM / DSP)
# Coincide de forma más robusta con familias 7-Series y UltraScale(+)
set bram_cells [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ BMEM.* || PRIMITIVE_TYPE =~ RAMB*.*}]
set dsp_cells  [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ MULT.DSP.* || PRIMITIVE_TYPE =~ DSP*.*}]

set bram_count [llength $bram_cells]
set dsp_count  [llength $dsp_cells]

puts "INFO \[INFERENCE\]: Inferred $bram_count BRAM(s) and $dsp_count DSP(s)."

if {$bram_count < $expected_bram_min || $dsp_count < $expected_dsp_min} {
    puts "FAIL \[INFERENCE\]: Macro inference below minimum (BRAM: $bram_count/$expected_bram_min, DSP: $dsp_count/$expected_dsp_min)."
    close_project
    exit 1
}

# 5. Logic-Depth & Timing Sanity Check
set setup_paths [get_timing_paths -quiet -max_paths 1 -nworst 1 -setup]
if {[llength $setup_paths] > 0} {
    set est_wns [get_property SLACK $setup_paths]
    puts "INFO \[SANITY\]: Post-synthesis estimated WNS = $est_wns ns (Threshold: $wns_sanity_threshold ns)"
    if {$est_wns < $wns_sanity_threshold} {
        puts "FAIL \[SANITY\]: Estimated logic depth is too deep for target clock (WNS: $est_wns ns)."
        close_project
        exit 1
    }
} else {
    puts "WARNING \[SANITY\]: No timing paths found. Check if timing constraints (XDC) are applied."
}

# 6. Functional Equivalence: Post-Synthesis Zero-Delay Simulation
launch_simulation -mode post-synthesis -type functional
# Ejecuta por un tiempo límite para prevenir loops infinitos (ej. 10 ms simulados)
run 10 ms

set sim_dir [get_property DIRECTORY [current_sim]]
set sim_log "$sim_dir/simulate.log"

if {[file exists $sim_log]} {
    set fp [open $sim_log r]
    set log_data [read $fp]
    close $fp

    # Búsqueda estricta de marcadores de fallo definidos en el Testbench
    if {[string match "*TEST_FAILED*" $log_data] || [string match "*Fatal:*" $log_data]} {
        puts "FAIL \[SIM\]: Post-synthesis functional simulation reported errors."
        close_sim -force
        close_project
        exit 1
    }
} else {
    puts "FAIL \[SIM\]: Could not locate simulation log at $sim_log."
    close_sim -force
    close_project
    exit 1
}

# Clean Exit
puts "SUCCESS: Synthesis layer verification passed!"
close_sim -force
close_project
exit 0