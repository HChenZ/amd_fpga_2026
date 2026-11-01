# R2 arm r2_net1_cell: same single net as r2_net1, but MAX_FANOUT 128 is written
# on the DRIVING CELL (the only object type Vivado's replication cost model
# reads it from) instead of on the net.
source [file join [file dirname [info script]] .. r2_lib.tcl]
set tag r2_net1_cell

set nets {}
foreach nm [lrange $::R2_SEL4 0 0] {
    set n [r2_net $nm]
    if {$n eq ""} { continue }
    r2_dump before $n
    r2_freeze $n
    set dc [r2_drv_cell $n]
    foreach c $dc { catch { set_property MAX_FANOUT 128 $c } }
    lappend nets $n
}
puts "R2 $tag replica_cells_before=[llength [r2_reps]] candidates=[llength $nets]"
if {[llength $nets] > 0} {
    if {[catch { phys_opt_design -force_replication_on_nets $nets } err]} {
        puts "R2 $tag repl_error=$err"
    }
}
r2_summary $tag
foreach n $nets { r2_dump after $n }
