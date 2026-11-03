# Real AXI DMA + actual CPU/control wrapper + vendor private BRAM. PS DDR is BFM.
set root [file normalize [file join [file dirname [info script]] ../..]]
open_bd_design [get_files */cpu_dma.bd]
# A BD-owned wrapper is not automatically included when directly referenced by
# an unrelated simulation top. Use a simulation-only native IP with read-back
# configuration copied from the actual BD DMA, rather than an RTL DMA stub.
if {[lsearch -exact [get_ips] cpu_dma_sim_dma]<0} {
    create_ip -name axi_dma -vendor xilinx.com -library ip -version 7.1 -module_name cpu_dma_sim_dma
    set cfg {}
    foreach key {c_include_sg c_include_mm2s c_include_s2mm c_m_axi_mm2s_data_width c_m_axi_s2mm_data_width c_m_axis_mm2s_tdata_width c_s_axis_s2mm_tdata_width c_sg_length_width c_include_mm2s_dre c_include_s2mm_dre c_mm2s_burst_size c_s2mm_burst_size c_micro_dma c_addr_width} {
        lappend cfg CONFIG.$key [get_property CONFIG.$key [get_bd_cells dma]]
    }
    set_property -dict $cfg [get_ips cpu_dma_sim_dma]
    foreach {key value} $cfg {if {[get_property $key [get_ips cpu_dma_sim_dma]] ne $value} {error "Simulation DMA differs: $key"}}
    set_property USED_IN_SYNTHESIS false [get_files [get_property IP_FILE [get_ips cpu_dma_sim_dma]]]
    generate_target all [get_ips cpu_dma_sim_dma]
    set fp [open [get_property DIRECTORY [current_project]]/simulation_dma_config.txt w]
    puts $fp $cfg
    close $fp
}
set fs sim_dma_cpu_system
if {[lsearch -exact [get_filesets] $fs]<0} {create_fileset -simset $fs}
current_fileset -simset $fs
set_property SOURCE_SET sources_1 [get_filesets $fs]
add_files -fileset $fs -norecurse [list $root/sim/pynq_dma_cpu/dma_cpu_vendor_system.sv $root/sim/pynq_dma_cpu/tb_vendor_dma_cpu.sv]
set_property top tb_vendor_dma_cpu [get_filesets $fs]
set_property include_dirs [list $root/src/rtl $root/src/rtl/ascon] [get_filesets $fs]
set_property xsim.simulate.runtime 1s [get_filesets $fs]
set_property -dict [list xsim.simulate.xsim.more_options "-testplusarg \"VECTORS=$root/build/local/dma_cpu_system_vectors.txt\" -testplusarg \"CASES=95\""] [get_filesets $fs]
update_compile_order -fileset $fs
launch_simulation -scripts_only -simset $fs -mode behavioral
puts "CPU_VENDOR_DMA_SYSTEM_SCRIPTS_READY"
