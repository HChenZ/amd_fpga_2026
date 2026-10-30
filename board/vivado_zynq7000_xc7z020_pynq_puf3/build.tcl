# pynq_puf3: PYNQ overlay = three-mode SW/HW(MMIO)/ISE service + PUF v1, Vivado 2025.2.
# Independent entry: never opens or overwrites the PYNQ release, pynq_puf or the JTAG project.
#   vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf3/build.tcl -notrace [-tclargs <strategy> <jobs>]
# Prerequisite: python -X utf8 src/firmware/pynq_svc_puf/build.py
if {![string match "2025.2*" [version -short]]} {error "Vivado 2025.2 required"}
set root  [file normalize [file join [file dirname [info script]] ../..]]
set board [file join $root board vivado_zynq7000_xc7z020_pynq_puf3]
set work  [file join $root build local pynq_puf3 vivado]
set rep   [file join $work reports]
set strategy [expr {[llength $argv] > 0 ? [lindex $argv 0] : "Performance_ExtraTimingOpt"}]
set jobs     [expr {[llength $argv] > 1 ? [lindex $argv 1] : 4}]
set coe [file join $root build local pynq_svc_puf pynq_svc_puf.coe]
if {![file exists $coe]} {error "Missing $coe; run src/firmware/pynq_svc_puf/build.py first"}
if {[file exists [file join $work pynq_puf3.xpr]]} {error "Existing project $work; remove it explicitly before a fresh build"}
file mkdir $rep

create_project pynq_puf3 $work -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set src {}
# Variant soc_top.v / key_mmio.v (no automatic hardware-key latch) replace the src/rtl copies.
foreach f [glob $root/src/rtl/*.v] {if {[file tail $f] ni {top_pl_bram.v soc_top.v}} {lappend src $f}}
foreach f [glob $root/src/rtl/ascon/*.v] {if {![string match *_tb.v $f]} {lappend src $f}}
foreach f [glob $root/src/rtl/keys/*.v] {if {[file tail $f] ne "key_mmio.v"} {lappend src $f}}
foreach f [glob $root/src/rtl/pynq/*.v] {lappend src $f}
foreach f {soc_top.v key_mmio.v} {lappend src [file join $board rtl $f]}
add_files -norecurse $src
add_files -norecurse [glob $root/src/rtl/ascon/*.vh]
set_property include_dirs [list $root/src/rtl $root/src/rtl/ascon] [get_filesets sources_1]
set_property file_type SystemVerilog [get_files */ascon_word.v]
set_property file_type {Verilog Header} [get_files */defines.v]
set ipbase $root/board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/riscv_vivado_project.srcs/sources_1/ip
foreach ip {axi_bram_ctrl_0 blk_mem_gen_0} {import_ip -files $ipbase/$ip/$ip.xci}
foreach ip [get_ips] {if {[get_property IS_LOCKED $ip]} {upgrade_ip $ip}}
set_property CONFIG.Coe_File $coe [get_ips blk_mem_gen_0]
foreach f [get_files -all -quiet *.coe] {if {[file normalize $f] ne [file normalize $coe]} {remove_files $f}}
generate_target all [get_ips]

create_bd_design pynq_puf3
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
set psconfig [list CONFIG.PCW_USE_M_AXI_GP0 1 CONFIG.PCW_EN_CLK0_PORT 1 CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100]
set_property -dict $psconfig [get_bd_cells ps7]
foreach {p v} $psconfig {if {[get_property $p [get_bd_cells ps7]] != $v} {error "PS readback mismatch $p"}}
# Dedicated PS pins must be top ports, otherwise PS pin constraints hit internal pins (Netlist 29-160).
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi
set_property CONFIG.NUM_MI 2 [get_bd_cells axi]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one
set_property CONFIG.CONST_VAL 1 [get_bd_cells one]
foreach m {pynq_ctl pynq_mbox pynq_soc} {create_bd_cell -type module -reference $m ${m}_0}
# Distinct identity "PQF3": the release client (PYNQ) and the PUF-only test (PFU1) refuse it.
set ctlcfg [list CONFIG.ID_VALUE 0x33465150 CONFIG.VERSION_VALUE 0x00000001]
set_property -dict $ctlcfg [get_bd_cells pynq_ctl_0]
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi/M00_AXI] [get_bd_intf_pins pynq_ctl_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi/M01_AXI] [get_bd_intf_pins pynq_mbox_0/S_AXI]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK] [get_bd_pins axi/ACLK] [get_bd_pins axi/S00_ACLK] [get_bd_pins axi/M00_ACLK] [get_bd_pins axi/M01_ACLK] [get_bd_pins reset/slowest_sync_clk] [get_bd_pins pynq_ctl_0/clk] [get_bd_pins pynq_mbox_0/clk] [get_bd_pins pynq_soc_0/clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins reset/ext_reset_in]
connect_bd_net [get_bd_pins one/dout] [get_bd_pins reset/dcm_locked]
connect_bd_net [get_bd_pins reset/peripheral_aresetn] [get_bd_pins axi/ARESETN] [get_bd_pins axi/S00_ARESETN] [get_bd_pins axi/M00_ARESETN] [get_bd_pins axi/M01_ARESETN] [get_bd_pins pynq_ctl_0/rst_n] [get_bd_pins pynq_mbox_0/rst_n] [get_bd_pins pynq_soc_0/rst_n]
foreach {a b} {pynq_ctl_0/soc_reset pynq_mbox_0/link_flush pynq_ctl_0/soc_rst_n pynq_soc_0/soc_rst_n pynq_ctl_0/soc_button pynq_soc_0/button pynq_soc_0/led pynq_ctl_0/soc_led pynq_mbox_0/mbox_txd pynq_soc_0/uart_rxd pynq_soc_0/uart_txd pynq_mbox_0/mbox_rxd} {connect_bd_net [get_bd_pins $a] [get_bd_pins $b]}
assign_bd_address
foreach {seg offset} {pynq_ctl_0 0x40000000 pynq_mbox_0 0x40001000} {
    set_property offset $offset [get_bd_addr_segs ps7/Data/SEG_${seg}_reg0]
    set_property range 4K [get_bd_addr_segs ps7/Data/SEG_${seg}_reg0]
}
foreach {p v} $ctlcfg {if {[get_property $p [get_bd_cells pynq_ctl_0]] != $v} {error "pynq_ctl readback mismatch $p"}}
validate_bd_design
save_bd_design
set xdc [file join $board pynq_puf3_timing.xdc]
add_files -fileset constrs_1 -norecurse $xdc
set_property USED_IN_SYNTHESIS false [get_files $xdc]
set_property USED_IN_IMPLEMENTATION true [get_files $xdc]
set bd [get_files */pynq_puf3.bd]
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
set_property top pynq_puf3_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

