# Run after route completion. Reports are deliberately not a timing-signoff gate.
set root [file normalize [file join [file dirname [info script]] ../..]]
if {![info exists ::puf_report_label]} {set ::puf_report_label implementation}
set out $root/data/advanced/puf_soc/$::puf_report_label
file mkdir $out
if {![info exists ::puf_report_current] || !$::puf_report_current} {open_run impl_1}
report_timing_summary -report_unconstrained -file $out/timing.rpt
report_timing -max_paths 20 -file $out/setup_paths.rpt
report_timing -delay_type min -max_paths 20 -file $out/hold_paths.rpt
report_utilization -file $out/utilization.rpt
report_drc -file $out/drc.rpt
report_methodology -file $out/methodology.rpt
report_clock_interaction -file $out/clock_interaction.rpt
report_cdc -file $out/cdc.rpt
report_clocks -file $out/clocks.rpt
report_route_status -file $out/route_status.rpt
check_timing -verbose -file $out/check_timing.rpt
write_xdc -force $out/applied_constraints.xdc
set fp [open $out/verdict.txt w]
puts $fp "STRUCTURAL_DIAGNOSTIC_ONLY; NOT TIMING SIGNOFF; RO minimum period NOT_MEASURED; no RO clocks invented."
puts $fp "setup_slack=[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]"
puts $fp "hold_slack=[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
puts $fp "part=[get_property PART [current_project]] top=[get_property TOP [current_fileset]] version=[version -short]"
close $fp
