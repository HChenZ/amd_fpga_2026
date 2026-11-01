# -----------------------------------------------------------------------------
# IO 时序签核变体：在 XC7Z020 上板工程副本上跑 synth + impl，产出 IO 覆盖证据。
#
#   vivado.bat -mode batch -notrace -source C:/.../build/build_io_sta.tcl -tclargs io
#   vivado.bat -mode batch -notrace -source C:/.../build/build_io_sta.tcl -tclargs noio
#
# tclargs:
#   io   = 加 const_io.xdc（签核变体，本轮交付）
#   noio = 不加 const_io.xdc（同会话对照组，用来把"IO 约束的影响"从"源集/策略的影响"里分离）
#
# 两个变体跑在**各自独立的工程副本**上（build/local/io_sta_20261027/proj_<tag>），
# 与原工程 board/.../riscv_vivado_project 和 PUF 线的 impl_1 完全隔离：
# 原工程的 XPR/RUN/bitstream 一个字节都不动。
#
# 不产生 bitstream：本轮是算力/约束签核，不是镜像替换；三份冻结 bitstream 的哈希
# 必须保持不变（docs/freeze_checkpoint_20261027.md §3）。impl 只跑到
# phys_opt_design (Post-Route)。
# -----------------------------------------------------------------------------
set tag [expr {[llength $argv] > 0 ? [lindex $argv 0] : ""}]
if {$tag ni {io noio}} { error "usage: -tclargs io|noio [xpr] [workdir]   (got '$tag')" }
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2 (got [version -short])" }

set root    [file normalize [file join [file dirname [info script]] ..]]
set work    [file join $root build local io_sta_20261027 proj_$tag]
set report  [file join $root build reports io_sta_20261027 $tag]
set xpr     [file join $work riscv_vivado_project riscv_vivado_project.xpr]
# 可选覆盖：给"钉住源快照的对照组"用（避免并发改 RTL 污染对照）
if {[llength $argv] > 1 && [lindex $argv 1] ne ""} { set xpr  [lindex $argv 1] }
if {[llength $argv] > 2 && [lindex $argv 2] ne ""} { set work [lindex $argv 2] }
set xdc_io  [file join $root board vivado_zynq7000_xc7z020_ascon riscv_vivado_project \
                        riscv_vivado_project.srcs constrs_1 new const_io.xdc]
set xdc_puf [file join $root board vivado_zynq7000_xc7z020_ascon riscv_vivado_project \
                        riscv_vivado_project.srcs sources_1 imports bin_file ascon_hw.coe]
set allow   [file join $root build keys_ro_allow_loops.tcl]

foreach f [list $xpr $allow $xdc_puf] { if {![file exists $f]} { error "missing input: $f" } }
if {$tag eq "io" && ![file exists $xdc_io]} { error "missing const_io.xdc: $xdc_io" }
file mkdir $report

open_project $xpr
if {[get_property PART [current_project]] ne "xc7z020clg400-1"} { error "Unexpected part" }
if {[get_property top [get_filesets sources_1]] ne "top_pl_bram"} { error "Unexpected top" }

# 镜像口径：ascon_hw.coe（与 P0 冻结口径一致；原工程此刻指向 ascon_keys.coe）
# 只影响 BRAM 初值，不改时序；本轮不出 bitstream，因此不产生可烧录镜像。
set_property CONFIG.Coe_File $xdc_puf [get_ips blk_mem_gen_0]

# ---- 约束集 ---------------------------------------------------------------
set constr_files [get_files -of_objects [get_filesets constrs_1]]
puts "CONSTR BEFORE($tag): $constr_files"
if {$tag eq "io"} {
    if {[llength [get_files -quiet $xdc_io]] == 0} {
        add_files -fileset constrs_1 -norecurse $xdc_io
        set_property used_in_synthesis true       [get_files $xdc_io]
        set_property used_in_implementation true  [get_files $xdc_io]
    }
    # 同一端口不要同时出现 false_path 与 input/output delay（避免自相矛盾）
    set io_ports {uart_rxd uart_txd}
} else {
    if {[llength [get_files -quiet $xdc_io]]} { error "noio variant must not contain const_io.xdc" }
}
update_compile_order -fileset sources_1
set constr_files [get_files -of_objects [get_filesets constrs_1]]
puts "CONSTR AFTER($tag): $constr_files"

foreach ip [get_ips] { if {[get_property IS_LOCKED $ip]} { error "Locked IP: $ip" } }
generate_target all [get_ips]

