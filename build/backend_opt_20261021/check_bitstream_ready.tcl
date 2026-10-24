# Bitstream-readiness check of the champion netlist WITHOUT writing a .bit:
# DRC (bitstream-relevant checks), IO/clock inventory, and the unconstrained-IO list.
# Nothing is programmed and no bitstream file is produced, so this is safe to run
# before the board model / clock pin is confirmed.
#   vivado -mode batch -source build/backend_opt_20261021/check_bitstream_ready.tcl -notrace
set root [file normalize [file join [file dirname [info script]] .. ..]]
set var  "pl_ndh_crit200_ntr"
set dcp  [file join $root build local backend_opt_20261021 $var ${var}_routed.dcp]
set out  [file join $root build reports backend_opt_20261021 $var]
if {![file exists $dcp]} { error "missing $dcp" }
open_checkpoint $dcp

report_drc -file [file join $out drc_bitstream.rpt]
report_io -file [file join $out io_report.rpt]
report_clock_utilization -file [file join $out clock_utilization.rpt]

# how many ports carry a package pin, and which do not
set ports [get_ports]
set noloc {}
foreach p $ports {
    if {[get_property -quiet PACKAGE_PIN $p] eq ""} { lappend noloc $p }
}
puts "BITREADY ports=[llength $ports] without_package_pin=[llength $noloc] {$noloc}"
set io_uncon [get_timing_paths -quiet -max_paths 50 -delay_type max -group [get_path_groups]]
puts "BITREADY path_groups={[get_path_groups]}"

# DRC summary line
set fp [open [file join $out drc_bitstream.rpt] r] ; set txt [read $fp] ; close $fp
set viol [regexp -all {Violations found} $txt]
if {[regexp {([0-9]+) violations? found} $txt -> n]} { puts "BITREADY drc_violations=$n" } else {
    if {[string match "*No violations*" $txt]} { puts "BITREADY drc_violations=0" } else { puts "BITREADY drc=unknown" }
}
puts "BITREADY clock={[get_clocks]}"
foreach c [get_clocks] { puts "BITREADY clock [get_property NAME $c] period=[get_property PERIOD $c]" }
puts "BITREADY DONE"
close_project
