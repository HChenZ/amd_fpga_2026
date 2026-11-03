# Independent experimental overlay, Vivado 2025.2; refuses an existing work directory.
set root [file normalize [file join [file dirname [info script]] ../..]]
set variant direct
if {[info exists ::dma_variant]} {set variant $::dma_variant}
if {$variant ni {direct loopback}} {error "variant must be direct or loopback"}
set work [file join $root build local dma_$variant]
if {[info exists ::dma_work]} {set work [file normalize $::dma_work]}
if {[file exists [file join $work d.xpr]]} {error "Existing experiment: choose a new work directory or explicitly open it"}
if {![string match 2025.2* [version -short]]} {error "Vivado 2025.2 required"}
create_project d $work -part xc7z020clg400-1
set_property target_language Verilog [current_project]
add_files -norecurse [list $root/src/rtl/ascon/ascon_round.v $root/src/rtl/ascon_dma/ascon_aead_multiblock.v $root/src/rtl/ascon_dma/ascon_axis_direct.v $root/src/rtl/ascon_dma/dma_direct_top.v]
create_bd_design d
proc checked_cfg {cell config} {
    set_property -dict $config [get_bd_cells $cell]
    foreach {k v} $config {if {[get_property $k [get_bd_cells $cell]] ne $v} {error "Configuration readback failed: $cell $k"}}
}
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
checked_cfg ps7 [list CONFIG.PCW_USE_M_AXI_GP0 1 CONFIG.PCW_USE_S_AXI_HP0 1 CONFIG.PCW_S_AXI_HP0_DATA_WIDTH 64 CONFIG.PCW_EN_CLK0_PORT 1 CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100]
# Fixed PS pins must remain top ports, even when the running SD image supplies PS configuration.
# Otherwise generated PS pin constraints bind to internal pins (Netlist 29-160).
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma
checked_cfg dma [list CONFIG.c_include_sg 0 CONFIG.c_include_mm2s 1 CONFIG.c_include_s2mm 1 CONFIG.c_m_axi_mm2s_data_width 32 CONFIG.c_m_axi_s2mm_data_width 32 CONFIG.c_m_axis_mm2s_tdata_width 32 CONFIG.c_s_axis_s2mm_tdata_width 32 CONFIG.c_sg_length_width 14 CONFIG.c_include_mm2s_dre 0 CONFIG.c_include_s2mm_dre 0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ctrl
checked_cfg ctrl [list CONFIG.NUM_MI [expr {$variant eq "direct"?2:1}]]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 mem
checked_cfg mem [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 1 CONFIG.XBAR_DATA_WIDTH 64]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one
checked_cfg one [list CONFIG.CONST_VAL 1]
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins ctrl/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl/M00_AXI] [get_bd_intf_pins dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_MM2S] [get_bd_intf_pins mem/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_S2MM] [get_bd_intf_pins mem/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins mem/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]
if {$variant eq "direct"} {
    create_bd_cell -type module -reference dma_direct_top engine
    connect_bd_intf_net [get_bd_intf_pins ctrl/M01_AXI] [get_bd_intf_pins engine/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins dma/M_AXIS_MM2S] [get_bd_intf_pins engine/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins engine/M_AXIS] [get_bd_intf_pins dma/S_AXIS_S2MM]
} else {
    connect_bd_intf_net [get_bd_intf_pins dma/M_AXIS_MM2S] [get_bd_intf_pins dma/S_AXIS_S2MM]
}
set clocks {ps7/M_AXI_GP0_ACLK ps7/S_AXI_HP0_ACLK ctrl/ACLK ctrl/S00_ACLK ctrl/M00_ACLK mem/ACLK mem/S00_ACLK mem/S01_ACLK mem/M00_ACLK dma/s_axi_lite_aclk dma/m_axi_mm2s_aclk dma/m_axi_s2mm_aclk reset/slowest_sync_clk}
set resets {ctrl/ARESETN ctrl/S00_ARESETN ctrl/M00_ARESETN mem/ARESETN mem/S00_ARESETN mem/S01_ARESETN mem/M00_ARESETN dma/axi_resetn}
if {$variant eq "direct"} {lappend clocks ctrl/M01_ACLK engine/clk; lappend resets ctrl/M01_ARESETN engine/rst_n}
foreach pin $clocks {connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins $pin]}
foreach pin $resets {connect_bd_net [get_bd_pins reset/peripheral_aresetn] [get_bd_pins $pin]}
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins reset/ext_reset_in]
connect_bd_net [get_bd_pins one/dout] [get_bd_pins reset/dcm_locked]
assign_bd_address
set_property offset 0x40400000 [get_bd_addr_segs ps7/Data/SEG_dma_Reg]
set_property range 64K [get_bd_addr_segs ps7/Data/SEG_dma_Reg]
if {$variant eq "direct"} {
    set_property offset 0x40000000 [get_bd_addr_segs ps7/Data/SEG_engine_reg0]
    set_property range 4K [get_bd_addr_segs ps7/Data/SEG_engine_reg0]
}
validate_bd_design
save_bd_design
generate_target all [get_files */d.bd]
add_files -norecurse [make_wrapper -files [get_files */d.bd] -top]
set_property top d_wrapper [current_fileset]
update_compile_order -fileset sources_1
set_property strategy Performance_ExploreWithRemap [get_runs impl_1]
set fp [open [file join $work context.txt] w]
puts $fp [version]
puts $fp "part=xc7z020clg400-1 top=d_wrapper variant=$variant fclk_config=100MHz"
foreach c [get_bd_cells -hier] {puts $fp "$c [get_property VLNV $c]"}
foreach c {ps7 dma} {foreach p [list_property [get_bd_cells $c]] {if {[string match CONFIG.* $p]} {puts $fp "$c $p=[get_property $p [get_bd_cells $c]]"}}}
close $fp
puts "DMA_SETUP_PASS $variant $work"
