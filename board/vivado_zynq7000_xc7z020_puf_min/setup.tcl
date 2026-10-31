# PUF-MIN：最小闭环 RO-PUF overlay（PS AXI-Lite -> puf_min_top）。
# 独立工程，绝不打开/修改 PYNQ 主线、baseline、puf_v2 或 pynq_puf 的工程目录。
if {![string match "2025.2*" [version -short]]} {error "Vivado 2025.2 required"}

set root [file normalize [file join [file dirname [info script]] ../..]]
set here [file dirname [info script]]
set work $root/board/vivado_zynq7000_xc7z020_puf_min/work
if {[info exists ::puf_min_work]} {set work [file normalize $::puf_min_work]}
# 批量重跑用环境变量指定新目录，避免覆盖已有实验工程/证据：
#   $env:PUF_MIN_WORK = <新的工程目录>
#   $env:PUF_MIN_OUT  = <新的证据目录>
if {[info exists ::env(PUF_MIN_WORK)] && $::env(PUF_MIN_WORK) ne ""} {
    set work [file normalize $::env(PUF_MIN_WORK)]
}
if {[file exists $work/puf_min.xpr]} {error "Existing project; reopen it explicitly instead of overwriting"}
if {![info exists ::puf_min_out]} {
    if {[info exists ::env(PUF_MIN_OUT)] && $::env(PUF_MIN_OUT) ne ""} {
        set ::puf_min_out [file normalize $::env(PUF_MIN_OUT)]
    } else {
        set ::puf_min_out $root/data/advanced/puf_min/impl_[clock format [clock seconds] -format %Y%m%d_%H%M%S]
    }
}
file mkdir $::puf_min_out
puts "PUF_MIN_PATHS work=$work out=$::puf_min_out"

create_project puf_min $work -part xc7z020clg400-1
# run 级 Tcl 钩子（OPT_DESIGN.TCL.PRE）跑在另一个解释器里，看不到会话里的
# ::puf_min_out，所以把证据目录落成工程内的一个标记文件，由 ring_ack.tcl 读取。
file mkdir $work
set fp [open $work/puf_min_out.txt w]
puts $fp $::puf_min_out
close $fp
set_property target_language Verilog [current_project]
set_param general.maxThreads 2

# ---- RTL 源清单：与 sim/puf_min/sources.json 的 rtl 段保持一致 ----
set f [open $here/sources.txt r]
set src {}
foreach p [split [read $f] \n] {if {$p ne ""} {lappend src $root/$p}}
close $f
add_files -norecurse $src
set_property file_type SystemVerilog [get_files */keys_v2/*.v]
add_files -norecurse [list $root/src/rtl/defines.v]
set_property include_dirs [list $root/src/rtl] [get_filesets sources_1]

# ---- Block design：PS7 单时钟 + 1:1 AXI-Lite ----
create_bd_design puf
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
set psconfig [list \
    CONFIG.PCW_USE_M_AXI_GP0 1 \
    CONFIG.PCW_EN_CLK0_PORT 1 \
    CONFIG.PCW_EN_CLK1_PORT 0 \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100]
set_property -dict $psconfig [get_bd_cells ps7]
foreach {p v} $psconfig {if {[get_property $p [get_bd_cells ps7]] != $v} {error "PS readback mismatch $p"}}
# 必须导出 PS 专用引脚接口：否则生成 XDC 会把 IOSTANDARD/PACKAGE_PIN/slew
# 施加到内部 pin，产生 CRITICAL WARNING [Netlist 29-160]（puf_v2 的教训）。
# overlay 模式：DDR/MIO 启动配置仍由 vendor SD image 提供。
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
if {[llength [get_bd_intf_ports -quiet -filter {NAME =~ "FIXED_IO*"}]] == 0} {error "FIXED_IO not exported"}
if {[llength [get_bd_intf_ports -quiet -filter {NAME =~ "DDR*"}]] == 0} {error "DDR not exported"}

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi
set_property CONFIG.NUM_MI 1 [get_bd_cells axi]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one
set_property CONFIG.CONST_VAL 1 [get_bd_cells one]

create_bd_cell -type module -reference puf_min_top puf_core
if {[llength [get_bd_intf_pins -quiet puf_core/S_AXI]] != 1} {error "puf_core S_AXI not inferred"}
foreach pin {puf_core/clk puf_core/rst_n} {
    if {[llength [get_bd_pins -quiet $pin]] != 1} {error "Missing $pin"}
}

connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi/M00_AXI] [get_bd_intf_pins puf_core/S_AXI]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK] \
    [get_bd_pins axi/ACLK] [get_bd_pins axi/S00_ACLK] [get_bd_pins axi/M00_ACLK] \
    [get_bd_pins reset/slowest_sync_clk] [get_bd_pins puf_core/clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins reset/ext_reset_in]
connect_bd_net [get_bd_pins one/dout] [get_bd_pins reset/dcm_locked]
connect_bd_net [get_bd_pins reset/peripheral_aresetn] [get_bd_pins axi/ARESETN] \
    [get_bd_pins axi/S00_ARESETN] [get_bd_pins axi/M00_ARESETN] [get_bd_pins puf_core/rst_n]

assign_bd_address
set_property offset 0x40000000 [get_bd_addr_segs ps7/Data/SEG_puf_core_reg0]
set_property range 4K [get_bd_addr_segs ps7/Data/SEG_puf_core_reg0]

validate_bd_design
save_bd_design
set bd [get_files */puf.bd]
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
set_property top puf_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

# 物理环阵列：在 opt_design 之前确认环反馈网并加 RO pblock（网表在此之后才存在）。
set_property STEPS.OPT_DESIGN.TCL.PRE $here/ring_ack.tcl [get_runs impl_1]

# ---- 上下文记录 ----
set fp [open $::puf_min_out/context.txt w]
puts $fp [version]
puts $fp "part=xc7z020clg400-1 top=puf_wrapper fclk0_mhz=100 clock_ports=1 (single clock; RO rings are asynchronous, no RO clock defined)"
puts $fp "overlay_ps_boot=vendor SD image keeps DDR/MIO configuration; PL exports FIXED_IO and DDR"
foreach ip [get_ips] {puts $fp "$ip [get_property IPDEF $ip]"}
puts $fp "ps_readback PCW_FPGA0_PERIPHERAL_FREQMHZ=[get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells ps7]]"
close $fp
puts "PUF_MIN_SETUP_READY out=$::puf_min_out"
