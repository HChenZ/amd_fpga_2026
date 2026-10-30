# Timing closure attempts on the same synthesized netlist of build/local/pynq_puf3/vivado.
# Only implementation strategies differ (plus post-route phys_opt); no XDC/clock/exception change.
#   vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf3/explore_impl.tcl -tclargs <first_run_index> <strategy>...
# Results are appended to build/local/pynq_puf3/vivado/reports/explore_impl.txt.
set root  [file normalize [file join [file dirname [info script]] ../..]]
set board [file join $root board vivado_zynq7000_xc7z020_pynq_puf3]
set work  [file join $root build local pynq_puf3 vivado]
open_project [file join $work pynq_puf3.xpr]
set i [lindex $argv 0]
set strategies [lrange $argv 1 end]
if {![llength $strategies]} {error "usage: -tclargs <first_run_index> <strategy>..."}
set runs {}
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
set fp [open [file join $work reports explore_impl.txt] a]
# open_checkpoint closes the project, so read every run's strategy first.
foreach r $runs {set strat($r) [get_property STRATEGY [get_runs $r]]; set stat($r) [get_property STATUS [get_runs $r]]}
foreach r $runs {
    set dcp [file join $work pynq_puf3.runs $r pynq_puf3_wrapper_postroute_physopt.dcp]
    if {![file exists $dcp]} {puts $fp "$r $strat($r) no post-route checkpoint ($stat($r))"; continue}
    open_checkpoint $dcp
    set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    puts $fp "$r $strat($r) post-route-physopt wns=$wns whs=$whs"
    puts "EXPLORE $r $strat($r) wns=$wns whs=$whs"
    close_design
}
close $fp
