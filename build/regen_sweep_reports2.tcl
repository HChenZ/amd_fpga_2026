# Regenerate reports for the original 10 runs from their routed DCPs.
# open_checkpoint (read-only, no project run needed).
set report C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/reports/strategy_sweep_20261017
set work C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/strategy_sweep
set runs {sweep_default sweep_perf_explore sweep_perf_explore_postroute sweep_perf_extra_timing
  sweep_perf_netdelay_high sweep_perf_netdelay_low sweep_perf_retiming sweep_perf_refine_placement
  sweep_congestion_spread_high sweep_flow_postroute_physopt}
set stratmap(sweep_default) "Vivado Implementation Defaults"
set stratmap(sweep_perf_explore) "Performance_Explore"
set stratmap(sweep_perf_explore_postroute) "Performance_ExplorePostRoutePhysOpt"
set stratmap(sweep_perf_extra_timing) "Performance_ExtraTimingOpt"
set stratmap(sweep_perf_netdelay_high) "Performance_NetDelay_high"
set stratmap(sweep_perf_netdelay_low) "Performance_NetDelay_low"
set stratmap(sweep_perf_retiming) "Performance_Retiming"
set stratmap(sweep_perf_refine_placement) "Performance_RefinePlacement"
set stratmap(sweep_congestion_spread_high) "Congestion_SpreadLogic_high"
set stratmap(sweep_flow_postroute_physopt) "Flow_RunPostRoutePhysOpt"
set fp [open [file join $report sweep_summary.tsv] a]
foreach run $runs {
    set dcp [file join $work $run.dcp]
    if {![file exists $dcp]} { puts "NO_DCP $run"; continue }
    set rdir [file join $report $run]
    file mkdir $rdir
    open_checkpoint $dcp
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
    puts $fp "$stratmap($run)\t$run\t0\t[format %.3f $wns]\t[format %.3f $tns]\t$fep\t[format %.3f $whs]"
    flush $fp
    close_design
    puts "DCPREGEN $run wns=[format %.3f $wns] failing=$fep"
}
close $fp
puts "DCP REGEN COMPLETE"