# ---- 上下文留档 -----------------------------------------------------------
set fp [open [file join $report build_context.txt] w]
puts $fp "IO timing signoff variant: tag=$tag const_io.xdc=[expr {$tag eq "io" ? "YES" : "NO"}]"
puts $fp "goal=board-level IO constraint coverage + timing signoff (no bitstream produced)"
puts $fp "tool=[version]"
puts $fp "part=[get_property PART [current_project]] top=[get_property top [get_filesets sources_1]]"
puts $fp "coe=[get_property CONFIG.Coe_File [get_ips blk_mem_gen_0]]"
puts $fp "constrset_files=$constr_files"
puts $fp "synth_strategy=[get_property strategy [get_runs synth_1]]"
puts $fp "impl_strategy=[get_property strategy [get_runs impl_1]]"
puts $fp "impl_opt_pre_tcl=[get_property STEPS.OPT_DESIGN.TCL.PRE [get_runs impl_1]]"
puts $fp "n_src=[llength [get_files -of_objects [get_filesets sources_1]]]"
puts $fp "date=[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S %z}]"
puts $fp "head=[string trim [exec git -C $root rev-parse --short HEAD]]"
puts $fp "branch=[string trim [exec git -C $root rev-parse --abbrev-ref HEAD]]"
puts $fp "dirty=[expr {[string trim [exec git -C $root status --porcelain]] ne "" ? "yes" : "no"}]"
close $fp

# ---- 综合 -----------------------------------------------------------------
reset_run synth_1
launch_runs synth_1 -jobs 10
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1 -name synth_1
report_utilization -file [file join $report synth_utilization.rpt]
close_design

# ---- 实现（策略沿用工程里的 Performance_ExploreWithRemap + RO 环 allow）----
if {[file exists $allow]} {
    set_property STEPS.OPT_DESIGN.TCL.PRE $allow [get_runs impl_1]
}
reset_run impl_1
launch_runs impl_1 -to_step {phys_opt_design (Post-Route)} -jobs 10
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1 -name impl_1

report_utilization               -file [file join $report route_utilization.rpt]
report_route_status              -file [file join $report route_status.rpt]
report_drc                       -file [file join $report route_drc.rpt]
report_methodology               -file [file join $report methodology.rpt]
check_timing -verbose            -file [file join $report check_timing.rpt]
report_cdc                       -file [file join $report cdc.rpt]
report_clock_interaction         -file [file join $report clock_interaction.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 10 \
                                 -file [file join $report route_timing.rpt]
report_timing -delay_type max -max_paths 20 -nworst 20 \
                                 -file [file join $report route_paths.rpt]
# 用 write_xdc -file（**不要**加 -constraints：Vivado 2025.2 会把它当带值选项，
# 报 "Invalid option value '-file' specified for '-constraints'" 并让整个 run 以非 0 退出）
write_xdc -force -file [file join $report applied_constraints.xdc]

# ---- 判据提取 -------------------------------------------------------------
# check_timing 里每条规则的计数：报告中形如 "1. checking no_input_delay (4)"
set ct_sum [file join $report check_timing_summary.txt]
set fp [open $ct_sum w]
set fin [open [file join $report check_timing.rpt] r]
set nline 0
while {[gets $fin line] >= 0} {
    if {[regexp {checking\s+([A-Za-z0-9_]+)\s+\((\d+)\)} $line -> rule cnt]} {
        puts $fp [format "%-40s %s" $rule $cnt]
        incr nline
    }
}
close $fin
puts $fp "# rules_listed=$nline"
close $fp
puts "CHECK_TIMING_SUMMARY:"
set fp [open $ct_sum r]; puts [read $fp]; close $fp

set wns  [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs  [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set fpaths  [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
set tns 0.0
foreach q $fpaths { set tns [expr {$tns + [get_property SLACK $q]}] }
set pw [get_timing_paths -max_paths 1 -nworst 1 -setup]

set fp [open [file join $report result.txt] w]
puts $fp "RESULT io_sta tag=$tag const_io=[expr {$tag eq "io" ? "yes" : "no"}] strategy=[get_property strategy [get_runs impl_1]] wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
puts $fp "PATH start=[get_property STARTPOINT_PIN $pw]"
puts $fp "PATH end=[get_property ENDPOINT_PIN $pw]"
puts $fp "PATH slack=[format %.3f $wns]"
close $fp
puts "RESULT io_sta tag=$tag wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
puts "IO_STA_$tag COMPLETE"
close_project
