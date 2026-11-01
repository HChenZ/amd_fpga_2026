# Strategy sweep: identical RTL/constraints/synthesis, ten implementation
# strategies, one shared synth_1. Isolated copy of the recovered baseline;
# the original board project is never opened or modified.
# Implementation runs are launched in PARALLEL WAVES (batch_size=3 by default,
# -jobs N per run) to use the machine's cores. Reports are written per strategy
# afterwards. Post-route physical optimization strategies get a second wave.
#   vivado -mode batch -source build/sweep_strategy_timing.tcl -notrace \
#     -log build/local/strategy_sweep_log/vivado_sweep.log \
#     -journal build/local/strategy_sweep_log/vivado_sweep.jou -tclargs jobs=6
# Resume after a partial run:
#   ... same command ... -tclargs resume jobs=6
set root [file normalize [file join [file dirname [info script]] ..]]
set work [file join $root build local strategy_sweep]
set report [file join $root build reports strategy_sweep_20261017]
set resume [expr {$argc > 0 && [lindex $argv 0] eq "resume"}]
# Vivado -tclargs splits on whitespace AND '=': use "jobs 6 extra file" (positional).
set jobs 6
set extra_file ""
for {set i 0} {$i < $argc} {incr i} {
    set a [lindex $argv $i]
    if {$a eq "jobs" && [expr {$i+1}] < $argc} {
        set j [lindex $argv [expr {$i+1}]]
        if {[regexp {^[0-9]+$} $j]} { set jobs $j }
    }
    if {$a eq "extra" && [expr {$i+1}] < $argc} { set extra_file [lindex $argv [expr {$i+1}]] }
}
set batch_size 3
if {![string match "2025.2*" [version -short]]} {error "Requires Vivado 2025.2; no automatic upgrade"}
if {[file exists $work] && !$resume} {error "Refusing to overwrite existing build: $work"}
if {!$resume && [file exists $report] && [llength [glob -nocomplain -directory $report *]] > 0} {
    error "Refusing to overwrite existing reports: $report"
}
file mkdir $report

set strategies [list \
  sweep_default                    "Vivado Implementation Defaults" \
  sweep_perf_explore               "Performance_Explore" \
  sweep_perf_explore_postroute     "Performance_ExplorePostRoutePhysOpt" \
  sweep_perf_extra_timing          "Performance_ExtraTimingOpt" \
  sweep_perf_netdelay_high         "Performance_NetDelay_high" \
  sweep_perf_netdelay_low          "Performance_NetDelay_low" \
  sweep_perf_retiming              "Performance_Retiming" \
  sweep_perf_refine_placement      "Performance_RefinePlacement" \
  sweep_congestion_spread_high     "Congestion_SpreadLogic_high" \
  sweep_flow_postroute_physopt     "Flow_RunPostRoutePhysOpt" \
]
# Optional additional strategies: -tclargs extra <file>, one "run<TAB>strategy[<TAB>flow]" per line.
if {$extra_file ne ""} {
    set fh [open $extra_file r]
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq ""} { continue }
        set parts [split $line "\t"]
        if {[llength $parts] >= 2} {
            lappend strategies [lindex $parts 0] [lindex $parts 1]
            if {[llength $parts] >= 3} { set flow_override([lindex $parts 0]) [lindex $parts 2] }
        }
    }
    close $fh
}

proc append_summary {fp run strategy dur wns tns fep whs} {
    puts $fp "$strategy\t$run\t$dur\t[format %.3f $wns]\t[format %.3f $tns]\t$fep\t[format %.3f $whs]"
    flush $fp
}

if {$resume} {
    if {![file exists [file join $work riscv_vivado_project.xpr]]} {error "Resume requires the isolated project"}
    cd $work
    open_project [file join $work riscv_vivado_project.xpr]
} else {
    file mkdir [file dirname $work]
    file copy [file join $root board vivado_zynq7000_xc7z020_baseline] $work
    file copy [file join $root src rtl] [file join $work development_rtl]
    cd $work
    set rtl [file join $work development_rtl]
    open_project [file join $work riscv_vivado_project.xpr]
    if {[get_property PART [current_project]] ne "xc7z020clg400-1"} { error "Unexpected part" }
    # Keep recovered XCI, COE, XDC; replace ONLY the copied imports source set.
    set old [get_files -of_objects [get_filesets sources_1] -filter {FILE_TYPE == Verilog || FILE_TYPE == "Verilog Header"}]
    remove_files $old
    set sources [concat [glob [file join $rtl *.v]] [glob -nocomplain [file join $rtl *.vh]]]
    foreach f [glob [file join $rtl ascon *]] {
        if {([file extension $f] eq ".v" || [file extension $f] eq ".vh") && ![string match "*_tb.v" $f]} { lappend sources $f }
    }
    add_files -norecurse $sources
    foreach f $sources {
        if {[file extension $f] eq ".v"} {set_property file_type SystemVerilog [get_files $f]}
    }
    set_property include_dirs [list $rtl [file join $rtl ascon]] [get_filesets sources_1]
    set_property top top_pl_bram [get_filesets sources_1]
    update_compile_order -fileset sources_1
    set fp [open [file join $report build_context.txt] w]
    puts $fp "[version]\npart=[get_property PART [current_project]]\ntop=top_pl_bram\nboard=unknown\nhost=[exec hostname]\ndate=[clock format [clock seconds]]\nsource_head=[exec git -C $root rev-parse HEAD]"
    puts $fp "source files: [get_files -compile_order sources -used_in synthesis]"
    puts $fp "constraints: [get_files -of_objects [get_filesets constrs_1]]"
    foreach ip [get_ips] {
        puts $fp "IP $ip [get_property IPDEF $ip] locked=[get_property IS_LOCKED $ip]"
        if {[get_property IS_LOCKED $ip]} {close $fp;error "Locked IP: $ip; upgrade not authorized by this script"}
    }
    close $fp
    report_ip_status -file [file join $report ip_status.rpt]
    generate_target all [get_ips]
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"}
    open_run synth_1
    report_utilization -file [file join $report synth_utilization.rpt]
    report_timing_summary -file [file join $report synth_timing.rpt]
    close_design
}
if {[get_property PART [current_project]] ne "xc7z020clg400-1"} {error "Unexpected part"}
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Completed synthesis required"}

