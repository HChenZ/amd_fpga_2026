# Independent experimental CPU DMA overlay. No release/baseline project is opened.
set root [file normalize [file join [file dirname [info script]] ../..]]
set work [file join $root build local dma_cpu]
if {[info exists ::cpu_dma_work]} {set work [file normalize $::cpu_dma_work]}
set mhz 100
if {[info exists ::cpu_dma_mhz]} {set mhz $::cpu_dma_mhz}
set resume [expr {[info exists ::cpu_dma_resume] && $::cpu_dma_resume}]
if {[file exists $work/cpu_dma.xpr] && !$resume} {error "Existing experiment; explicitly reopen it instead of overwriting"}
if {![string match 2025.2* [version -short]]} {error "Vivado 2025.2 required"}
set coe $root/build/local/pynq_dma_svc/dma_svc.coe
if {![file exists $coe]} {error "Build real DMA service firmware first"}
if {!$resume} {
create_project cpu_dma $work -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set src {}
foreach f [glob $root/src/rtl/*.v] {
    if {[file tail $f] ni {top.v top_pl_bram.v soc_top.v bus_interconnect.v}} {lappend src $f}
}
foreach f {ascon_aead_2.v ascon_aead_core.v ascon_ise.v ascon_permutation.v ascon_round.v ascon_word.v crypto_aead.v} {lappend src $root/src/rtl/ascon/$f}
lappend src $root/board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v
foreach f {bus_interconnect_dma.v soc_top_dma.v dma_cpu_endpoint.v dma_control.v} {lappend src $root/src/rtl/pynq_dma_cpu/$f}
foreach f {pynq_dma_cpu.v dma_private_bram.v} {lappend src $root/board/vivado_zynq7000_xc7z020_pynq_dma_cpu/$f}
add_files -norecurse $src
add_files -norecurse [glob $root/src/rtl/ascon/*.vh]
set_property include_dirs [list $root/src/rtl $root/src/rtl/ascon] [get_filesets sources_1]
foreach f {ascon_word.v crypto_aead.v ascon_aead_2.v} {set_property file_type SystemVerilog [get_files */$f]}
set_property file_type {Verilog Header} [get_files */defines.v]
set ipbase $root/board/vivado_zynq7000_xc7z020_baseline/riscv_vivado_project.srcs/sources_1/ip
foreach ip {axi_bram_ctrl_0 blk_mem_gen_0} {import_ip -files $ipbase/$ip/$ip.xci}
foreach ip [get_ips] {if {[get_property IS_LOCKED $ip]} {upgrade_ip $ip}}
} elseif {![string equal -nocase [file normalize [get_property DIRECTORY [current_project]]] $work]} {error "Resume project directory mismatch"}
set_property CONFIG.Coe_File $coe [get_ips blk_mem_gen_0]
set coe_read [get_property CONFIG.Coe_File [get_ips blk_mem_gen_0]]
if {[file pathtype $coe_read] ne "absolute"} {set coe_read [file join [get_property IP_DIR [get_ips blk_mem_gen_0]] $coe_read]}
if {![string equal -nocase [file normalize $coe_read] [file normalize $coe]]} {error "Firmware COE readback failed: $coe_read"}
foreach f [get_files -all *.coe] {if {[file normalize $f] ne [file normalize $coe]} {remove_files $f}}
generate_target all [get_ips]
create_bd_design cpu_dma
if {[info exists ::cpu_ipcfg_lib]} {
    if {![llength [info commands ipcfg::python_status]]} {source -notrace $::cpu_ipcfg_lib}
    set ::ipcfg::native_log_path $::cpu_native_log
    set ps [ipcfg::python_status]
    if {![string match {PYTHON:OK *} $ps]} {error $ps}
    puts $ps
    puts [ipcfg::python_exec -c {import argparse, base64, hashlib, json, pathlib, re, sys, typing; print("PYTHON_IMPORTS:OK")}]
}
proc cpu_checked_cfg {cell config} {
    if {[llength [info commands ipcfg::capture]]} {
        set evidence [file join [get_property DIRECTORY [current_project]] config_evidence]
        file mkdir $evidence
        set receipt [ipcfg::capture [file normalize [file join $evidence $cell.[clock clicks].tcldict]] [list set_property -dict $config [get_bd_cells $cell]]]
        if {[dict get $receipt status] ne "OK"} {error "IP configuration capture failed: $receipt"}
    } else {set_property -dict $config [get_bd_cells $cell]}
    foreach {k v} $config {if {[get_property $k [get_bd_cells $cell]] ne $v} {error "Configuration readback failed: $cell $k"}}
}
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
cpu_checked_cfg ps7 [list CONFIG.PCW_USE_M_AXI_GP0 1 CONFIG.PCW_USE_S_AXI_HP0 1 CONFIG.PCW_S_AXI_HP0_DATA_WIDTH 64 CONFIG.PCW_EN_CLK0_PORT 1 CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $mhz]
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
# Overlay only: vendor SD image retains DDR/MIO boot configuration, as existing PYNQ.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma
cpu_checked_cfg dma [list CONFIG.c_include_sg 0 CONFIG.c_include_mm2s 1 CONFIG.c_include_s2mm 1 CONFIG.c_m_axi_mm2s_data_width 32 CONFIG.c_m_axi_s2mm_data_width 32 CONFIG.c_m_axis_mm2s_tdata_width 32 CONFIG.c_s_axis_s2mm_tdata_width 32 CONFIG.c_sg_length_width 14 CONFIG.c_include_mm2s_dre 0 CONFIG.c_include_s2mm_dre 0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ctrl
cpu_checked_cfg ctrl [list CONFIG.NUM_MI 2]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 mem
cpu_checked_cfg mem [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 1 CONFIG.XBAR_DATA_WIDTH 64]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one
cpu_checked_cfg one [list CONFIG.CONST_VAL 1]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 zero2
cpu_checked_cfg zero2 [list CONFIG.CONST_WIDTH 2 CONFIG.CONST_VAL 0]
create_bd_cell -type module -reference pynq_dma_cpu engine
create_bd_cell -type module -reference dma_private_bram private_bram
foreach interface {engine/S_AXI engine/M_AXI engine/S_AXIS engine/M_AXIS private_bram/S_AXI} {
    if {[llength [get_bd_intf_pins $interface]]!=1} {error "Missing inferred interface $interface"}
}
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins ctrl/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl/M00_AXI] [get_bd_intf_pins dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ctrl/M01_AXI] [get_bd_intf_pins engine/S_AXI]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_MM2S] [get_bd_intf_pins mem/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_S2MM] [get_bd_intf_pins mem/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins mem/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXIS_MM2S] [get_bd_intf_pins engine/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins engine/M_AXIS] [get_bd_intf_pins dma/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins engine/M_AXI] [get_bd_intf_pins private_bram/S_AXI]
set clocks {ps7/M_AXI_GP0_ACLK ps7/S_AXI_HP0_ACLK ctrl/ACLK ctrl/S00_ACLK ctrl/M00_ACLK ctrl/M01_ACLK mem/ACLK mem/S00_ACLK mem/S01_ACLK mem/M00_ACLK dma/s_axi_lite_aclk dma/m_axi_mm2s_aclk dma/m_axi_s2mm_aclk reset/slowest_sync_clk engine/clk private_bram/clk}
set resets {ctrl/ARESETN ctrl/S00_ARESETN ctrl/M00_ARESETN ctrl/M01_ARESETN mem/ARESETN mem/S00_ARESETN mem/S01_ARESETN mem/M00_ARESETN dma/axi_resetn engine/rst_n}
foreach pin $clocks {connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins $pin]}
foreach pin $resets {connect_bd_net [get_bd_pins reset/peripheral_aresetn] [get_bd_pins $pin]}
connect_bd_net [get_bd_pins engine/cpu_resetn] [get_bd_pins private_bram/rst_n]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins reset/ext_reset_in]
connect_bd_net [get_bd_pins one/dout] [get_bd_pins reset/dcm_locked] [get_bd_pins engine/uart_rxd]
connect_bd_net [get_bd_pins zero2/dout] [get_bd_pins engine/button]
assign_bd_address
set_property offset 0x40400000 [get_bd_addr_segs ps7/Data/SEG_dma_Reg]
set_property range 64K [get_bd_addr_segs ps7/Data/SEG_dma_Reg]
set_property offset 0x40000000 [get_bd_addr_segs ps7/Data/SEG_engine_reg0]
set_property range 4K [get_bd_addr_segs ps7/Data/SEG_engine_reg0]
set private_seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces engine/M_AXI]]
set_property range 128K $private_seg
set_property offset 0x10000000 $private_seg
validate_bd_design
save_bd_design
source -notrace $root/build/advanced/cpu_dma_finish_setup.tcl
