# Finish a validated CPU DMA BD; also used after recorded first-build corrections.
set root [file normalize [file join [file dirname [info script]] ../..]]
set work [get_property DIRECTORY [current_project]]
set coe $root/build/local/pynq_dma_svc/dma_svc.coe
set mhz [get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells ps7]]
set actual_mhz [get_property CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells ps7]]
set pin_hz [get_property CONFIG.FREQ_HZ [get_bd_pins ps7/FCLK_CLK0]]
if {abs(double($actual_mhz)-double($mhz))>0.000001 || $pin_hz!=round(double($mhz)*1000000)} {error "FCLK request/readback mismatch: requested=$mhz actual=$actual_mhz pin_hz=$pin_hz"}
foreach interface {engine/M_AXI private_bram/S_AXI dma/M_AXI_MM2S dma/M_AXI_S2MM} {
    if {[get_property CONFIG.DATA_WIDTH [get_bd_intf_pins $interface]]!=32} {error "Native AXI width mismatch: $interface"}
}
if {[get_property CONFIG.PROTOCOL [get_bd_intf_pins engine/M_AXI]] ne "AXI4"} {error "CPU AXI inference failed"}
if {[get_property CONFIG.DATA_WIDTH [get_bd_intf_pins ps7/S_AXI_HP0]]!=64} {error "HP0 width mismatch"}
if {[get_property CONFIG.XBAR_DATA_WIDTH [get_bd_cells mem]]!=64} {error "Memory crossbar width mismatch"}
foreach interface {dma/M_AXIS_MM2S dma/S_AXIS_S2MM engine/S_AXIS engine/M_AXIS} {
    if {[get_property CONFIG.TDATA_NUM_BYTES [get_bd_intf_pins $interface]]!=4} {error "Stream width mismatch: $interface"}
}
if {[get_property CONFIG.Write_Depth_A [get_ips blk_mem_gen_0]]!=32768} {error "BRAM depth mismatch"}
set fp [open $work/context.txt w]
puts $fp [version]
puts $fp "part=xc7z020clg400-1 top=cpu_dma_wrapper configured_fclk_mhz=$mhz coe=$coe board=NOT_RUN"
puts $fp "actual_fclk_mhz=$actual_mhz clock_pin_hz=$pin_hz"
foreach c [get_bd_cells -hier] {puts $fp "$c [get_property VLNV $c]"}
foreach c {ps7 dma mem engine private_bram} {
    foreach p [list_property [get_bd_cells $c]] {if {[string match CONFIG.* $p]} {puts $fp "$c $p=[get_property $p [get_bd_cells $c]]"}}
}
foreach ip {axi_bram_ctrl_0 blk_mem_gen_0} {
    puts $fp "ip $ip [get_property IPDEF [get_ips $ip]]"
    foreach p [list_property [get_ips $ip]] {if {[string match CONFIG.* $p]} {puts $fp "$ip $p=[get_property $p [get_ips $ip]]"}}
}
foreach interface {engine/M_AXI private_bram/S_AXI dma/M_AXI_MM2S dma/M_AXI_S2MM dma/M_AXIS_MM2S dma/S_AXIS_S2MM ps7/S_AXI_HP0} {
    puts $fp "interface $interface"
    foreach p [list_property [get_bd_intf_pins $interface]] {if {[string match CONFIG.* $p]} {puts $fp "$p=[get_property $p [get_bd_intf_pins $interface]]"}}
}
foreach seg [get_bd_addr_segs -hier] {puts $fp "address $seg offset=[get_property OFFSET $seg] range=[get_property RANGE $seg]"}
close $fp
generate_target all [get_files */cpu_dma.bd]
add_files -norecurse [make_wrapper -files [get_files */cpu_dma.bd] -top]
set_property top cpu_dma_wrapper [current_fileset]
update_compile_order -fileset sources_1
set_property strategy Performance_ExploreWithRemap [get_runs impl_1]
set fp [open $work/source_files.txt w]
foreach f [get_files -all] {puts $fp [file normalize $f]}
foreach f [glob $root/board/vivado_zynq7000_xc7z020_pynq_dma_cpu/*] {if {[file isfile $f]} {puts $fp $f}}
foreach f [glob $root/src/firmware/pynq_dma_svc/*] {if {[file isfile $f]} {puts $fp $f}}
puts $fp $coe
close $fp
puts "CPU_DMA_SETUP_PASS native_AXI=32 stream=32 HP=64 private_BRAM=128KiB FCLK_MHz=$mhz $work"
