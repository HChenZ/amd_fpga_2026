# Dump the worst setup path of two implementations for comparison (control vs e2).
set root [file normalize [file join [file dirname [info script]] ..]]
foreach tag {control e2} {
    set dcp [file join $root build local bce_timing_$tag bce_routed.dcp]
    if {![file exists $dcp]} { puts "MISSING $dcp"; continue }
    open_checkpoint $dcp
    set p [get_timing_paths -max_paths 1 -nworst 1 -setup]
    puts "SLACK_${tag} [get_property SLACK $p]"
    puts "FROM_${tag} [get_property STARTPOINT_PIN $p]"
    puts "TO_${tag} [get_property ENDPOINT_PIN $p]"
    report_timing -max_paths 1 -nworst 1 -delay_type max -path_type full \
        -file [file join $root build local margin_20261020 path_$tag.rpt]
    close_design
}
puts "PATH COMPARE DONE"
