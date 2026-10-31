# Prepare vendor-private-BRAM real CPU simulation in the CPU DMA project.
# Generated native simulator scripts may run independently while synth/impl runs.
set root [file normalize [file join [file dirname [info script]] ../..]]
set vectors $root/data/advanced/dma_cpu/full_20261030_002958_293520/xsim_all
set simset sim_cpu_vendor
if {[lsearch -exact [get_filesets] $simset]<0} {create_fileset -simset $simset}
current_fileset -simset $simset
set_property SOURCE_SET sources_1 [get_filesets $simset]
add_files -fileset $simset -norecurse $root/sim/pynq_dma_cpu/tb_dma_cpu_vendor.v
set_property file_type SystemVerilog [get_files */tb_dma_cpu_vendor.v]
set_property top tb_dma_cpu_vendor [get_filesets $simset]
set_property target_simulator XSim [current_project]
set_property xsim.simulate.runtime 10s [get_filesets $simset]
set_property -dict [list xsim.simulate.xsim.more_options "-testplusarg \"DATA=$vectors\" -testplusarg \"CASES=7418\" -testplusarg \"REQUEST_BYTES=895411\" -testplusarg \"RESPONSE_BYTES=469856\""] [get_filesets $simset]
set_property include_dirs [list $root/src/rtl $root/src/rtl/ascon] [get_filesets $simset]
update_compile_order -fileset $simset
launch_simulation -scripts_only -mode behavioral -simset $simset
puts "CPU_DMA_VENDOR_XSIM_SCRIPTS_READY [get_property DIRECTORY [current_project]]/cpu_dma.sim/$simset/behav/xsim"
