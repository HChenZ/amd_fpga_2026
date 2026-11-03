# R2 arm r2_net4_cell: all FOUR sel_* nets, but as 4 parent net objects (the R1
# arm passed 12 aliases of the same 4 nets) and with MAX_FANOUT on the driving
# CELL.  Direct test of "aliases + wrong property object" as the reason the R1
# arm produced 0 replicas.
source [file join [file dirname [info script]] .. r2_lib.tcl]
set tag r2_net4_cell

set nets {}
foreach nm $::R2_SEL4 {
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
