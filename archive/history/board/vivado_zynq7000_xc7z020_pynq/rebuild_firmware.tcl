set root [file normalize [file join [file dirname [info script]] ../..]]
set work $root/build/local/pynq_final/vivado
set coe $root/build/local/pynq_svc/pynq_svc.coe
open_project $work/pynq_overlay.xpr
set_property CONFIG.Coe_File $coe [get_ips blk_mem_gen_0]
foreach f [get_files -all -quiet *.coe] {
 puts "COE_DEP=$f"
 if {[file normalize $f] ne [file normalize $coe]} {remove_files $f}
}
reset_target all [get_ips blk_mem_gen_0]
generate_target all [get_ips blk_mem_gen_0]
reset_run blk_mem_gen_0_synth_1
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "synthesis failed"}
set_property strategy Performance_ExploreWithRemap [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "implementation failed"}
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
