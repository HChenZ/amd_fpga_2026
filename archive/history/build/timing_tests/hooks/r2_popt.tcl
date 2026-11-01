# R2 arm r2_popt: bare phys_opt_design at PHYS_OPT_DESIGN.TCL.POST, no nets,
# no properties.  Isolates "an extra phys_opt pass at that flow point" from any
# replication effect.  Motivation: the R1 sel_* arm created ZERO replicas and
# still moved WNS +0.087 -> +0.184, so something other than replication has to
# explain that number.
source [file join [file dirname [info script]] .. r2_lib.tcl]

foreach nm $::R2_SEL4 {
    set n [r2_net $nm]
    if {$n ne ""} { r2_dump before $n }
}
puts "R2 r2_popt replica_cells_before=[llength [r2_reps]]"

phys_opt_design

puts "R2 r2_popt replica_cells_after=[llength [r2_reps]]"
foreach nm $::R2_SEL4 {
    set n [r2_net $nm]
    if {$n ne ""} { r2_dump after $n }
}
