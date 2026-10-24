# Classify near-critical setup paths for the 2026-10-24 next.html route tests.
#   vivado -mode batch -source build/local/tests_20261024/probe_classes.tcl -notrace \
#          -tclargs <routed.dcp> <out.csv>
set root [file normalize [file join [file dirname [info script]] ../..]]
set dcp [lindex $argv 0]
set out [lindex $argv 1]
if {$dcp eq "" || $out eq ""} { error "usage: -tclargs <dcp> <out.csv>" }
open_checkpoint $dcp
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
