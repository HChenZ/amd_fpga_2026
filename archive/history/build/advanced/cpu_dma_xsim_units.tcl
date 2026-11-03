# Generate isolated XSim unit scripts; never touch the running full CPU sim dir.
set root [file normalize [file join [file dirname [info script]] ../..]]
foreach kind {endpoint control reset} {
    set fs sim_dma_$kind
    if {[lsearch -exact [get_filesets] $fs]<0} {create_fileset -simset $fs}
    current_fileset -simset $fs
    set_property SOURCE_SET sources_1 [get_filesets $fs]
    add_files -fileset $fs -norecurse $root/sim/pynq_dma_cpu/tb_dma_$kind.v
    set_property file_type SystemVerilog [get_files */tb_dma_$kind.v]
    set_property top tb_dma_$kind [get_filesets $fs]
    set_property include_dirs [list $root/src/rtl $root/src/rtl/ascon] [get_filesets $fs]
    set_property xsim.simulate.runtime 1ms [get_filesets $fs]
    set_property -dict [list xsim.simulate.xsim.more_options {}] [get_filesets $fs]
    update_compile_order -fileset $fs
    launch_simulation -scripts_only -mode behavioral -simset $fs
}
puts "CPU_DMA_XSIM_UNIT_SCRIPTS_READY"
