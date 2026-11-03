# Correct the already-built experimental BD after preserving its first reports.
# Never opens or modifies any baseline/release project.
set root [file normalize [file join [file dirname [info script]] ../..]]
set work [get_property DIRECTORY [current_project]]
if {![string equal -nocase [file normalize $work] [file normalize $root/build/local/dma_cpu]]} {error "Wrong project for CPU PS-pin repair"}
close_design
open_bd_design [get_files */cpu_dma.bd]
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
validate_bd_design
save_bd_design
source -notrace $root/build/advanced/cpu_dma_finish_setup.tcl
puts "CPU_PS_FIXED_PORTS_EXPORTED"
