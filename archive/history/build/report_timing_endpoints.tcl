# Report actual failing endpoints; do not infer counts from the top-20 report.
proc export_timing_endpoints {dir label} {
    file mkdir $dir
    set paths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
    set counts [dict create ise_private 0 multiplier 0 dcache 0 other 0]
    set tns 0.0
    set fp [open [file join $dir failing_endpoints.csv] w]
    puts $fp "class,slack_ns,startpoint,endpoint"
    foreach p $paths {
        set slack [get_property SLACK $p]
        set end [get_property ENDPOINT_PIN $p]
        set start [get_property STARTPOINT_PIN $p]
        set class other
        if {[string match "*u_ascon_ise/u_p*/*" $end]} {set class ise_private
        } elseif {[string match "*u_multiplier/*" $end]} {set class multiplier
        } elseif {[string match "*u_dcache/*" $end]} {set class dcache}
        dict incr counts $class
        set tns [expr {$tns+$slack}]
        puts $fp "$class,$slack,$start,$end"
    }
    close $fp
    set wns [get_property SLACK [get_timing_paths -quiet -max_paths 1 -nworst 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -quiet -max_paths 1 -nworst 1 -hold]]
    set summary "RESULT strategy=$label wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $paths] whs=[format %.3f $whs] classes=$counts"
    puts $summary
    set fp [open [file join $dir result.txt] w];puts $fp $summary;close $fp
}
