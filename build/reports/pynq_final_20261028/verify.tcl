set root [pwd]
set work $root/build/local/pynq_final/vivado
open_project $work/pynq_overlay.xpr
open_run impl_1
report_timing_summary -file $work/timing.rpt
report_drc -file $work/drc.rpt
report_utilization -file $work/utilization.rpt
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {error "setup timing failed; do not release"}
if {[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]] < 0} {error "hold timing failed; do not release"}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]]} {error "DRC release gate failed"}
set release $root/board/vivado_zynq7000_xc7z020_pynq/release
file mkdir $release
file copy -force $work/pynq_overlay.runs/impl_1/pynq_wrapper.bit $release/pynq.bit
file copy -force $work/pynq_overlay.gen/sources_1/bd/pynq/hw_handoff/pynq.hwh $release/pynq.hwh
puts "PYNQ_BUILD_PASS"
