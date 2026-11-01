# R2 arm r2_net2: replicate TWO nets (sel_ex_mem_rs1_o fo=172 + sel_ex_mem_rs2_o
# fo=141) -- the "1~2 nets" variant the R1 page asks for, without touching the
# mem_wb pair.
source [file join [file dirname [info script]] .. r2_lib.tcl]
set tag r2_net2

set nets {}
foreach nm [lrange $::R2_SEL4 0 1] {
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
