# Timing closure attempts on the same synthesized netlist, same clocks/constraints.
# Only implementation strategies differ; no XDC, clock or exception change.
#   vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf/explore_impl.tcl
set root  [file normalize [file join [file dirname [info script]] ../..]]
set board [file join $root board vivado_zynq7000_xc7z020_pynq_puf]
set work  [file join $root build local pynq_puf vivado]
open_project [file join $work pynq_puf.xpr]
set strategies {Performance_Explore Performance_NetDelay_high Performance_ExtraTimingOpt Performance_RefinePlacement}
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
launch_runs $runs -to_step route_design -jobs 4
foreach r $runs {wait_on_run $r}
set fp [open [file join $work reports explore_impl.txt] w]
foreach r $runs {
    if {[get_property PROGRESS [get_runs $r]] ne "100%"} {puts $fp "$r [get_property STRATEGY [get_runs $r]] FAILED [get_property STATUS [get_runs $r]]"; continue}
    open_run $r -name $r
    set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    puts $fp "$r [get_property STRATEGY [get_runs $r]] wns=$wns whs=$whs"
    puts "EXPLORE $r [get_property STRATEGY [get_runs $r]] wns=$wns whs=$whs"
    close_design
}
close $fp
