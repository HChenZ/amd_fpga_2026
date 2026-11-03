# 生产策略 + 复制钩子（ExploreWithRemap 全流程，只在放置后插一步扇出复制）
#
#   vivado -mode batch -source build/timing_tests/run_prod_rep.tcl -notrace \
#          -tclargs <tag> <rtl_tree> <clk_in_period_ns> <ctl|rep>
#
# 做法：不手写 directive 序列，仍然用 create_run -strategy Performance_ExploreWithRemap，
# 只给 PHYS_OPT_DESIGN（放置后）这一步挂一个 TCL.POST 钩子做扇出复制。
# 这样 opt/place/phys_opt/route 的 directive 完全等同生产策略，结果可与 d_100（+0.087）直接比。
#
# 钩子里复制什么：放置后 fanout >= 400、驱动是 u_crypto_aead/state* 的那些网
# （C+D 之后最差路径就是 state[3]：fo=627、单根走线 9.29 ns）。
# 约束：MAX_FANOUT 128 提示 + phys_opt_design -force_replication_on_nets，
# 复制体设 EQUIVALENT_REGISTER_REMOVAL=NO 防后续 phys_opt 折回，不用 DONT_TOUCH。
set root [file normalize [file join [file dirname [info script]] ../..]]
set tag      [lindex $argv 0]
set rtl_src  [file normalize [lindex $argv 1]]
set period   [lindex $argv 2]
set mode     [expr {[llength $argv] > 3 ? [lindex $argv 3] : "rep"}]
if {$tag eq ""} { error "usage: -tclargs <tag> <rtl_tree> <clk_period_ns> \[ctl|rep\]" }
if {![file exists $rtl_src]} { error "missing RTL tree: $rtl_src" }
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2" }

set work   [file join $root build local tests_20261024 $tag]
set report [file join $root build reports tests_20261024 $tag]
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
puts $fp "tag=$tag mode=$mode rtl_src=$rtl_src clk_period_ns=$period strategy=Performance_ExploreWithRemap+hook:$mode"
puts $fp "tool=[version] part=[get_property PART [current_project]] top=top_pl_bram host=[exec hostname]"
puts $fp "date=[clock format [clock seconds]] head=[exec git -C $root rev-parse --short HEAD]"
foreach f [list [file join $rtl dcache.v] [file join $rtl cpu_core.v] [file join $rtl ascon crypto_aead.v]] {
    puts $fp "sha256 [file tail $f] = [lindex [exec sha256sum $f] 0]"
}
close $fp

# ---------------------------------------------------------------- 复制钩子
set hook [file join $work rep_hook.tcl]
set fh [open $hook w]
puts $fh {# hook: PHYS_OPT_DESIGN.TCL.POST -- post-placement fanout replication
# ASCII only: Vivado writes TCL.PRE/POST files with the platform encoding, and a
# non-UTF8 comment breaks the braced string (2026-10-25 lesson).
set cand {}
foreach n [get_nets -quiet -hier -filter "FLAT_PIN_COUNT >= 400"] {
    set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
    set c [get_cells -quiet -of_objects $drv]
    if {$c eq ""} { continue }
    # The net keeps the RTL name (state[*]); the driving FF is renamed to
    # FSM_sequential_state_reg[*] by synthesis. Match both, otherwise the
    # selection silently comes up empty (2026-10-25 lesson).
    set nn [get_property NAME $n]
    set cn [get_property NAME $c]
    # Single-net recipe: only the net that keeps the RTL name state[*]
    # (the winning arm replicated exactly one net; adding a second one hurt).
    if {![string match "*/u_crypto_aead/state*" $nn]} { continue }
    lappend cand $n
}
puts "PRODREP candidates=[llength $cand]"
foreach n $cand {
    puts "  PRODREP fo=[get_property FLAT_PIN_COUNT $n] [get_property NAME $n]"
    catch { set_property MAX_FANOUT 128 $n }
}
if {[llength $cand] > 0} { phys_opt_design -force_replication_on_nets $cand }
set reps [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ "*_rep*"}]
puts "PRODREP replica_cells=[llength $reps]"
foreach c $reps { catch { set_property EQUIVALENT_REGISTER_REMOVAL NO $c } }
foreach n $cand { puts "  PRODREP after fo=[get_property FLAT_PIN_COUNT $n] [get_property NAME $n]" }}
close $fh

# ---------------------------------------------------------------- synth + impl
launch_runs synth_1 -jobs 6
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
open_run synth_1
report_utilization -file [file join $report synth_utilization.rpt]
close_design

create_run impl_m -parent_run synth_1 -flow {Vivado Implementation 2025} \
    -strategy Performance_ExploreWithRemap -constrset constrs_1 -part xc7z020clg400-1
if {$mode eq "rep"} {
    set_property STEPS.PHYS_OPT_DESIGN.TCL.POST $hook [get_runs impl_m]
    puts "PRODREP hook attached to PHYS_OPT_DESIGN.TCL.POST"
}
launch_runs impl_m -to_step {phys_opt_design (Post-Route)} -jobs 6
wait_on_run impl_m
if {[get_property PROGRESS [get_runs impl_m]] ne "100%"} {
    error "Implementation failed: [get_property STATUS [get_runs impl_m]]"
}
open_run impl_m
report_utilization -file [file join $report route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report route_timing.rpt]
report_timing -delay_type max -max_paths 20 -file [file join $report route_paths.rpt]
report_route_status -file [file join $report route_status.rpt]

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set fpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
set tns 0.0
foreach q $fpaths { set tns [expr {$tns + [get_property SLACK $q]}] }
set reps [llength [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ "*_rep*"}]]
set wp [get_timing_paths -max_paths 1 -nworst 1 -setup]
set fp [open [file join $report result.txt] w]
puts $fp "RESULT tag=$tag mode=$mode strategy=Performance_ExploreWithRemap wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs] rep_cells=$reps"
puts $fp "PATH start=[get_property STARTPOINT_PIN $wp] end=[get_property ENDPOINT_PIN $wp] dp=[format %.3f [get_property DATAPATH_DELAY $wp]] logic=[format %.3f [get_property DATAPATH_LOGIC_DELAY $wp]] net=[format %.3f [get_property DATAPATH_NET_DELAY $wp]] levels=[get_property LOGIC_LEVELS $wp]"
close $fp
puts "PRODREP RESULT tag=$tag mode=$mode wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs] reps=$reps"
write_checkpoint -force [file join $work ${tag}_routed.dcp]
close_project
puts "PRODREP $tag COMPLETE"
