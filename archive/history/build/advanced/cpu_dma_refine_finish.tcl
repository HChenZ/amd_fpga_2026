# Run after the standalone phys_opt_design call. Preserve FAIL as well as PASS.
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set replicas [llength [get_cells -hier -filter {NAME =~ *_replica*}]]
report_timing_summary -file $cpu_refine_out/timing.rpt
report_timing -delay_type max -max_paths 10 -file $cpu_refine_out/paths.rpt
report_route_status -file $cpu_refine_out/route_status.rpt
report_drc -file $cpu_refine_out/drc.rpt
write_checkpoint $cpu_refine_out/after.dcp
set fp [open $cpu_refine_out/after.txt w]
puts $fp "setup=$setup hold=$hold replicas_before=$cpu_before_replicas replicas_after=$replicas clock_period_ns=[get_property PERIOD [get_clocks clk_fpga_0]]"
close $fp
if {$setup<0 || $hold<0} {error "Bounded physical refinement did not close timing: $cpu_refine_out"}
puts "CPU_REFINED_TIMING_PASS $cpu_refine_out"
