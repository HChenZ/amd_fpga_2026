# R2C arm r2_noprop: the same four sel_* nets and the same
# -force_replication_on_nets call as r2_net1/r2_net2/r2_all4_cell, but WITHOUT
# writing any property (no EQUIVALENT_REGISTER_REMOVAL, no MAX_FANOUT).
# Q: is the +0.097 trigger the property write, or the call itself?
source [file join [file dirname [info script]] .. r2_lib.tcl]
set tag r2_noprop

set nets {}
foreach nm $::R2_SEL4 {
    set n [r2_net $nm]
    if {$n eq ""} { continue }
    r2_dump before $n
    lappend nets $n
}
puts "R2 $tag replica_cells_before=[llength [r2_reps]] candidates=[llength $nets] props=none"
if {[llength $nets] > 0} {
    if {[catch { phys_opt_design -force_replication_on_nets $nets } err]} {
        puts "R2 $tag repl_error=$err"
    }
}
r2_summary $tag
foreach n $nets { r2_dump after $n }
