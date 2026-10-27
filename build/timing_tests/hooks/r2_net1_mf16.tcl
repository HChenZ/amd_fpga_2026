# R2 arm r2_net1_mf16: one net, cell MAX_FANOUT 16 (172 loads -> ~11 copies
# asked for), AggressiveExplore + forced replication.  Tells us whether the
# refusal in R1 was "fanout hint too weak to be worth it" (128 leaves ~1 copy)
# or a hard "loads are already local" verdict.
source [file join [file dirname [info script]] .. r2_lib.tcl]
set tag r2_net1_mf16

set nets {}
foreach nm [lrange $::R2_SEL4 0 0] {
    set n [r2_net $nm]
    if {$n eq ""} { continue }
    r2_dump before $n
    r2_freeze $n
    set dc [r2_drv_cell $n]
    foreach c $dc { catch { set_property MAX_FANOUT 16 $c } }
    lappend nets $n
}
puts "R2 $tag replica_cells_before=[llength [r2_reps]] candidates=[llength $nets]"
if {[llength $nets] > 0} {
    if {[catch { phys_opt_design -directive AggressiveExplore } err]} {
        puts "R2 $tag physopt_error=$err"
    }
    puts "R2 $tag replica_cells_after_aggr=[llength [r2_reps]]"
    if {[catch { phys_opt_design -force_replication_on_nets $nets } err]} {
        puts "R2 $tag repl_error=$err"
    }
}
r2_summary $tag
foreach n $nets { r2_dump after $n }
