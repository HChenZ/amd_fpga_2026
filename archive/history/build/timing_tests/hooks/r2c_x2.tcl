# R2C arm r2_x2: identical to r2_net1_cell (properties + forced replication on one
# sel_* net) but the force call is issued TWICE in a row.  The 2025.2 help text
# says nets can be replicated repeatedly by successive commands, so if the
# +0.097 were a replication-side effect it should stack; if the result stays at
# +0.184 the effect is a one-shot refresh of the post-place state.
source [file join [file dirname [info script]] .. r2_lib.tcl]
set tag r2_x2

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
foreach i {1 2} {
    if {[catch { phys_opt_design -force_replication_on_nets $nets } err]} {
        puts "R2 $tag repl_error_pass$i=$err"
    }
    puts "R2 $tag after_pass$i replica_cells=[llength [r2_reps]]"
}
r2_summary $tag
foreach n $nets { r2_dump after $n }
