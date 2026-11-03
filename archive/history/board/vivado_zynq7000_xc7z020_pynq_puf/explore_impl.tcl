# Timing closure attempts on the same synthesized netlist, same clocks/constraints.
# Only implementation strategies differ; no XDC, clock or exception change.
#   vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf/explore_impl.tcl
set root  [file normalize [file join [file dirname [info script]] ../..]]
set board [file join $root board vivado_zynq7000_xc7z020_pynq_puf]
set work  [file join $root build local pynq_puf vivado]
open_project [file join $work pynq_puf.xpr]
set strategies {Performance_Explore Performance_ExtraTimingOpt Performance_ExploreWithRemap Performance_SpreadSLLs}
if {[info exists ::explore_strategies]} {set strategies $::explore_strategies}
set runs {}
set i 2
foreach s $strategies {
    set r impl_$i
    if {[llength [get_runs -quiet $r]]} {error "run $r already exists"}
    create_run $r -parent_run synth_1 -flow {Vivado Implementation 2025} -strategy $s
    set_property STEPS.OPT_DESIGN.TCL.PRE [file join $board puf_opt_pre.tcl] [get_runs $r]
    set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $r]
    lappend runs $r
    incr i
}
launch_runs $runs -to_step {phys_opt_design (Post-Route)} -jobs 4
foreach r $runs {wait_on_run $r}
set fp [open [file join $work reports explore_impl_runs.txt] a]
foreach r $runs {
    set dcp [file join $work pynq_puf.runs $r pynq_puf_wrapper_postroute_physopt.dcp]
    if {![file exists $dcp]} {puts $fp "$r [get_property STRATEGY [get_runs $r]] no post-route checkpoint ([get_property STATUS [get_runs $r]])"; continue}
    open_checkpoint $dcp
    set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    puts $fp "$r [get_property STRATEGY [get_runs $r]] post-route-physopt wns=$wns whs=$whs"
    puts "EXPLORE $r [get_property STRATEGY [get_runs $r]] wns=$wns whs=$whs"
    close_design
}
close $fp
