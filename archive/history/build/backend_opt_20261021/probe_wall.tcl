# Timing-wall distribution of one or more routed variants: how many endpoints sit
# below each slack threshold, and which module owns the worst paths.
#   vivado -mode batch -source build/backend_opt_20261021/probe_wall.tcl \
#          -notrace -tclargs "ctl fp3 prod_place"
set root [file normalize [file join [file dirname [info script]] .. ..]]
set variants [split [lindex $argv 0] " "]
if {[llength $variants] == 0} { error "usage: -tclargs \"v1 v2 ...\"" }
set MODS {ascon_ise dcache icache if_stage if_id id_ex ex_stage csr_file ex_mem mem_wb predictor ascon_mmio bus_interconnect}
proc owner {pin} {
    global MODS
    foreach m $MODS { if {[string match "*/[set m]/*" $pin]} { return $m } }
    return other
}
set thr {0.0 0.05 0.1 0.2 0.3 0.5 1.0}
set fp [open [file join $root build reports backend_opt_20261021 wall_distribution.txt] w]
foreach v $variants {
    set dcp [file join $root build local backend_opt_20261021 $v ${v}_routed.dcp]
    if {![file exists $dcp]} { puts "WALL skip $v (no dcp)" ; continue }
    open_checkpoint $dcp
    set paths [get_timing_paths -quiet -max_paths 400000 -nworst 1 -setup -slack_less_than 2.0]
    set n [llength $paths]
    set slacks {}
    foreach p $paths { lappend slacks [get_property SLACK $p] }
    set line "$v n_lt2p0=$n"
    foreach t $thr {
        set c 0
        foreach s $slacks { if {$s < $t} { incr c } }
        append line " lt$t=$c"
    }
    puts "WALL $line"
    puts $fp "WALL $line"
    # owner histogram of the 200 worst paths (endpoint side)
    array unset own ; array set own {}
    set cnt 0
    foreach p $paths {
        if {[incr cnt] > 200} { break }
        set o [owner [get_property ENDPOINT_PIN $p]]
        if {![info exists own($o)]} { set own($o) 0 }
        incr own($o)
    }
    set hs {}
    foreach k [array names own] { lappend hs "$k=$own($k)" }
    puts "WALL $v worst200_endpoint_owners: [join [lsort $hs] { }]"
    puts $fp "WALL $v worst200_endpoint_owners: [join [lsort $hs] { }]"
    # logic/net split of the 10 worst
    set i 0
    foreach p [lrange $paths 0 9] {
        set l "  [format %.3f [get_property SLACK $p]]"
        catch { append l " dp=[format %.3f [get_property DATAPATH_DELAY $p]]"
                append l " logic=[format %.3f [get_property DATAPATH_LOGIC_DELAY $p]]"
                append l " net=[format %.3f [get_property DATAPATH_NET_DELAY $p]]" }
        catch { append l " lv=[get_property LOGIC_LEVELS $p]" }
        append l " [owner [get_property STARTPOINT_PIN $p]] -> [owner [get_property ENDPOINT_PIN $p]]"
        puts "WALL $v top[incr i]$l"
        puts $fp "WALL $v top$i$l"
    }
    close_design
}
close $fp
puts "WALL DONE"
