# Independent diagnostic STRUCTURAL candidate. No edits to the released overlay.
set root [file normalize [file join [file dirname [info script]] ../..]]
set out $root/data/advanced/puf_soc
set work $root/board/vivado_zynq7000_xc7z020_puf_v2/work
set coe $out/firmware/puf_v2.coe
if {![file exists $coe]} {error "Run prepare.py first"}
if {![info exists ::puf_diagnostic]} {set ::puf_diagnostic 0}
if {$::puf_diagnostic ni {0 1}} {error "puf_diagnostic must be 0 or 1"}
create_project puf_soc $work -part xc7z020clg400-1
set_param general.maxThreads 2
set_property target_language Verilog [current_project]
set f [open $root/board/vivado_zynq7000_xc7z020_puf_v2/sources.txt r]
foreach p [split [read $f] \n] {if {$p ne ""} {add_files -norecurse $root/$p}}
close $f
add_files -norecurse [list $root/src/rtl/defines.v $root/src/rtl/ascon/ascon_constants.vh]
set_property include_dirs [list $root/src/rtl $root/src/rtl/ascon] [get_filesets sources_1]
set_property file_type SystemVerilog [get_files */ascon/*.v]
set_property file_type SystemVerilog [get_files */keys_v2/*.v]
set ipbase $root/board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/riscv_vivado_project.srcs/sources_1/ip
foreach ip {axi_bram_ctrl_0 blk_mem_gen_0} {import_ip -files $ipbase/$ip/$ip.xci}
foreach ip [get_ips] {if {[get_property IS_LOCKED $ip]} {upgrade_ip $ip}}
set_property CONFIG.Coe_File $coe [get_ips blk_mem_gen_0]
foreach f [get_files -all -quiet *.coe] {if {[file normalize $f] ne [file normalize $coe]} {remove_files $f}}
generate_target all [get_ips]
create_bd_design puf
# Reuse verified PYNQ PS/GPIO-free overlay topology. No DDR/MIO preset replacement.
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
set psconfig [list CONFIG.PCW_USE_M_AXI_GP0 1 CONFIG.PCW_EN_CLK0_PORT 1 CONFIG.PCW_EN_CLK1_PORT 1 CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100 CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ 25]
set_property -dict $psconfig [get_bd_cells ps7]
foreach {p v} $psconfig {if {[get_property $p [get_bd_cells ps7]] != $v} {error "PS readback mismatch $p"}}
foreach pin {FCLK_CLK0 FCLK_CLK1 M_AXI_GP0_ACLK} {if {[llength [get_bd_pins ps7/$pin]]!=1} {error "Missing $pin"}}
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi
set_property CONFIG.NUM_MI 2 [get_bd_cells axi]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one
set_property CONFIG.CONST_VAL 1 [get_bd_cells one]
foreach {m n} {pynq_ctl control pynq_mbox mailbox pynq_puf_soc_v2 soc} {create_bd_cell -type module -reference $m $n}
# Distinct identity; VERSION bit8 is helper-disclosing DIAGNOSTIC ABI.
set_property -dict [list CONFIG.ID_VALUE 0x32554650 CONFIG.VERSION_VALUE [expr {2+256*$::puf_diagnostic}]] [get_bd_cells control]
set_property CONFIG.DIAGNOSTIC $::puf_diagnostic [get_bd_cells soc]
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi/M00_AXI] [get_bd_intf_pins control/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi/M01_AXI] [get_bd_intf_pins mailbox/S_AXI]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK] [get_bd_pins axi/ACLK] [get_bd_pins axi/S00_ACLK] [get_bd_pins axi/M00_ACLK] [get_bd_pins axi/M01_ACLK] [get_bd_pins reset/slowest_sync_clk] [get_bd_pins control/clk] [get_bd_pins mailbox/clk] [get_bd_pins soc/clk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins soc/ro_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins reset/ext_reset_in]
connect_bd_net [get_bd_pins one/dout] [get_bd_pins reset/dcm_locked]
connect_bd_net [get_bd_pins reset/peripheral_aresetn] [get_bd_pins axi/ARESETN] [get_bd_pins axi/S00_ARESETN] [get_bd_pins axi/M00_ARESETN] [get_bd_pins axi/M01_ARESETN] [get_bd_pins control/rst_n] [get_bd_pins mailbox/rst_n] [get_bd_pins soc/rst_n]
foreach {a b} {control/soc_reset mailbox/link_flush control/soc_rst_n soc/soc_rst_n control/soc_button soc/button soc/led control/soc_led mailbox/mbox_txd soc/uart_rxd soc/uart_txd mailbox/mbox_rxd} {connect_bd_net [get_bd_pins $a] [get_bd_pins $b]}
assign_bd_address
foreach {seg offset} {control 0x40000000 mailbox 0x40001000} {
    set_property offset $offset [get_bd_addr_segs ps7/Data/SEG_${seg}_reg0]
    set_property range 4K [get_bd_addr_segs ps7/Data/SEG_${seg}_reg0]
}
validate_bd_design
save_bd_design
set bd [get_files */puf.bd]
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
set_property top puf_wrapper [get_filesets sources_1]
set_property STEPS.OPT_DESIGN.TCL.PRE $root/board/vivado_zynq7000_xc7z020_puf_v2/ring_ack.tcl [get_runs impl_1]
update_compile_order -fileset sources_1
set fp [open $out/context.txt w]
puts $fp [version]
puts $fp "part=xc7z020clg400-1 top=puf_wrapper core=100MHz management=25MHz diagnostic=$::puf_diagnostic coe=$coe"
puts $fp "RO minimum period NOT_MEASURED. No RO clocks or blanket timing exceptions. Structural candidate only."
foreach ip [get_ips] {puts $fp "$ip [get_property IPDEF $ip]"}
close $fp
puts "PUF_SOC_SETUP_READY"
