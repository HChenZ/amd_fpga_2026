# STA of the integrated key subsystem (PUF+DNA) on top of current RTL, 100 MHz.
# The RTL tree is a copy of src/rtl with the two key-subsystem patches applied
# (build/local/rtl_keys), so src/rtl itself is never modified.
# Adds build/keys_ro_pblock.xdc so the 256 RO + counters land in their own block.
#
#   vivado -mode batch -source build/build_keys_sta.tcl -notrace [-tclargs <tag>]
set root [file normalize [file join [file dirname [info script]] ..]]
set tag    [expr {[llength $argv] > 0 ? "_[lindex $argv 0]" : ""}]
set work   [file join $root build local keys_sta$tag]
set report [file join $root build reports keys_sta_20261025$tag]
if {[file exists $work]} { error "Refusing to overwrite: $work" }
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2" }
file mkdir [file dirname $work]
file copy [file join $root board vivado_zynq7000_xc7z020_baseline] $work
file copy [file join $root build local rtl_keys] [file join $work development_rtl]
file mkdir $report
cd $work
set rtl [file join $work development_rtl]
open_project [file join $work riscv_vivado_project.xpr]
if {[get_property PART [current_project]] ne "xc7z020clg400-1"} { error "Unexpected part" }
remove_files [get_files -of_objects [get_filesets sources_1] -filter {FILE_TYPE == Verilog || FILE_TYPE == "Verilog Header"}]
set sources [concat [glob [file join $rtl *.v]] [glob -nocomplain [file join $rtl *.vh]]]
foreach f [glob [file join $rtl ascon *]] {
    if {([file extension $f] eq ".v" || [file extension $f] eq ".vh") && ![string match "*_tb.v" $f]} { lappend sources $f }
}
foreach f [glob [file join $rtl keys *]] {
    if {[file extension $f] eq ".v"} { lappend sources $f }
}
add_files -norecurse $sources
foreach f $sources {
    if {[file extension $f] eq ".v"} {set_property file_type SystemVerilog [get_files $f]}
}
set_property include_dirs [list $rtl [file join $rtl ascon] [file join $rtl keys]] [get_filesets sources_1]
set_property top top_pl_bram [get_filesets sources_1]

# RO pblock / DONT_TOUCH
set xdc [file join $root build keys_ro_pblock.xdc]
add_files -fileset constrs_1 -norecurse $xdc
update_compile_order -fileset sources_1

foreach ip [get_ips] {
    if {[get_property IS_LOCKED $ip]} { error "Locked IP: $ip" }
}
generate_target all [get_ips]
set fp [open [file join $report build_context.txt] w]
puts $fp "integrated key subsystem (PUF+DNA), pblock pb_ro_puf, 100 MHz"
puts $fp "tool=[version] part=[get_property PART [current_project]] top=top_pl_bram"
puts $fp "date=[clock format [clock seconds]] head=[exec git -C $root rev-parse --short HEAD]"
close $fp
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
open_run synth_1
report_utilization -file [file join $report synth_utilization.rpt]
close_design
create_run impl_k -parent_run synth_1 -flow {Vivado Implementation 2025} -strategy Performance_ExploreWithRemap -constrset constrs_1 -part xc7z020clg400-1
# RO 环是有意为之：在 opt_design 前显式承认，避免 256 条 LUTLP-1 critical warning
set_property STEPS.OPT_DESIGN.TCL.PRE [file join $root build keys_ro_allow_loops.tcl] [get_runs impl_k]
launch_runs impl_k -to_step {phys_opt_design (Post-Route)} -jobs 8
wait_on_run impl_k
if {[get_property PROGRESS [get_runs impl_k]] ne "100%"} { error "Implementation failed: [get_property STATUS [get_runs impl_k]]" }
open_run impl_k
report_utilization -file [file join $report route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report route_timing.rpt]
report_timing -delay_type max -max_paths 12 -file [file join $report route_paths.rpt]
report_route_status -file [file join $report route_status.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set fpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
set tns 0.0
foreach q $fpaths { set tns [expr {$tns + [get_property SLACK $q]}] }
set pw [get_timing_paths -quiet -max_paths 1 -nworst 1 -setup]
set fp [open [file join $report result.txt] w]
puts $fp "RESULT keys_sta strategy=Performance_ExploreWithRemap wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
puts $fp "PATH start=[get_property STARTPOINT_PIN $pw] end=[get_property ENDPOINT_PIN $pw]"
close $fp
puts "RESULT keys_sta wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
write_checkpoint -force [file join $work keys_routed.dcp]
close_project
puts "KEYS STA COMPLETE"
