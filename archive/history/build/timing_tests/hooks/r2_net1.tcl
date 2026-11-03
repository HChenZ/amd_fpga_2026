# R2 arm r2_net1: replicate exactly ONE net -- id_ex_u/sel_ex_mem_rs1_o (fo=172),
# the source register of the current worst path (R1 -> 13 levels, logic 3.52 ns).
# MAX_FANOUT hint written on the NET (what the R1 hook did) for a direct
# A/B against the 12-alias arm.
source [file join [file dirname [info script]] .. r2_lib.tcl]
set tag r2_net1

set nets {}
foreach nm [lrange $::R2_SEL4 0 0] {
    set n [r2_net $nm]
    if {$n eq ""} { continue }
    r2_dump before $n
    r2_freeze $n
    catch { set_property MAX_FANOUT 128 $n }
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
