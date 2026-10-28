# Vivado 2025.2, standalone overlay; never opens or modifies frozen projects.
if {![string match "2025.2*" [version -short]]} {error "Vivado 2025.2 required"}
set root [file normalize [file join [file dirname [info script]] ../..]]
set work [file join $root build local pynq_final vivado]
set coe [file join $root build local pynq_svc pynq_svc.coe]
if {![file exists $coe]} {error "Build pynq_svc first"}
create_project pynq_overlay $work -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
set src {}
foreach f [glob $root/src/rtl/*.v] {
 if {[file tail $f] ni {top_pl_bram.v soc_top.v}} {lappend src $f}
}
foreach f {soc_top.v ascon_mmio.v} {lappend src $root/board/vivado_zynq7000_xc7z020_pynq/rtl_p0/$f}
foreach f {ascon_aead_2.v ascon_aead_core.v ascon_ise.v ascon_permutation.v ascon_round.v ascon_word.v crypto_aead.v} {lappend src $root/src/rtl/ascon/$f}
foreach f [glob $root/src/rtl/pynq/*.v] {lappend src $f}
add_files -norecurse $src
add_files -norecurse [glob $root/src/rtl/ascon/*.vh]
set_property include_dirs [list $root/src/rtl $root/src/rtl/ascon] [get_filesets sources_1]
set_property file_type SystemVerilog [get_files */ascon_word.v]
set_property file_type {Verilog Header} [get_files */defines.v]
set ipbase $root/board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/riscv_vivado_project.srcs/sources_1/ip
foreach ip {axi_bram_ctrl_0 blk_mem_gen_0} {import_ip -files $ipbase/$ip/$ip.xci}
foreach ip [get_ips] {if {[get_property IS_LOCKED $ip]} {upgrade_ip $ip}}
set_property CONFIG.Coe_File $coe [get_ips blk_mem_gen_0]
# import_ip also imports the old init-file dependency; remove that stale file.
foreach f [get_files -all -quiet *.coe] {
 if {[file normalize $f] ne [file normalize $coe]} {remove_files $f}
}
generate_target all [get_ips]
create_bd_design pynq
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}] [get_bd_cells ps7]
# Overlay only: PS DDR/MIO boot configuration remains supplied by vendor SD image.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi
set_property CONFIG.NUM_MI 2 [get_bd_cells axi]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one
set_property CONFIG.CONST_VAL 1 [get_bd_cells one]
foreach m {pynq_ctl pynq_mbox pynq_soc} {create_bd_cell -type module -reference $m ${m}_0}
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi/M00_AXI] [get_bd_intf_pins pynq_ctl_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi/M01_AXI] [get_bd_intf_pins pynq_mbox_0/S_AXI]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK] [get_bd_pins axi/ACLK] [get_bd_pins axi/S00_ACLK] [get_bd_pins axi/M00_ACLK] [get_bd_pins axi/M01_ACLK] [get_bd_pins reset/slowest_sync_clk] [get_bd_pins pynq_ctl_0/clk] [get_bd_pins pynq_mbox_0/clk] [get_bd_pins pynq_soc_0/clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins reset/ext_reset_in]
connect_bd_net [get_bd_pins one/dout] [get_bd_pins reset/dcm_locked]
connect_bd_net [get_bd_pins reset/peripheral_aresetn] [get_bd_pins axi/ARESETN] [get_bd_pins axi/S00_ARESETN] [get_bd_pins axi/M00_ARESETN] [get_bd_pins axi/M01_ARESETN] [get_bd_pins pynq_ctl_0/rst_n] [get_bd_pins pynq_mbox_0/rst_n] [get_bd_pins pynq_soc_0/rst_n]
foreach {a b} {pynq_ctl_0/soc_reset pynq_mbox_0/link_flush pynq_ctl_0/soc_rst_n pynq_soc_0/soc_rst_n pynq_ctl_0/soc_button pynq_soc_0/button pynq_soc_0/led pynq_ctl_0/soc_led pynq_mbox_0/mbox_txd pynq_soc_0/uart_rxd pynq_soc_0/uart_txd pynq_mbox_0/mbox_rxd} {connect_bd_net [get_bd_pins $a] [get_bd_pins $b]}
assign_bd_address
set_property offset 0x40000000 [get_bd_addr_segs ps7/Data/SEG_pynq_ctl_0_reg0]
set_property range 4K [get_bd_addr_segs ps7/Data/SEG_pynq_ctl_0_reg0]
set_property offset 0x40001000 [get_bd_addr_segs ps7/Data/SEG_pynq_mbox_0_reg0]
set_property range 4K [get_bd_addr_segs ps7/Data/SEG_pynq_mbox_0_reg0]
validate_bd_design
save_bd_design
set bd [get_files */pynq.bd]
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
set_property top pynq_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
set fp [open $work/context.txt w]
puts $fp [version]
puts $fp "part=xc7z020clg400-1 top=pynq_wrapper FCLK0=100MHz coe=$coe"
puts $fp "source_head=[exec git -C $root rev-parse HEAD]"
foreach ip [get_ips] {puts $fp "$ip [get_property IPDEF $ip]"}
close $fp
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "synthesis failed"}
set_property strategy Performance_ExploreWithRemap [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "implementation failed"}
open_run impl_1
report_timing_summary -file $work/timing.rpt
report_drc -file $work/drc.rpt
report_utilization -file $work/utilization.rpt
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {error "setup timing failed; do not release"}
if {[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]] < 0} {error "hold timing failed; do not release"}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]]} {error "DRC release gate failed"}
set release $root/board/vivado_zynq7000_xc7z020_pynq/release
file mkdir $release
file copy -force $work/pynq_overlay.runs/impl_1/pynq_wrapper.bit $release/pynq.bit
file copy -force $work/pynq_overlay.gen/sources_1/bd/pynq/hw_handoff/pynq.hwh $release/pynq.hwh
puts "PYNQ_BUILD_PASS"
