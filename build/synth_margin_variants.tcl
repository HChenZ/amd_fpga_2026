# Synthesis-level margin experiments at 100 MHz (no RTL change).
# Fresh isolated copy of the recovered XC7Z020 baseline + current src/rtl; the
# running projects and the board baseline itself are not touched.
#
#   vivado -mode batch -source build/synth_margin_variants.tcl -notrace -tclargs <tag>
#
# tags:
#   flat_perf    FLATTEN_HIERARCHY=full  SYNTH DIRECTIVE=PerformanceOptimized
#   flat_alt     FLATTEN_HIERARCHY=full  SYNTH DIRECTIVE=AlternateRoutability
#   rebuilt_alt  FLATTEN_HIERARCHY=rebuilt SYNTH DIRECTIVE=AlternateRoutability
# Impl is always Performance_ExploreWithRemap (the current production strategy).
set root [file normalize [file join [file dirname [info script]] ..]]
set tag  [lindex $argv 0]
if {$tag eq ""} { error "usage: -tclargs <flat_perf|flat_alt|rebuilt_alt>" }
switch -- $tag {
    flat_perf   { set flat full    ; set sdir PerformanceOptimized }
    flat_alt    { set flat full    ; set sdir AlternateRoutability }
    rebuilt_alt { set flat rebuilt ; set sdir AlternateRoutability }
    default     { error "unknown tag $tag" }
}
set work   [file join $root build local synth_margin_$tag]
set report [file join $root build reports synth_margin_20261020 $tag]
if {[file exists $work]} { error "Refusing to overwrite existing build: $work" }
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2" }
file mkdir [file dirname $work]
file copy [file join $root board vivado_zynq7000_xc7z020_baseline] $work
file copy [file join $root src rtl] [file join $work development_rtl]
file mkdir $report
cd $work
set rtl [file join $work development_rtl]
open_project [file join $work riscv_vivado_project.xpr]
if {[get_property PART [current_project]] ne "xc7z020clg400-1"} { error "Unexpected part" }
set old [get_files -of_objects [get_filesets sources_1] -filter {FILE_TYPE == Verilog || FILE_TYPE == "Verilog Header"}]
remove_files $old
set sources [concat [glob [file join $rtl *.v]] [glob -nocomplain [file join $rtl *.vh]]]
foreach f [glob [file join $rtl ascon *]] {
    if {([file extension $f] eq ".v" || [file extension $f] eq ".vh") && ![string match "*_tb.v" $f]} { lappend sources $f }
}
add_files -norecurse $sources
foreach f $sources {
    if {[file extension $f] eq ".v"} {set_property file_type SystemVerilog [get_files $f]}
}
set_property include_dirs [list $rtl [file join $rtl ascon]] [get_filesets sources_1]
set_property top top_pl_bram [get_filesets sources_1]
update_compile_order -fileset sources_1
foreach ip [get_ips] {
    if {[get_property IS_LOCKED $ip]} { error "Locked IP: $ip" }
}
generate_target all [get_ips]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY $flat [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE $sdir [get_runs synth_1]
set fp [open [file join $report build_context.txt] w]
puts $fp "tag=$tag flatten=$flat synth_directive=$sdir impl=Performance_ExploreWithRemap"
puts $fp "tool=[version] part=[get_property PART [current_project]] top=top_pl_bram host=[exec hostname]"
puts $fp "date=[clock format [clock seconds]] head=[exec git -C $root rev-parse --short HEAD]"
close $fp
launch_runs synth_1 -jobs 6
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed: [get_property STATUS [get_runs synth_1]]" }
open_run synth_1
report_utilization -file [file join $report synth_utilization.rpt]
report_timing_summary -file [file join $report synth_timing.rpt]
close_design
create_run impl_m -parent_run synth_1 -flow {Vivado Implementation 2025} -strategy Performance_ExploreWithRemap -constrset constrs_1 -part xc7z020clg400-1
launch_runs impl_m -to_step {phys_opt_design (Post-Route)} -jobs 6
wait_on_run impl_m
if {[get_property PROGRESS [get_runs impl_m]] ne "100%"} { error "Implementation failed: [get_property STATUS [get_runs impl_m]]" }
open_run impl_m
report_utilization -file [file join $report route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report route_timing.rpt]
report_timing -delay_type max -max_paths 12 -file [file join $report route_paths.rpt]
report_route_status -file [file join $report route_status.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set fpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
set tns 0.0
foreach q $fpaths { set tns [expr {$tns + [get_property SLACK $q]}] }
set fp [open [file join $report result.txt] w]
puts $fp "RESULT tag=$tag flatten=$flat synth=$sdir wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
close $fp
puts "RESULT tag=$tag wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
write_checkpoint -force [file join $work ${tag}_routed.dcp] -routing
close_project
puts "SYNTH MARGIN $tag COMPLETE"
