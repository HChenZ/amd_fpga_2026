# Run only after completed implementation; reports retained even if timing fails.
open_run impl_1
set root [file normalize [file join [file dirname [info script]] ../..]]
set stamp [clock format [clock seconds] -format %Y%m%d_%H%M%S]
set out [file join $root data advanced dma_direct vivado_$stamp]
file mkdir $out
report_timing_summary -file $out/timing.rpt
report_utilization -file $out/utilization.rpt
report_drc -file $out/drc.rpt
report_route_status -file $out/route_status.rpt
report_methodology -file $out/methodology.rpt
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set critical [llength [get_drc_violations -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]]
set fp [open $out/result.txt w]
puts $fp "vivado=[version -short] part=[get_property PART [current_project]] top=[get_property TOP [current_fileset]] setup=$setup hold=$hold critical_drc=$critical board=NOT_RUN"
close $fp
set work [get_property DIRECTORY [current_project]]
file copy $work/context.txt $out/context.txt
if {$setup<0 || $hold<0 || $critical>0} {error "Implementation gate failed; see $out"}
set release [file join $out candidate]
file mkdir $release
file copy $work/d.runs/impl_1/d_wrapper.bit $release/dma_direct.bit
file copy $work/d.gen/sources_1/bd/d/hw_handoff/d.hwh $release/dma_direct.hwh
puts "DMA_IMPLEMENTATION_PASS $out"
