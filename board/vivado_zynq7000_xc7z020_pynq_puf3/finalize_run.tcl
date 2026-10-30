# Gate + bitstream for one routed implementation run of build/local/pynq_puf3/vivado.
#   vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf3/finalize_run.tcl -tclargs impl_N <strategy>
# Same gates as build.tcl; uses the run's post-route phys_opt checkpoint when present.
set run [lindex $argv 0]
set strategy [lindex $argv 1]
set root [file normalize [file join [file dirname [info script]] ../..]]
set work [file join $root build local pynq_puf3 vivado]
set rep  [file join $work reports]
set dcp [file join $work pynq_puf3.runs $run pynq_puf3_wrapper_postroute_physopt.dcp]
if {![file exists $dcp]} {set dcp [file join $work pynq_puf3.runs $run pynq_puf3_wrapper_routed.dcp]}
open_checkpoint $dcp
report_timing_summary -delay_type min_max -max_paths 10 -file $rep/timing_summary.rpt
report_timing_summary -delay_type min_max -max_paths 1 -report_unconstrained -file $rep/timing_unconstrained.rpt
check_timing -verbose -file $rep/check_timing.rpt
report_drc -file $rep/drc.rpt
report_methodology -file $rep/methodology.rpt
report_utilization -file $rep/utilization.rpt
report_utilization -pblocks [get_pblocks -quiet pb_ro_puf] -file $rep/pblock_utilization.rpt
report_clock_interaction -file $rep/clock_interaction.rpt
report_route_status -file $rep/route_status.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set drc_bad [llength [get_drc_violations -quiet -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]]
set ro_luts [get_cells -quiet -hier -filter {NAME =~ "*u_ro/*" && REF_NAME =~ "LUT*"}]
set ro_assigned [llength [filter $ro_luts {PBLOCK =~ "*pb_ro_puf"}]]
set ro_placed 0
foreach c $ro_luts {
    if {[regexp {SLICE_X(\d+)Y(\d+)} [get_property LOC $c] -> x y] && $x >= 60 && $x <= 113 && $y >= 115 && $y <= 149} {incr ro_placed}
}
set pb_soft [get_property IS_SOFT [get_pblocks pb_ro_puf]]
set f [open [file join $work pynq_puf3.runs $run runme.log] r]; set log [read $f]; close $f
set n29160 [regexp -all {Netlist 29-160} $log]
set fp [open $rep/gate.txt w]
puts $fp "run=$run strategy=$strategy dcp=[file tail $dcp] wns=$wns whs=$whs drc_error_or_critical=$drc_bad ro_luts=[llength $ro_luts] ro_luts_assigned_pblock=$ro_assigned ro_luts_placed_in_pblock_region=$ro_placed pblock_soft=$pb_soft netlist_29_160=$n29160"
close $fp
puts "PYNQ_PUF3_GATE run=$run strategy=$strategy wns=$wns whs=$whs drc=$drc_bad ro=[llength $ro_luts] assigned=$ro_assigned placed_in_region=$ro_placed soft=$pb_soft n29160=$n29160"
if {$wns < 0 || $whs < 0} {error "timing gate failed"}
if {$drc_bad} {error "DRC gate failed"}
if {[llength $ro_luts] != 1280 || $ro_assigned != 1280} {error "RO structure gate failed"}
if {$n29160} {error "PS pin constraints applied to internal pins"}
write_bitstream -force $work/pynq_puf3.bit
file copy -force $work/pynq_puf3.gen/sources_1/bd/pynq_puf3/hw_handoff/pynq_puf3.hwh $work/pynq_puf3.hwh
puts "PYNQ_PUF3_BUILD_PASS"
