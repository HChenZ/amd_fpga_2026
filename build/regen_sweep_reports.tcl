# Regenerate sweep reports + summary TSV from existing routed runs only.
# Does NOT re-run any implementation. Read-only wrt runs.
open_project C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/strategy_sweep/riscv_vivado_project.xpr
set report C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/reports/strategy_sweep_20261017
set runs {sweep_default sweep_perf_explore sweep_perf_explore_postroute sweep_perf_extra_timing
  sweep_perf_netdelay_high sweep_perf_netdelay_low sweep_perf_retiming sweep_perf_refine_placement
  sweep_congestion_spread_high sweep_flow_postroute_physopt sweep_perf_explore_remap
  sweep_perf_spread_slls sweep_perf_balance_slls sweep_perf_balance_slrs sweep_perf_highutil_slrs
  sweep_congestion_spread_medium sweep_congestion_spread_low sweep_congestion_ssi_high
  sweep_congestion_ssi_low sweep_area_explore sweep_area_explore_sequential sweep_area_explore_remap
  sweep_power_default sweep_power_explore_area sweep_flow_run_physopt sweep_flow_runtimeopt
  sweep_flow_quick sweep_auto_1 sweep_auto_2 sweep_auto_3 sweep_early_block_placement
  sweep_wl_block_placement sweep_wl_block_fanout}
file mkdir $report
set fp [open [file join $report sweep_summary.tsv] w]
puts $fp "strategy\trun\tduration_s\twns_ns\ttns_ns\tfailing_setup_endpoints\twhs_ns"
set missing {}
foreach run $runs {
    if {![llength [get_runs -quiet $run]]} { lappend missing $run; continue }
    set r [get_runs $run]
    if {[get_property PROGRESS $r] ne "100%"} { lappend missing "$run:progress<100" ; continue }
    set rdir [file join $report $run]
    file mkdir $rdir
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
    set strat [get_property STRATEGY $r]
    puts $fp "$strat\t$run\t0\t[format %.3f $wns]\t[format %.3f $tns]\t$fep\t[format %.3f $whs]"
    flush $fp
    close_design
    puts "REGEN $run wns=[format %.3f $wns] failing=$fep"
}
close $fp
puts "REGEN_MISSING=[join $missing ,]"
close_project
puts "REGEN COMPLETE"
