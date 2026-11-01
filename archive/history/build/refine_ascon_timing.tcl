# Second and final continuation round: unchanged RTL/constraints, new physical
# implementation run, reusing round one's successful synthesis and IP products.
# vivado -mode batch -source build/refine_ascon_timing.tcl -notrace
set root [file normalize [file join [file dirname [info script]] ..]]
set work [file join $root build local ascon_timing_r1]
set report [file join $root build reports ascon_timing_r2]
set resume [expr {$argc > 0 && [lindex $argv 0] eq "resume"}]
if {![string match "2025.2*" [version -short]]} {error "Requires Vivado 2025.2"}
if {[file exists $report] && !$resume} {error "Refusing to overwrite round two reports"}
if {$resume && [file exists [file join $report route_timing.rpt]]} {error "Round two already completed"}
if {![file exists [file join $work reviewed_routed.dcp]]} {error "Round one must finish first"}
cd $work
open_project [file join $work riscv_vivado_project.xpr]
if {[get_property PART [current_project]] ne "xc7z020clg400-1"} {error "Unexpected part"}
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Completed synthesis required"}
set strategy Performance_ExplorePostRoutePhysOpt
if {$resume} {
    if {[get_property STATUS [get_runs key_review_r2]] ne "Not started"} {error "Resume only permits a never-started run"}
} else {
if {[llength [get_runs -quiet key_review_r2]]} {error "Round two already exists; refusing rerun"}
create_run key_review_r2 -parent_run synth_1 -flow {Vivado Implementation 2025} -strategy $strategy -constrset constrs_1 -part xc7z020clg400-1
}
if {![get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED [get_runs key_review_r2]]} {
    error "Selected strategy did not enable post-route physical optimization"
}
file mkdir $report
if {!$resume} {
# These are the SAME synthesis results, not an additional synthesis measurement.
foreach f {build_context.txt ip_status.rpt synth_timing.rpt synth_utilization.rpt} {
    file copy [file join $root build reports ascon_timing_r1 $f] [file join $report $f]
}
set fp [open [file join $report build_context.txt] a]
puts $fp "\nround=2\nstrategy=$strategy\nsynthesis=reused round one synth_1\nsource_snapshot=build/local/ascon_timing_r1/development_rtl\nrtl_and_constraints_changed=false"
foreach prop [list_property [get_runs key_review_r2]] {
    if {[string match "STEPS.*" $prop]} {puts $fp "$prop=[get_property $prop [get_runs key_review_r2]]"}
}
close $fp
}
launch_runs key_review_r2 -to_step {phys_opt_design (Post-Route)} -jobs 4
wait_on_run key_review_r2
if {[get_property PROGRESS [get_runs key_review_r2]] ne "100%"} {error "Implementation failed: [get_property STATUS [get_runs key_review_r2]]"}
open_run key_review_r2
report_utilization -file [file join $report route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report route_timing.rpt]
report_timing -delay_type max -max_paths 20 -file [file join $report route_paths.rpt]
report_clock_interaction -file [file join $report clock_interaction.rpt]
check_timing -verbose -file [file join $report check_timing.rpt]
report_route_status -file [file join $report route_status.rpt]
report_drc -file [file join $report route_drc.rpt]
report_methodology -file [file join $report methodology.rpt]
write_checkpoint [file join $work reviewed_routed_r2.dcp]
# No write_bitstream/programming. Original board assets remain untouched.
close_project
