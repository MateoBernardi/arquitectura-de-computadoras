# ==============================================================================
# Pure Implementation Layer Verification Script (Vivado Batch Mode)
# Prerequisites: synth_1 must already be completed and verified.
# Usage: vivado -mode batch -source verify_impl_only.tcl
# ==============================================================================

# --- Configuration ---
set proj_path "../../project_4.xpr"
set run_timing_sim 1         ;# Set to 0 to skip slow SDF timing sim on routine runs
set generate_bitstream 1     ;# Set to 1 to emit .bit file only after all checks pass

# 1. Open Project and Verify Synthesis Prerequisite
open_project $proj_path

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "FAIL \[PREREQ\]: synth_1 is not complete. Run verify_synth_only.tcl first."
    close_project
    exit 1
}

# 2. Reset and Run Implementation
reset_run impl_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "FAIL \[IMPL\]: Implementation run crashed or failed to complete."
    close_project
    exit 1
}

open_run impl_1

# 3. Physical Check A: Routing Completeness
set route_status [report_route_status -return_string]
if {![string match "*Errors: 0*" $route_status] || [string match "*Unrouted Nets: \[1-9\]*" $route_status]} {
    puts "FAIL \[ROUTE\]: Design has unrouted nets or routing errors."
    puts $route_status
    close_project
    exit 1
}

# 4. Physical Check B: Strict Timing Closure (Setup, Hold, Pulse Width)
set setup_paths [get_timing_paths -quiet -max_paths 1 -nworst 1 -setup]
set hold_paths  [get_timing_paths -quiet -max_paths 1 -nworst 1 -hold]
set pw_paths    [get_timing_paths -quiet -max_paths 1 -nworst 1 -pulse_width]

if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {
    puts "FAIL \[TIMING\]: No constrained timing paths found. Check your XDC clock constraints!"
    close_project
    exit 1
}

set wns  [get_property SLACK $setup_paths]
set whs  [get_property SLACK $hold_paths]
set wpws [if {[llength $pw_paths] > 0} { get_property SLACK $pw_paths } else { list 0.0 }]

puts "INFO \[TIMING\]: Post-Route WNS = $wns ns | WHS = $whs ns | WPWS = $wpws ns"

if {$wns < 0.0 || $whs < 0.0 || $wpws < 0.0} {
    puts "FAIL \[TIMING\]: Physical timing closure failed (WNS: $wns, WHS: $whs, WPWS: $wpws)."
    report_timing_summary -file ./impl_timing_failure.rpt
    close_project
    exit 1
}

# 5. Physical Check C: DRC & Pin Assignment Checks
set drc_errors [report_drc -return_string -ruledecks {default}]
if {[string match "*ERROR*" $drc_errors] || [string match "*CRITICAL WARNING*" $drc_errors]} {
    puts "FAIL \[DRC\]: Physical/Electrical DRC rules failed or critical pin assignment warnings found."
    report_drc -file ./impl_drc_failure.rpt
    close_project
    exit 1
}

# 6. Dynamic Check: Post-Implementation Timing Simulation (SDF)
if {$run_timing_sim == 1} {
    puts "INFO \[SIM\]: Launching Post-Implementation Timing Simulation..."
    launch_simulation -mode post-implementation -type timing
    
    # Se impone un acotamiento temporal razonable en lugar de 'run all'
    run 10 ms

    set sim_dir [get_property DIRECTORY [current_sim]]
    set sim_log "$sim_dir/simulate.log"

    if {[file exists $sim_log]} {
        set fp [open $sim_log r]
        set log_data [read $fp]
        close $fp

        # Búsqueda de banderas explícitas de error en el testbench o violaciones SDF ($setuphold)
        if {[string match "*TEST_FAILED*" $log_data] || [string match "*$setuphold*" $log_data] || [string match "*$hold*" $log_data]} {
            puts "FAIL \[SIM\]: Post-implementation timing simulation failed or reported SDF timing violations."
            close_sim -force
            close_project
            exit 1
        }
    } else {
        puts "FAIL \[SIM\]: Could not locate timing simulation log at $sim_log."
        close_sim -force
        close_project
        exit 1
    }
    close_sim -force
}

# 7. Final Output: Generate Bitstream
if {$generate_bitstream == 1} {
    puts "INFO \[BIT\]: Generating verified bitstream..."
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
        puts "FAIL \[BIT\]: Bitstream generation failed."
        close_project
        exit 1
    }
}

puts "SUCCESS: Implementation layer verification passed!"
close_project
exit 0