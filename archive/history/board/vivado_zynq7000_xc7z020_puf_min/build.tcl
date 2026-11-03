# PUF-MIN 完整离线流程：setup -> synth -> route（**不跑 phys_opt_design**）-> 门禁 -> bit
#
# 门禁逻辑在 gate.tcl，可单独对已完成 route 的工程重跑（见 data/advanced/puf_min/retry_impl.tcl）。
# 实现门限：WNS >= +0.5ns、WHS >= 0、DRC Error = 0、Netlist 29-160 = 0、
#           DDR*/FIXED_IO* 顶层端口存在、RO LUT = 1280 且全在 pb_ro_puf。
set here [file dirname [file normalize [info script]]]
source $here/setup.tcl
# 用工程目录而不是硬编码 work：支持 ::puf_min_work / PUF_MIN_WORK 指向新的实验目录。
set work [file normalize [get_property DIRECTORY [current_project]]]

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis incomplete"}
puts "PUF_MIN_SYNTH_OK"

launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Route incomplete: [get_property STATUS [get_runs impl_1]]"
}
source $here/gate.tcl
