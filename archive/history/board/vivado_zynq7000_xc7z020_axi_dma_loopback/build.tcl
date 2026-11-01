# Non-Ascon AXI DMA loopback overlay for the pynq-overlay-workflow Skill L3 board test.
# Vivado 2025.2, xc7z020clg400-1. Independent entry; touches no other board project.
#   vivado -mode batch -source board/vivado_zynq7000_xc7z020_axi_dma_loopback/build.tcl -notrace [-tclargs <strategy> <jobs>]
# PS7 GP0 -> AXI DMA S_AXI_LITE; DMA M_AXI_MM2S/S2MM -> PS7 HP0; M_AXIS_MM2S -> S_AXIS_S2MM (TLAST/TKEEP
# carried by the interface connection). Simple mode only (no SG). Everything on FCLK0 = 100 MHz.
if {![string match "2025.2*" [version -short]]} {error "Vivado 2025.2 required"}
set root  [file normalize [file join [file dirname [info script]] ../..]]
set work  [file join $root build local axi_dma_loopback vivado]
set rep   [file join $work reports]
set strategy [expr {[llength $argv] > 0 ? [lindex $argv 0] : "Performance_ExploreWithRemap"}]
set jobs     [expr {[llength $argv] > 1 ? [lindex $argv 1] : 4}]
if {[file exists [file join $work dma_loop.xpr]]} {error "Existing project $work; remove it explicitly before a fresh build"}
file mkdir $rep

create_project dma_loop $work -part xc7z020clg400-1
set_property target_language Verilog [current_project]
create_bd_design dma_loop

proc checked_cfg {cell config} {
    set_property -dict $config [get_bd_cells $cell]
    foreach {k v} $config {
        if {[get_property $k [get_bd_cells $cell]] ne $v} {error "configuration readback failed: $cell $k"}
    }
}

create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
# FCLK0 on the board = boot-image IO PLL / divisors from this hwh (PYNQ writes only the divisors).
# The ATK Navigator boot image runs IO PLL = 33.333333 MHz x 30 = 1000 MHz, so pin FBDIV 30 and
# divide by 10 x 1 (same fix as pynq_puf3, board-verified 2026-10-30: 99.999999 MHz derived,
# 99.988 MHz measured). Letting the IP choose (1600 MHz, 4 x 4) gives 62.5 MHz on this board.
checked_cfg ps7 [list CONFIG.PCW_USE_M_AXI_GP0 1 CONFIG.PCW_USE_S_AXI_HP0 1 CONFIG.PCW_S_AXI_HP0_DATA_WIDTH 64 \
    CONFIG.PCW_EN_CLK0_PORT 1 CONFIG.PCW_OVERRIDE_BASIC_CLOCK 1 CONFIG.PCW_IOPLL_CTRL_FBDIV 30 \
    CONFIG.PCW_FCLK0_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_FCLK0_PERIPHERAL_DIVISOR0 10 \
    CONFIG.PCW_FCLK0_PERIPHERAL_DIVISOR1 1 CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100]
# DDR metadata of the board (vendor base BD: DDR3 32-bit MT41J256M16 RE-125, 1 GiB, 0x0..0x3FFFFFFF).
# The overlay does not reconfigure DDR, but this sets the HP0 aperture seen by the DMA masters:
# with the IP default (512 MiB) a pynq.allocate buffer above 0x20000000 would end in DMADecErr.
checked_cfg ps7 [list CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit}]
if {[get_property CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ [get_bd_cells ps7]] != 33.333333} {error "PS crystal is not 33.333333 MHz"}
if {abs([get_property CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells ps7]] - 100.0) > 0.01} {error "FCLK0 actual is not 100 MHz"}
# Dedicated PS pins must be top ports, otherwise PS pin constraints hit internal pins (Netlist 29-160).
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
checked_cfg axi_dma_0 [list CONFIG.c_include_sg 0 CONFIG.c_include_mm2s 1 CONFIG.c_include_s2mm 1 \
    CONFIG.c_addr_width 32 CONFIG.c_sg_length_width 14 \
    CONFIG.c_m_axi_mm2s_data_width 32 CONFIG.c_m_axi_s2mm_data_width 32 \
    CONFIG.c_m_axis_mm2s_tdata_width 32 CONFIG.c_s_axis_s2mm_tdata_width 32 \
    CONFIG.c_include_mm2s_dre 0 CONFIG.c_include_s2mm_dre 0]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ctrl_ic
checked_cfg ctrl_ic [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 mem_ic
checked_cfg mem_ic [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 1]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_fclk0
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one
checked_cfg one [list CONFIG.CONST_VAL 1]

connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins ctrl_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_ic/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins mem_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins mem_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins mem_ic/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]
# Stream loopback: the interface net carries TDATA/TKEEP/TLAST/TVALID/TREADY unchanged.
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

set clk_pins {ps7/M_AXI_GP0_ACLK ps7/S_AXI_HP0_ACLK ctrl_ic/ACLK ctrl_ic/S00_ACLK ctrl_ic/M00_ACLK
              mem_ic/ACLK mem_ic/S00_ACLK mem_ic/S01_ACLK mem_ic/M00_ACLK
              axi_dma_0/s_axi_lite_aclk axi_dma_0/m_axi_mm2s_aclk axi_dma_0/m_axi_s2mm_aclk rst_fclk0/slowest_sync_clk}
