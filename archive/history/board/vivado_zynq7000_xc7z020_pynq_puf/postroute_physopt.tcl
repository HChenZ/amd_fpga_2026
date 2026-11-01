# Post-route physical optimization of impl_1 (Performance_ExploreWithRemap) result.
# Real netlist/routing changes only; clocks and constraints untouched.
set root [file normalize [file join [file dirname [info script]] ../..]]
set work [file join $root build local pynq_puf vivado]
set out  [file join $work physopt]
file mkdir $out
open_checkpoint [file join $work pynq_puf.runs impl_1 pynq_puf_wrapper_postroute_physopt.dcp]
set fp [open [file join $out physopt.txt] w]
puts $fp "start wns=[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]"
foreach d {AggressiveExplore AlternateFlowWithRetiming AggressiveFanoutOpt} {
    phys_opt_design -directive $d
    set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    puts $fp "after $d wns=$wns whs=[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
    flush $fp
    if {$wns >= 0} break
}
route_design -directive Explore
puts $fp "after route_design Explore wns=[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] whs=[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
close $fp
write_checkpoint -force [file join $out physopt.dcp]
report_timing_summary -delay_type min_max -max_paths 10 -file [file join $out timing_summary.rpt]