# Load already-finished runs from the summary TSV (resume bookkeeping).
set tsv [file join $report sweep_summary.tsv]
set tsv_done {}
if {[file exists $tsv]} {
    set fh [open $tsv r]
    while {[gets $fh line] >= 0} {
        set parts [split $line "\t"]
        if {[llength $parts] >= 2 && [string match "sweep_*" [lindex $parts 1]]} { lappend tsv_done [lindex $parts 1] }
    }
    close $fh
}
set summary_fp [open $tsv a]
if {!$resume} {
    puts $summary_fp "strategy\trun\tduration_s\twns_ns\ttns_ns\tfailing_setup_endpoints\twhs_ns"
    flush $summary_fp
}

# ---- create runs for every pending strategy ----
set pending {}
foreach {run strategy} $strategies {
    set rdir [file join $report $run]
    set done_rpt [file join $rdir route_timing.rpt]
    set done [expr {[lsearch $tsv_done $run] >= 0}]
    if {$done} {
        if {![file exists $done_rpt]} {error "Summary says $run done but reports are missing"}
        puts "SKIP $run ($strategy): already finished"
        continue
    }
    if {[file exists $done_rpt]} {error "Reports exist for $run but no summary row; inconsistent state"}
    file mkdir $rdir
    if {![llength [get_runs -quiet $run]]} {
        set fl {Vivado Implementation 2025}
        if {[info exists flow_override($run)]} { set fl $flow_override($run) }
        create_run $run -parent_run synth_1 -flow $fl -strategy $strategy -constrset constrs_1 -part xc7z020clg400-1
    }
    set r [get_runs $run]
    set props_fp [open [file join $rdir strategy_props.txt] w]
    puts $props_fp "strategy=$strategy\nrun=$run\nflow=[get_property FLOW $r]"
    foreach prop [list_property $r] {
        if {[string match "STEPS.*" $prop]} { puts $props_fp "$prop=[get_property $prop $r]" }
    }
    close $props_fp
    lappend pending $run
}

# ---- run all pending runs in parallel waves, grouped by final flow step ----
# Runs whose strategy ends at route_design go in waves of batch_size; runs whose
# strategy includes phys_opt_design (Post-Route) are launched directly to that
# FINAL step (single wave), so the run's launch context always matches its
# strategy's full flow and PROGRESS reaches 100% cleanly. Resume-friendly.
proc launch_wave {wave to_step jobs} {
    set t_wave [clock seconds]
    puts "WAVE [join $wave ,] to_step=$to_step jobs=$jobs"
    if {[catch {launch_runs {*}$wave -to_step $to_step -jobs $jobs} err]} {
        puts "launch_runs failed ($err); resetting runs and retrying once"
        if {[catch {foreach r $wave { reset_runs $r }} err2]} {error "reset_runs failed: $err2"}
        launch_runs {*}$wave -to_step $to_step -jobs $jobs
    }
    foreach r $wave {
        set ::t_start($r) $t_wave
        wait_on_run $r
        if {[get_property PROGRESS [get_runs $r]] ne "100%"} {error "Implementation failed: $r status [get_property STATUS [get_runs $r]]"}
        set ::dur($r) [expr {[clock seconds] - $::t_start($r)}]
        puts "DONE-RUN $r dur=$::dur($r)s"
    }
}

set route_runs {}
set pr_runs {}
foreach run $pending {
    if {[get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED [get_runs $run]]} {
        lappend pr_runs $run
    } else {
        lappend route_runs $run
    }
}
set wave {}
foreach run $route_runs {
    lappend wave $run
    if {[llength $wave] >= $batch_size} {
        launch_wave $wave route_design $jobs
        set wave {}
    }
}
if {[llength $wave] > 0} { launch_wave $wave route_design $jobs }
if {[llength $pr_runs] > 0} { launch_wave $pr_runs {phys_opt_design (Post-Route)} $jobs }

# ---- report + summary for every pending strategy ----
foreach {run strategy} $strategies {
    if {[lsearch $tsv_done $run] >= 0} { continue }
    set rdir [file join $report $run]
    open_run $run
    report_utilization -file [file join $rdir route_utilization.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained -file [file join $rdir route_timing.rpt]
    report_timing -delay_type max -max_paths 20 -file [file join $rdir route_paths.rpt]
    report_clock_interaction -file [file join $rdir clock_interaction.rpt]
    check_timing -verbose -file [file join $rdir check_timing.rpt]
    report_route_status -file [file join $rdir route_status.rpt]
    report_drc -file [file join $rdir route_drc.rpt]
    report_methodology -file [file join $rdir methodology.rpt]
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
    set fpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
    set fep [llength $fpaths]
    set tns 0.0
    foreach p $fpaths { set tns [expr {$tns + [get_property SLACK $p]}] }
    append_summary $summary_fp $run $strategy $dur($run) $wns $tns $fep $whs
    write_checkpoint [file join $work $run.dcp]
    close_design
    puts "DONE $run ($strategy) dur=$dur($run)s wns=[format %.3f $wns] tns=[format %.3f $tns] failing=$fep whs=[format %.3f $whs]"
}
close $summary_fp
close_project
puts "SWEEP COMPLETE"
