# Dump near-critical setup paths to CSV for offline classification.
set root [file normalize [file join [file dirname [info script]] ..]]
set out  [file join $root build local margin_20261020 paths_lt_2p0.csv]
open_checkpoint [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_routed.dcp]

set fp [open $out w]
puts $fp "slack,start_pin,end_pin"
set n 0
foreach p [get_timing_paths -quiet -max_paths 400000 -nworst 1 -setup -slack_less_than 2.0] {
    puts $fp "[get_property SLACK $p],[get_property STARTPOINT_PIN $p],[get_property ENDPOINT_PIN $p]"
    incr n
}
close $fp
puts "DUMPED $n paths -> $out"
puts "CLASSIFY DUMP DONE"
