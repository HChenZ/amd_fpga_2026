# PUF-MIN 的 XSim 回归：只允许在 puf_min 自己的工程里跑（不碰 puf_v2 / pynq / baseline）。
# 行为级 RO 模型 (sim/puf_soc_v2/ro_array_model.sv) 在仿真里整替换 ro_array_v2，
# 因此必须把综合用的 ro_array_v2.v 排除在仿真编译之外。
set root [file normalize [file join [file dirname [info script]] ../..]]
set work $root/board/vivado_zynq7000_xc7z020_puf_min/work
if {[llength [get_property DIRECTORY [current_project]]] == 0} {error "No project open"}
if {[file normalize [get_property DIRECTORY [current_project]]] ne [file normalize $work]} {
    error "Wrong project: [get_property DIRECTORY [current_project]]"
}

set out $root/data/advanced/puf_min/xsim_[clock format [clock seconds] -format %Y%m%d_%H%M%S]
file mkdir $out

set_property used_in_simulation false [get_files */keys_v2/ro_array_v2.v]
add_files -fileset sim_1 -norecurse [list \
    $root/sim/puf_soc_v2/ro_array_model.sv \
    $root/sim/keys/DNA_PORT_sim.v \
    $root/sim/puf_min/axi_lite_bfm.sv \
    $root/sim/puf_min/tb_puf_min.sv \
    $root/sim/puf_min/tb_ro_core_single_clock.sv]
set_property target_simulator XSim [current_project]
set_property file_type SystemVerilog [get_files */keys_v2/*.v]
set_property include_dirs [list $root/src/rtl] [get_filesets sim_1]
set_property xsim.simulate.runtime 20ms [get_filesets sim_1]

# {label top defines pass_marker}
set cases {
    {regs_fast        tb_puf_min              {}              "TEST_PASS tb_puf_min"}
    {regs_prod        tb_puf_min              {PROD_PARAMS}   "TEST_PASS tb_puf_min"}
    {e1_single_clock  tb_ro_core_single_clock {}              "TEST_PASS tb_ro_core_single_clock"}
}
foreach case $cases {
    lassign $case label top defines marker
    set_property verilog_define [list {*}$defines] [get_filesets sim_1]
    set_property top $top [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -mode behavioral -simset sim_1
    set d $work/puf_min.sim/sim_1/behav/xsim
    file mkdir $out/$label
    foreach f [glob -nocomplain $d/*.log $d/*.tcl $d/*.bat $d/*.prj] {
        file copy $f $out/$label/[file tail $f]
    }
    set fp [open $d/simulate.log r]; set log [read $fp]; close $fp
    close_sim
    if {[string first $marker $log] < 0} {
        error "XSim functional failure in $label: $out/$label"
    }
    puts "XSIM_CASE_PASS $label"
}
set fp [open $out/result.txt w]
puts $fp "PASS regs_fast, regs_prod, e1_single_clock; modeled RO array and DNA_PORT; board NOT_MEASURED; [version -short]"
close $fp
puts "PUF_MIN_XSIM_PASS $out"
