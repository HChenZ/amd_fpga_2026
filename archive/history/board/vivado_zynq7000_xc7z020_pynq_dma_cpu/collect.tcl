# Collect actual post-route reports; never promote a failing timing/DRC candidate.
if {![info exists ::cpu_collect_current] || !$::cpu_collect_current} {open_run impl_1}
set root [file normalize [file join [file dirname [info script]] ../..]]
set work [get_property DIRECTORY [current_project]]
set out $root/data/advanced/dma_cpu/vivado_[clock format [clock seconds] -format %Y%m%d_%H%M%S]
file mkdir $out
report_timing_summary -file $out/timing.rpt
report_timing -delay_type max -max_paths 20 -file $out/setup_paths.rpt
report_timing -delay_type min -max_paths 20 -file $out/hold_paths.rpt
report_utilization -file $out/utilization.rpt
report_drc -file $out/drc.rpt
report_route_status -file $out/route_status.rpt
report_methodology -file $out/methodology.rpt
report_clocks -file $out/clocks.rpt
write_xdc -exclude_physical $out/effective_constraints.xdc
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set critical [llength [get_drc_violations -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]]
set pin_export_ok [expr {[llength [get_ports {DDR*}]]>0 && [llength [get_ports {FIXED_IO*}]]>0}]
set lf [open $work/cpu_dma.runs/impl_1/runme.log r]
set runlog [read $lf]
close $lf
set invalid_pin_constraints [regexp -all {CRITICAL WARNING: \[Netlist 29-160\]} $runlog]
set fp [open $out/result.txt w]
puts $fp "vivado=[version -short] part=[get_property PART [current_project]] top=[get_property TOP [current_fileset]] work=$work setup=$setup hold=$hold critical_drc=$critical board=NOT_RUN"
foreach c [get_clocks] {puts $fp "clock=$c period_ns=[get_property PERIOD $c]"}
puts $fp "synth_status=[get_property STATUS [get_runs synth_1]] impl_status=[get_property STATUS [get_runs impl_1]]"
puts $fp "ps_external_ports=$pin_export_ok invalid_pin_constraints=$invalid_pin_constraints"
close $fp
foreach f {context.txt source_files.txt} {if {[file exists $work/$f]} {file copy $work/$f $out/$f}}
if {$setup eq "" || $hold eq "" || $setup<0 || $hold<0 || $critical>0 || !$pin_export_ok || $invalid_pin_constraints>0} {error "CPU implementation gate failed; reports preserved: $out"}
set candidate $out/candidate
file mkdir $candidate
set bit $work/cpu_dma.runs/impl_1/cpu_dma_wrapper.bit
if {[info exists ::cpu_bit_path]} {set bit $::cpu_bit_path}
if {![file exists $bit]} {error "Timing passed but bitstream is not yet generated: $out"}
file copy $bit $candidate/dma_cpu.bit
file copy $work/cpu_dma.gen/sources_1/bd/cpu_dma/hw_handoff/cpu_dma.hwh $candidate/dma_cpu.hwh
file copy $root/build/local/pynq_dma_svc/dma_svc.bin $candidate/dma_svc.bin
file copy $root/build/local/pynq_dma_svc/build.json $candidate/firmware_build.json
puts "CPU_DMA_IMPLEMENTATION_PASS $out"
