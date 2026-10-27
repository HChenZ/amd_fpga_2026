# R2C arm r2_tiny: -force_replication_on_nets on ONE trivial net (flat pin count
# == 3, FF driven) that cannot possibly benefit from replication, with no
# properties.  Q: does the net selection matter at all, or is any single call a
# no-op that nevertheless changes the downstream route result?
source [file join [file dirname [info script]] .. r2_lib.tcl]
set tag r2_tiny

set pick ""
foreach n [get_nets -quiet -hier -filter "FLAT_PIN_COUNT == 3"] {
    set dc [r2_drv_cell $n]
    if {$dc eq ""} { continue }
    if {![string match "FD*" [get_property REF_NAME $dc]]} { continue }
    set pick $n
    break
}
if {$pick eq ""} {
    puts "R2 $tag WARN no fo=3 FF-driven net found"
} else {
    r2_dump before $pick
    puts "R2 $tag replica_cells_before=[llength [r2_reps]] candidates=1 props=none"
    if {[catch { phys_opt_design -force_replication_on_nets [list $pick] } err]} {
        puts "R2 $tag repl_error=$err"
    }
    r2_summary $tag
    r2_dump after $pick
}
