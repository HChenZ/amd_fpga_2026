# 重跑 impl_1：100MHz 下 WNS 只有 +0.121ns，未达 +0.5ns 门禁。
# 关键路径在 ro_puf_core_v2 内部（snapshot -> 20-bit compare -> 128 输入的 health[5]
# 归约 -> result），数据路径 9.476ns 里 74.5% 是布线。这里只改 place/route 指令
# （不加时序例外、不跑 post-route phys_opt_design），试图压缩布线延迟。
set root [file normalize [file join [file dirname [info script]] ../../..]]
set board $root/board/vivado_zynq7000_xc7z020_puf_min
open_project $board/work_v2/puf_min.xpr

set ::puf_min_out $root/data/advanced/puf_min/impl_[clock format [clock seconds] -format %Y%m%d_%H%M%S]
file mkdir $::puf_min_out
set fp [open $board/work_v2/puf_min_out.txt w]
puts $fp $::puf_min_out
close $fp

# 只改布局/布线指令；保持默认的 post-place phys_opt（标准实现步骤），
# 流程仍停在 route_design，因此没有 post-route phys_opt。
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Route incomplete: [get_property STATUS [get_runs impl_1]]"
}
source $board/gate.tcl
