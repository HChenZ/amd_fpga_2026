# Pre-flight for the R2 wave: (a) brace/quote balance of every hook,
# (b) actually source one hook on a routed checkpoint to prove the net names
# resolve and phys_opt accepts the call.  Writes nothing.
set root [file normalize [file join [file dirname [info script]] ../..]]
set hooks [glob -nocomplain [file join $root build timing_tests hooks r2_*.tcl]]
puts "PREFLIGHT hooks=[llength $hooks]"
foreach h $hooks {
    set fh [open $h r]; set txt [read $fh]; close $fh
    puts [format "  %-24s complete=%d chars=%d ascii=%d" [file tail $h] [info complete $txt] [string length $txt] [string is ascii $txt]]
}
set dcp [file join $root build local tests_20261024 pr_rep2_sel pr_rep2_sel_routed.dcp]
if {![file exists $dcp]} { error "missing $dcp" }
open_checkpoint $dcp
set test [file join $root build timing_tests hooks r2_net1_aggr.tcl]
puts "PREFLIGHT source $test"
if {[catch { source $test } err]} { puts "PREFLIGHT ERROR: $err" }
set n [get_nets -quiet -hier -filter "NAME == \"u_soc_axi_top/u_soc_top/u_cpu_core/id_ex_u/sel_ex_mem_rs1_o\""]
puts "PREFLIGHT sel_rs1 fo=[get_property FLAT_PIN_COUNT $n]"
set c [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ "*_rep*"}]
puts "PREFLIGHT replica_cells=[llength $c]"
close_project
puts "PREFLIGHT DONE"
