# R2C arm r2_tight: give the extra post-place phys_opt_design a REAL timing
# pressure.  The strategy's own phys_opt is a no-op here because the estimated
# post-place WNS is +0.247 ("All physical synthesis setup optimizations will be
# skipped"), so nothing that needs violating paths ever fires.  This arm
# temporarily tightens the input clock 20.0 -> 18.0 ns (core 10.0 -> 9.0 ns),
# runs one AggressiveExplore pass, then restores 20.0 ns before route_design.
# No replication, no properties: pure "phys_opt under pressure".
#
# The final numbers are therefore measured at the real 10 ns constraint.
source [file join [file dirname [info script]] .. r2_lib.tcl]
set tag r2_tight

set clk [get_clocks -quiet clk]
if {$clk eq ""} { error "clock clk not found" }
set p0 [get_property PERIOD $clk]
puts "R2 $tag period_before=$p0"
foreach nm $::R2_SEL4 {
    set n [r2_net $nm]
    if {$n ne ""} { r2_dump before $n }
}
puts "R2 $tag replica_cells_before=[llength [r2_reps]]"

# PERIOD is a read-only property on a create_clock clock (ERROR: [Common 17-107]),
# so over-constrain by re-issuing create_clock with the same name, then restore.
create_clock -period 18.000 -name clk [get_ports clk]
puts "R2 $tag tight_period=[get_property PERIOD [get_clocks clk]] core=[get_property PERIOD [get_clocks -quiet clk_out1_clk_wiz_0]] est_wns=[get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"
if {[catch { phys_opt_design -directive AggressiveExplore } err]} {
    puts "R2 $tag physopt_error=$err"
}

create_clock -period $p0 -name clk [get_ports clk]
puts "R2 $tag period_restored=[get_property PERIOD [get_clocks clk]] core=[get_property PERIOD [get_clocks -quiet clk_out1_clk_wiz_0]] est_wns=[get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"
r2_summary $tag
foreach nm $::R2_SEL4 {
    set n [r2_net $nm]
    if {$n ne ""} { r2_dump after $n }
}
