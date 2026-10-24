# Variant implementation run for the next.html route tests (2026-10-24).
# Compares three configurations on the same script/tool/part:
#   f_100    TIMING F (MMIO write-decode registered) @ core 10.000 ns
#   f_80     TIMING F                                   @ core 12.500 ns
#   ctl_80   unmodified src/rtl                         @ core 12.500 ns
#
# Nothing in src/ or board/ is modified: the project tree and the RTL tree are
# copied into build/local/tests_20261024/<tag>/.
#
# Clock retargeting: the MMCM IP is untouched (CLKFBOUT_MULT_F=18,
# CLKOUT0_DIVIDE_F=9 -> core = 2x input), so the input-port constraint sets the
# core period. 25.000 ns input -> 12.500 ns core (80 MHz), 20.000 -> 10.000 (100 MHz).
# The core netlist / datapath is identical to what a board build with a different
# MMCM divider would use; only the clock-generation ratio differs.
#
#   vivado -mode batch -source build/local/tests_20261024/run_variantF.tcl -notrace \
#          -tclargs <tag> <rtl_tree> <clk_period_ns> [strategy]
set root [file normalize [file join [file dirname [info script]] ../..]]
set tag      [lindex $argv 0]
set rtl_src  [file normalize [lindex $argv 1]]
set period   [lindex $argv 2]
set strategy [expr {[llength $argv] > 3 ? [lindex $argv 3] : "Performance_ExploreWithRemap"}]
if {$tag eq ""} { error "usage: -tclargs <tag> <rtl_tree> <clk_period_ns> \[strategy\]" }
if {![file exists $rtl_src]} { error "missing RTL tree: $rtl_src" }
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2" }

set work   [file join $root build local tests_20261024 $tag]
set report [file join $root build reports tests_20261024 $tag]
if {[file exists $work]} { error "Refusing to overwrite existing build: $work" }
file mkdir [file dirname $work]
file mkdir $report
file copy [file join $root board vivado_zynq7000_xc7z020_baseline] $work
file copy $rtl_src [file join $work development_rtl]

# retarget the input clock constraint
set xdc [file join $work riscv_vivado_project.srcs constrs_1 new const.xdc]
set fh [open $xdc r]; set txt [read $fh]; close $fh
regsub {create_clock -period [0-9.]+ -name clk} $txt "create_clock -period $period -name clk" txt
set fh [open $xdc w]; puts -nonewline $fh $txt; close $fh

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
puts $fp "tag=$tag rtl_src=$rtl_src clk_period_ns=$period strategy=$strategy"
puts $fp "tool=[version] part=[get_property PART [current_project]] top=top_pl_bram host=[exec hostname]"
puts $fp "date=[clock format [clock seconds]] head=[exec git -C $root rev-parse --short HEAD]"
foreach f [list [file join $rtl dcache.v] [file join $rtl ascon ascon_mmio.v] [file join $rtl ascon ascon_ise.v]] {
    puts $fp "sha256 [file tail $f] = [lindex [exec sha256sum $f] 0]"
}
close $fp

launch_runs synth_1 -jobs 6
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
open_run synth_1
report_utilization -file [file join $report synth_utilization.rpt]
close_design

create_run impl_m -parent_run synth_1 -flow {Vivado Implementation 2025} -strategy $strategy -constrset constrs_1 -part xc7z020clg400-1
launch_runs impl_m -to_step {phys_opt_design (Post-Route)} -jobs 6
wait_on_run impl_m
if {[get_property PROGRESS [get_runs impl_m]] ne "100%"} { error "Implementation failed: [get_property STATUS [get_runs impl_m]]" }
open_run impl_m
report_utilization -file [file join $report route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report route_timing.rpt]
report_timing -delay_type max -max_paths 20 -file [file join $report route_paths.rpt]
report_timing -delay_type max -max_paths 2000 -nworst 1 -slack_less_than 2.0 \
    -input_pins -file [file join $report route_paths_lt2.rpt]
report_route_status -file [file join $report route_status.rpt]
report_clock_utilization -file [file join $report clock_utilization.rpt]

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set fpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
set tns 0.0
foreach q $fpaths { set tns [expr {$tns + [get_property SLACK $q]}] }
set clk [get_clocks -quiet clk_out1_clk_wiz_0]
set corep [expr {$clk ne "" ? [get_property PERIOD $clk] : "n/a"}]
set fp [open [file join $report result.txt] w]
puts $fp "RESULT tag=$tag clk_in=$period core_period=$corep strategy=$strategy wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
close $fp
puts "RESULT tag=$tag core_period=$corep strategy=$strategy wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
write_checkpoint -force [file join $work ${tag}_routed.dcp]
close_project
puts "VARIANT $tag COMPLETE"