set fp [open $work/context.txt w]
puts $fp [version]
puts $fp "part=xc7z020clg400-1 top=pynq_puf3_wrapper FCLK0=100MHz ro_clk=clk/4 (inside soc_top) coe=$coe strategy=$strategy"
puts $fp "source_head=[exec git -C $root rev-parse HEAD]"
foreach ip [get_ips] {puts $fp "$ip [get_property IPDEF $ip]"}
close $fp

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "synthesis failed"}
# 2026-10-30 on this netlist (reports/explore_impl.txt): RefinePlacement -0.123 (no post-route
# phys_opt); with post-route phys_opt ExtraTimingOpt +0.104 (candidate), RefinePlacement +0.025,
# Explore +0.016, NetDelay_low -0.244. The candidate came from explore_impl.tcl run impl_2 +
# finalize_run.tcl; this default reproduces that recipe in impl_1 (fresh rerun not yet done).
set_property strategy $strategy [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.OPT_DESIGN.TCL.PRE [file join $board puf_opt_pre.tcl] [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "implementation failed: [get_property STATUS [get_runs impl_1]]"}

open_checkpoint [file join $work pynq_puf3.runs impl_1 pynq_puf3_wrapper_postroute_physopt.dcp]
report_timing_summary -delay_type min_max -max_paths 10 -file $rep/timing_summary.rpt
report_timing_summary -delay_type min_max -max_paths 1 -report_unconstrained -file $rep/timing_unconstrained.rpt
check_timing -verbose -file $rep/check_timing.rpt
report_drc -file $rep/drc.rpt
report_methodology -file $rep/methodology.rpt
report_utilization -file $rep/utilization.rpt
report_utilization -pblocks [get_pblocks -quiet pb_ro_puf] -file $rep/pblock_utilization.rpt
report_clock_interaction -file $rep/clock_interaction.rpt
report_route_status -file $rep/route_status.rpt

set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set drc_bad [llength [get_drc_violations -quiet -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]]
set ro_luts [get_cells -quiet -hier -filter {NAME =~ "*u_ro/*" && REF_NAME =~ "LUT*"}]
set ro_assigned [llength [filter $ro_luts {PBLOCK =~ "*pb_ro_puf"}]]
set ro_placed 0
foreach c $ro_luts {
    if {[regexp {SLICE_X(\d+)Y(\d+)} [get_property LOC $c] -> x y] && $x >= 60 && $x <= 113 && $y >= 115 && $y <= 149} {incr ro_placed}
}
set pb_soft [get_property IS_SOFT [get_pblocks pb_ro_puf]]
set impl_log [file join $work pynq_puf3.runs impl_1 runme.log]
set f [open $impl_log r]; set log [read $f]; close $f
set n29160 [regexp -all {Netlist 29-160} $log]
set fp [open $rep/gate.txt w]
puts $fp "run=impl_1 strategy=$strategy wns=$wns whs=$whs drc_error_or_critical=$drc_bad ro_luts=[llength $ro_luts] ro_luts_assigned_pblock=$ro_assigned ro_luts_placed_in_pblock_region=$ro_placed pblock_soft=$pb_soft netlist_29_160=$n29160"
close $fp
puts "PYNQ_PUF3_GATE wns=$wns whs=$whs drc=$drc_bad ro=[llength $ro_luts] assigned=$ro_assigned placed_in_region=$ro_placed soft=$pb_soft n29160=$n29160"
if {$wns < 0} {error "setup timing failed; do not release"}
if {$whs < 0} {error "hold timing failed; do not release"}
if {$drc_bad} {error "DRC gate failed"}
if {[llength $ro_luts] != 1280 || $ro_assigned != 1280} {error "RO structure gate failed"}
if {$n29160} {error "PS pin constraints applied to internal pins"}
write_bitstream -force $work/pynq_puf3.bit
file copy -force $work/pynq_puf3.gen/sources_1/bd/pynq_puf3/hw_handoff/pynq_puf3.hwh $work/pynq_puf3.hwh
puts "PYNQ_PUF3_BUILD_PASS"