foreach p $clk_pins {connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins $p]}
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_fclk0/ext_reset_in]
connect_bd_net [get_bd_pins one/dout] [get_bd_pins rst_fclk0/dcm_locked]
# Interconnect cores take interconnect_aresetn, endpoints take peripheral_aresetn.
foreach p {ctrl_ic/ARESETN mem_ic/ARESETN} {connect_bd_net [get_bd_pins rst_fclk0/interconnect_aresetn] [get_bd_pins $p]}
foreach p {ctrl_ic/S00_ARESETN ctrl_ic/M00_ARESETN mem_ic/S00_ARESETN mem_ic/S01_ARESETN mem_ic/M00_ARESETN axi_dma_0/axi_resetn} {
    connect_bd_net [get_bd_pins rst_fclk0/peripheral_aresetn] [get_bd_pins $p]
}

assign_bd_address
set_property offset 0x40400000 [get_bd_addr_segs ps7/Data/SEG_axi_dma_0_Reg]
set_property range 64K [get_bd_addr_segs ps7/Data/SEG_axi_dma_0_Reg]
foreach space {Data_MM2S Data_S2MM} {
    set seg [get_bd_addr_segs axi_dma_0/$space/SEG_ps7_HP0_DDR_LOWOCM]
    if {[llength $seg] != 1 || [get_property OFFSET $seg] ne "0x00000000" || [get_property RANGE $seg] != 1073741824} {
        error "DMA $space HP0 aperture is not 0x0 + 1G: [get_property OFFSET $seg] [get_property RANGE $seg]"
    }
}
validate_bd_design
save_bd_design
set bd [get_files */dma_loop.bd]
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
set_property top dma_loop_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

set fp [open $work/context.txt w]
puts $fp [version]
puts $fp "part=xc7z020clg400-1 top=dma_loop_wrapper strategy=$strategy FCLK0=100MHz (IOPLL FBDIV 30, div 10x1)"
puts $fp "source_head=[exec git -C $root rev-parse HEAD]"
foreach c [lsort [get_bd_cells -hier]] {puts $fp "cell $c [get_property VLNV $c]"}
foreach c {ps7 axi_dma_0} {
    foreach p [lsort [list_property [get_bd_cells $c]]] {if {[string match CONFIG.* $p]} {puts $fp "$c $p=[get_property $p [get_bd_cells $c]]"}}
}
foreach s [lsort [get_bd_addr_segs -of_objects [get_bd_addr_spaces -of_objects [get_bd_cells -hier]]]] {
    puts $fp "addr $s offset=[get_property OFFSET $s] range=[get_property RANGE $s]"
}
close $fp

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "synthesis failed"}
set_property strategy $strategy [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "implementation failed: [get_property STATUS [get_runs impl_1]]"}

set dcp [file join $work dma_loop.runs impl_1 dma_loop_wrapper_postroute_physopt.dcp]
if {![file exists $dcp]} {set dcp [file join $work dma_loop.runs impl_1 dma_loop_wrapper_routed.dcp]}
open_checkpoint $dcp
report_timing_summary -delay_type min_max -max_paths 10 -report_unconstrained -file $rep/timing_summary.rpt
check_timing -verbose -file $rep/check_timing.rpt
report_drc -file $rep/drc.rpt
report_methodology -file $rep/methodology.rpt
report_utilization -file $rep/utilization.rpt
report_clock_interaction -file $rep/clock_interaction.rpt
report_route_status -file $rep/route_status.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set drc_bad [llength [get_drc_violations -quiet -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]]
set f [open [file join $work dma_loop.runs impl_1 runme.log] r]; set log [read $f]; close $f
set n29160 [regexp -all {Netlist 29-160} $log]
set unrouted [llength [get_nets -quiet -hier -filter {ROUTE_STATUS == UNROUTED || ROUTE_STATUS == CONFLICTS}]]
set fp [open $rep/gate.txt w]
puts $fp "run=impl_1 strategy=$strategy dcp=[file tail $dcp] wns=$wns whs=$whs drc_error_or_critical=$drc_bad netlist_29_160=$n29160 unrouted_or_conflict_nets=$unrouted"
close $fp
puts "AXI_DMA_LOOPBACK_GATE wns=$wns whs=$whs drc=$drc_bad n29160=$n29160 unrouted=$unrouted"
if {$wns < 0} {error "setup timing failed; do not release"}
if {$whs < 0} {error "hold timing failed; do not release"}
if {$drc_bad} {error "DRC gate failed"}
if {$n29160} {error "PS pin constraints applied to internal pins"}
if {$unrouted} {error "routing incomplete"}
# Same basename for bit and hwh: PYNQ loads <stem>.hwh next to <stem>.bit.
write_bitstream -force $work/axi_dma_loopback.bit
file copy -force [file join $work dma_loop.gen sources_1 bd dma_loop hw_handoff dma_loop.hwh] $work/axi_dma_loopback.hwh
puts "AXI_DMA_LOOPBACK_BUILD_PASS"
