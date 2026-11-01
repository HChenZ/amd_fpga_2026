# 从已实现的 run 里导出"STA 实际吃到的约束"，作为签核证据（不重跑 P&R）。
# io 变体在 build/local/ist_i（短路径，避开 Windows 260 字符限制）；
# 对照组在 build/local/io_sta_20261027/pin_root（钉住源快照）。
set R C:/wenjian/game/FPGA2026/ours/amd_fpga_2026
set pairs [list \
    [list io   [file join $R build local ist_i board x rvp riscv_vivado_project.xpr]] \
    [list noio [file join $R build local io_sta_20261027 pin_root board vivado_zynq7000_xc7z020_ascon riscv_vivado_project riscv_vivado_project.xpr]] ]
foreach pair $pairs {
    set tag  [lindex $pair 0]
    set proj [lindex $pair 1]
    set out  [file join $R build reports io_sta_20261027 $tag applied_constraints.xdc]
    if {![file exists $proj]} { error "missing project for $tag: $proj" }
    open_project $proj
    open_run impl_1 -name impl_1
    write_xdc -force -file $out
    report_clocks -file [file join [file dirname $out] clocks.rpt]
    puts "COLLECT $tag -> $out"
    close_project
}
puts COLLECT_DONE
