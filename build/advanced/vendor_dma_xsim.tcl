# Actual AXI DMA IP simulation with AXI memory BFM, not a mocked DMA engine.
set root [file normalize [file join [file dirname [info script]] ../..]]
set work $root/build/local/dma_vendor_sim
create_project v $work -part xc7z020clg400-1
create_ip -name axi_dma -vendor xilinx.com -library ip -version 7.1 -module_name d_dma_0
set cfg [list CONFIG.c_include_sg 0 CONFIG.c_include_mm2s 1 CONFIG.c_include_s2mm 1 CONFIG.c_m_axi_mm2s_data_width 32 CONFIG.c_m_axi_s2mm_data_width 32 CONFIG.c_m_axis_mm2s_tdata_width 32 CONFIG.c_s_axis_s2mm_tdata_width 32 CONFIG.c_sg_length_width 14 CONFIG.c_include_mm2s_dre 0 CONFIG.c_include_s2mm_dre 0]
set_property -dict $cfg [get_ips d_dma_0]
foreach {k val} $cfg {if {[get_property $k [get_ips d_dma_0]] ne $val} {error "IP readback $k"}}
generate_target all [get_ips d_dma_0]
add_files -norecurse [list $root/src/rtl/ascon/ascon_round.v $root/src/rtl/ascon_dma/ascon_aead_multiblock.v $root/src/rtl/ascon_dma/ascon_axis_direct.v]
add_files -fileset sim_1 -norecurse $root/sim/ascon_dma/tb_vendor_dma.sv
set_property top tb_vendor_dma [get_filesets sim_1]
set_property xsim.simulate.runtime 1s [get_filesets sim_1]
set_property -dict [list xsim.simulate.xsim.more_options "-testplusarg VECTORS=$root/build/local/advanced_dma/vectors.txt"] [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -mode behavioral -simset sim_1
set out $root/data/advanced/dma_direct/vendor_xsim_[clock format [clock seconds] -format %Y%m%d_%H%M%S]
file mkdir $out
foreach f {simulate.log xvlog.log xvhdl.log elaborate.log tb_vendor_dma.tcl} {
    set p $work/v.sim/sim_1/behav/xsim/$f
    if {[file exists $p]} {file copy $p $out/$f}
}
set fp [open $out/simulate.log r];set text [read $fp];close $fp
close_sim
if {![regexp {TEST_PASS vendor_dma} $text] || [regexp -nocase {fatal:|assertion failed} $text]} {error "Vendor DMA behavioral simulation failed: $out"}
set fp [open $out/result.txt w];puts $fp "status=PASS vivado=[version -short] ip=axi_dma7.1 mode=simple memory_width=32 stream_width=32 ps_ddr_model=BFM board=NOT_RUN";close $fp
puts "VENDOR_DMA_XSIM_PASS $out"
