# 生产策略 + 复制钩子（Performance_ExploreWithRemap 全流程，只在放置后插一步扇出复制）
#
#   vivado -mode batch -source build/timing_tests/run_prod_arm.tcl -notrace \
#          -tclargs <tag> <clk_in_period_ns> <ctl|hook> <fo_min> <pats> <maxfan> <dorep>
#
# 与 run_prod_rep.tcl 的关系：流程、约束、报告完全一致，只修掉「钩子文件写出」的 bug
# （原脚本第 66 行 puts 的花括号提前闭合，导致第 67~83 行在父脚本里执行，
#  报 can't read "cand"：no such variable，prod_ctl / prod_rep 在 00:24:41 双双 EXIT=1）。
# 现改为模板 + string map：hooks/rep_hook.tmpl -> <work>/rep_hook.tcl。
#
# 全部 directive 仍由策略给，脚本不手写 opt/place/phys_opt/route 序列，
# 所以结果可以和 d_100（+0.087，同策略无钩子）直接比。
set root [file normalize [file join [file dirname [info script]] ../..]]
set tag      [lindex $argv 0]
set period   [expr {[llength $argv] > 1 ? [lindex $argv 1] : "20.000"}]
set mode     [expr {[llength $argv] > 2 ? [lindex $argv 2] : "hook"}]
set fo_min   [expr {[llength $argv] > 3 ? [lindex $argv 3] : "400"}]
set pats     [expr {[llength $argv] > 4 ? [lindex $argv 4] : "*u_crypto_aead/state*"}]
set maxfan   [expr {[llength $argv] > 5 ? [lindex $argv 5] : "128"}]
set dorep    [expr {[llength $argv] > 6 ? [lindex $argv 6] : "1"}]
set rtl_src  [file normalize [file join $root src rtl]]
if {$tag eq ""} { error "usage: -tclargs <tag> <clk_period_ns> <ctl|hook> <fo_min> <pats> <maxfan> <dorep>" }
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2" }

set work   [file join $root build local tests_20261024 $tag]
set report [file join $root build reports tests_20261024 $tag]
if {[file exists [file join $report result.txt]]} { error "tag $tag already has a result" }
if {[file exists $work]} { error "Refusing to overwrite existing build: $work" }
file mkdir [file dirname $work]; file mkdir $report
file copy [file join $root board vivado_zynq7000_xc7z020_baseline] $work
file copy $rtl_src [file join $work development_rtl]

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
puts $fp "tag=$tag mode=$mode fo_min=$fo_min pats=$pats maxfan=$maxfan dorep=$dorep clk_in_period_ns=$period"
puts $fp "strategy=Performance_ExploreWithRemap tool=[version -short] part=[get_property PART [current_project]] top=top_pl_bram"
puts $fp "date=[clock format [clock seconds]] head=[exec git -C $root rev-parse --short HEAD]"
foreach f [list [file join $rtl dcache.v] [file join $rtl cpu_core.v] [file join $rtl ascon crypto_aead.v]] {
    puts $fp "sha256 [file tail $f] = [lindex [exec sha256sum $f] 0]"
}
close $fp

# ---------------------------------------------------------------- 复制钩子（模板实例化）
if {$mode eq "hook" || $mode eq "physopt"} {
    set tmplname [expr {$mode eq "physopt" ? "physopt_only.tmpl" : "rep_hook.tmpl"}]
    set tmpl [file join $root build timing_tests hooks $tmplname]
    if {![file exists $tmpl]} { error "missing hook template $tmpl" }
    set fh [open $tmpl r]; set body [read $fh]; close $fh
    set body [string map [list "@@FO_MIN@@" $fo_min "@@PATS@@" $pats "@@MAXFAN@@" $maxfan "@@DOREP@@" $dorep] $body]
    set hook [file join $work rep_hook.tcl]
    set fh [open $hook w]; puts $fh $body; close $fh
    puts "PRODARM hook written ($tmplname): $hook"
}

# ---------------------------------------------------------------- synth + impl
launch_runs synth_1 -jobs 6
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
open_run synth_1
report_utilization -file [file join $report synth_utilization.rpt]
close_design

create_run impl_m -parent_run synth_1 -flow {Vivado Implementation 2025} \
    -strategy Performance_ExploreWithRemap -constrset constrs_1 -part xc7z020clg400-1
if {$mode eq "hook" || $mode eq "physopt"} {
    set_property STEPS.PHYS_OPT_DESIGN.TCL.POST [file join $work rep_hook.tcl] [get_runs impl_m]
    puts "PRODARM hook attached to PHYS_OPT_DESIGN.TCL.POST"
}
launch_runs impl_m -jobs 6
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
puts $fp "KNOBS fo_min=$fo_min pats=$pats maxfan=$maxfan dorep=$dorep"
puts $fp "SOURCE head=[exec git -C $root rev-parse --short HEAD] tool=[version -short] date=[clock format [clock seconds]]"
close $fp
puts "PRODARM RESULT tag=$tag mode=$mode wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs] reps=$reps luts=$luts"
write_checkpoint -force [file join $work ${tag}_routed.dcp]
close_project
puts "PRODARM $tag COMPLETE"
