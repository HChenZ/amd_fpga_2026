# R2 wave runner: production strategy (Performance_ExploreWithRemap) end to end,
# with an OPTIONAL hand-written hook attached to PHYS_OPT_DESIGN.TCL.POST.
#
#   vivado -mode batch -source build/timing_tests/run_rep2.tcl -notrace \
#          -tclargs <tag> <clk_in_period_ns> <ctl|hook> [hook.tcl]
#
# Same flow / constraints / reports as run_prod_arm.tcl, so results compare
# directly against prod_ctl / d_100 (+0.087) and pr_sel_b (+0.184).
# Differences vs run_prod_arm.tcl:
#   * output tree is build/{local,reports}/tests_20261025/
#   * the hook is a checked-in file (hooks/r2_*.tcl), not a generated template
#   * result.txt also records the fanout of the four sel_* nets after routing,
#     so "did the net actually get split" is visible without opening the DCP
set root [file normalize [file join [file dirname [info script]] ../..]]
set tag      [lindex $argv 0]
set period   [expr {[llength $argv] > 1 ? [lindex $argv 1] : "20.000"}]
set mode     [expr {[llength $argv] > 2 ? [lindex $argv 2] : "ctl"}]
set hooksrc  [expr {[llength $argv] > 3 ? [lindex $argv 3] : ""}]
if {$tag eq ""} { error "usage: -tclargs <tag> <clk_in_period_ns> <ctl|hook> \[hook.tcl\]" }
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2" }
if {$mode eq "hook"} {
    if {$hooksrc eq "" || ![file exists $hooksrc]} { error "missing hook file: $hooksrc" }
}

set wave   tests_20261025
set work   [file join $root build local $wave $tag]
set report [file join $root build reports $wave $tag]
if {[file exists [file join $report result.txt]]} { error "tag $tag already has a result" }
if {[file exists $work]} { error "Refusing to overwrite existing build: $work" }
file mkdir [file dirname $work]; file mkdir $report
file copy [file join $root board vivado_zynq7000_xc7z020_baseline] $work
file copy [file join $root src rtl] [file join $work development_rtl]

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
foreach f $sources { if {[file extension $f] eq ".v"} { set_property file_type SystemVerilog [get_files $f] } }
set_property include_dirs [list $rtl [file join $rtl ascon]] [get_filesets sources_1]
set_property top top_pl_bram [get_filesets sources_1]
update_compile_order -fileset sources_1
foreach ip [get_ips] { if {[get_property IS_LOCKED $ip]} { error "Locked IP: $ip" } }
generate_target all [get_ips]

set fp [open [file join $report build_context.txt] w]
puts $fp "tag=$tag mode=$mode clk_in_period_ns=$period strategy=Performance_ExploreWithRemap"
puts $fp "hook=[expr {$hooksrc eq "" ? "none" : [file tail $hooksrc]}]"
if {$hooksrc ne ""} { puts $fp "hook_sha256=[lindex [exec sha256sum $hooksrc] 0]" }
puts $fp "tool=[version] part=[get_property PART [current_project]] top=top_pl_bram host=[exec hostname]"
puts $fp "date=[clock format [clock seconds]] head=[exec git -C $root rev-parse --short HEAD]"
foreach f [list [file join $rtl dcache.v] [file join $rtl cpu_core.v] [file join $rtl ascon crypto_aead.v]] {
    puts $fp "sha256 [file tail $f] = [lindex [exec sha256sum $f] 0]"
}
close $fp

# ---------------------------------------------------------------- synth + impl
launch_runs synth_1 -jobs 5
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
open_run synth_1
report_utilization -file [file join $report synth_utilization.rpt]
close_design

create_run impl_m -parent_run synth_1 -flow {Vivado Implementation 2025} \
    -strategy Performance_ExploreWithRemap -constrset constrs_1 -part xc7z020clg400-1
set hookdst ""
if {$mode eq "hook"} {
    # Attach the checked-in hook IN PLACE: each hook does
    #   source [file join [file dirname [info script]] .. r2_lib.tcl]
    # so copying it into the run directory would break that relative path.
    # Hooks are ASCII-only, so Vivado's platform-encoding source read is safe.
    set hookdst [file normalize $hooksrc]
    set_property STEPS.PHYS_OPT_DESIGN.TCL.POST $hookdst [get_runs impl_m]
    puts "R2 hook attached: $hookdst"
}
launch_runs impl_m -jobs 5
wait_on_run impl_m
if {[get_property PROGRESS [get_runs impl_m]] ne "100%"} {
    error "Implementation failed: [get_property STATUS [get_runs impl_m]]"
}
open_run impl_m
report_utilization -file [file join $report route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report route_timing.rpt]
report_timing -delay_type max -max_paths 40 -file [file join $report route_paths.rpt]
report_route_status -file [file join $report route_status.rpt]
catch { report_high_fanout_nets -fanout_greater_than 128 -max_nets 60 -load_types -file [file join $report high_fanout.rpt] }
catch { report_clock_utilization -file [file join $report clock_utilization.rpt] }

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set fpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
set tns 0.0
foreach q $fpaths { set tns [expr {$tns + [get_property SLACK $q]}] }
set luts [llength [get_cells -hier -filter {PRIMITIVE_GROUP == "LUT"}]]
set ffs  [llength [get_cells -hier -filter {IS_SEQUENTIAL}]]
set reps [llength [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ "*_rep*"}]]
set wp [get_timing_paths -max_paths 1 -nworst 1 -setup]
set fp [open [file join $report result.txt] w]
puts $fp "RESULT tag=$tag mode=$mode strategy=Performance_ExploreWithRemap wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs] luts=$luts ffs=$ffs rep_cells=$reps"
puts $fp "PATH start=[get_property STARTPOINT_PIN $wp] end=[get_property ENDPOINT_PIN $wp] dp=[format %.3f [get_property DATAPATH_DELAY $wp]] logic=[format %.3f [get_property DATAPATH_LOGIC_DELAY $wp]] net=[format %.3f [get_property DATAPATH_NET_DELAY $wp]] levels=[get_property LOGIC_LEVELS $wp]"
puts $fp "HOOK [expr {$hooksrc eq "" ? "none" : [file tail $hooksrc]}]"
foreach nm [list \
    "u_soc_axi_top/u_soc_top/u_cpu_core/id_ex_u/sel_ex_mem_rs1_o" \
    "u_soc_axi_top/u_soc_top/u_cpu_core/id_ex_u/sel_ex_mem_rs2_o" \
    "u_soc_axi_top/u_soc_top/u_cpu_core/id_ex_u/sel_mem_wb_rs1_o" \
    "u_soc_axi_top/u_soc_top/u_cpu_core/id_ex_u/sel_mem_wb_rs2_o"] {
    set n [get_nets -quiet -hier -filter "NAME == \"$nm\""]
    if {[llength $n] == 1} {
        puts $fp "NET fo=[get_property FLAT_PIN_COUNT $n] $nm"
    } else {
        puts $fp "NET fo=na $nm"
    }
}
puts $fp "SOURCE head=[exec git -C $root rev-parse --short HEAD] tool=[version -short] date=[clock format [clock seconds]]"
close $fp
puts "R2 RESULT tag=$tag mode=$mode wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs] reps=$reps luts=$luts ffs=$ffs"
write_checkpoint -force [file join $work ${tag}_routed.dcp]
close_project
puts "R2 $tag COMPLETE"
