# Timing-wall characterisation: how many endpoints sit just under/over the 10 ns wall?
# Read-only on the accepted routed snapshot.
set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_routed.dcp]
foreach thr {0.0 0.05 0.1 0.2 0.3 0.5 1.0 2.0} {
    set n [llength [get_timing_paths -quiet -max_paths 200000 -nworst 1 -setup -slack_less_than $thr]]
    puts "WALL slack<$thr ns : $n endpoints"
}
puts "--- worst 25 path endpoints ---"
set i 0
foreach p [get_timing_paths -max_paths 25 -nworst 1 -setup] {
    incr i
    puts [format "%2d slack=%7.3f %s -> %s" $i [get_property SLACK $p] \
        [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
}
puts "WALL PROBE DONE"
