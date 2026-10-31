# 重跑 impl_1 + 门禁：合成网表不变，只修了 OPT_DESIGN.TCL.PRE 钩子里 pblock cell 的
# 解析方式（不再写死 */puf_core/bank，改为从 ring 门单元名反推 bank 层次）。
# 不新建工程、不重新综合。
set root [file normalize [file join [file dirname [info script]] ../../..]]
set board $root/board/vivado_zynq7000_xc7z020_puf_min
open_project $board/work_v2/puf_min.xpr

set ::puf_min_out $root/data/advanced/puf_min/impl_[clock format [clock seconds] -format %Y%m%d_%H%M%S]
file mkdir $::puf_min_out
# 钩子跑在独立解释器里，用工程内的标记文件传证据目录
set fp [open $board/work_v2/puf_min_out.txt w]
puts $fp $::puf_min_out
close $fp

reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Route incomplete: [get_property STATUS [get_runs impl_1]]"
}
source $board/gate.tcl
