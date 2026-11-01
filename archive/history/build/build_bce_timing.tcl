# STA of the TIMING B + TIMING E patched RTL (dcache bus_addr_r CE, ascon_ise cancel).
# The patched source tree is build/local/patches/rtl_patched (complete copy of
# src/rtl with the two patches applied) - src/ and board/ are untouched.
# Strategy = current production (Performance_ExploreWithRemap), same part/top/XDC,
# so the result is directly comparable with the recorded WNS +0.007.
#
#   vivado -mode batch -source build/build_bce_timing.tcl -notrace [-tclargs <tag>]
set root [file normalize [file join [file dirname [info script]] ..]]
set variant [expr {[llength $argv] > 0 ? [lindex $argv 0] : "patched"}]
switch -- $variant {
    patched { set rtl_src [file join $root build local patches rtl_patched] }
    control { set rtl_src [file join $root src rtl] }
    b_only  { set rtl_src [file join $root build local patches rtl_B_only] }
    e_only  { set rtl_src [file join $root build local patches rtl_E_only] }
    e2      { set rtl_src [file join $root build local patches rtl_E2] }
    a1      { set rtl_src [file join $root build local patches rtl_A1] }
    default { error "usage: -tclargs <patched|control|b_only|e_only|e2|a1>" }
}
set strategy [expr {[llength $argv] > 1 ? [lindex $argv 1] : "Performance_ExploreWithRemap"}]
set stag [expr {$strategy eq "Performance_ExploreWithRemap" ? "" : "_pr"}]
set base [expr {$variant eq "patched" ? "" : "_$variant"}]
set tag "$base$stag"
set work   [file join $root build local bce_timing$tag]
set report [file join $root build reports bce_timing_20261020$tag]
set patched $rtl_src
if {![file exists $patched]} { error "missing RTL tree: $patched" }
if {[file exists $work]} { error "Refusing to overwrite existing build: $work" }
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2" }
file mkdir [file dirname $work]
file copy [file join $root board vivado_zynq7000_xc7z020_baseline] $work
file copy $patched [file join $work development_rtl]
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
set fp [open [file join $report build_context.txt] w]
puts $fp "variant=$variant rtl_src=$rtl_src strategy=$strategy"
puts $fp "tool=[version] part=[get_property PART [current_project]] top=top_pl_bram host=[exec hostname]"
puts $fp "date=[clock format [clock seconds]] head=[exec git -C $root rev-parse --short HEAD]"
foreach f [list [file join $rtl dcache.v] [file join $rtl ascon ascon_ise.v]] {
    puts $fp "sha256 [file tail $f] = [lindex [exec sha256sum $f] 0]"
}
close $fp
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
open_run synth_1
report_utilization -file [file join $report synth_utilization.rpt]
close_design
create_run impl_m -parent_run synth_1 -flow {Vivado Implementation 2025} -strategy $strategy -constrset constrs_1 -part xc7z020clg400-1
launch_runs impl_m -to_step {phys_opt_design (Post-Route)} -jobs 8
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
puts $fp "RESULT bce_patches strategy=$strategy wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
close $fp
puts "RESULT bce strategy=$strategy wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
write_checkpoint -force [file join $work bce_routed.dcp]
close_project
puts "BCE TIMING BUILD COMPLETE"
