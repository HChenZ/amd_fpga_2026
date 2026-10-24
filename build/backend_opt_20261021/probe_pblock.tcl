# Verify pblock membership without running place: does add_cells_to_pblock on the
# hierarchical cpu_core / ascon_mmio cell actually constrain their leaf cells?
#   vivado -mode batch -source build/backend_opt_20261021/probe_pblock.tcl -notrace
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_opt.dcp]
open_checkpoint $dcp
source [file join $root build local backend_opt_20261021 floorplan fp3.tcl]
foreach pb [get_pblocks] {
    set n  [get_property NAME $pb]
    set rc [get_property GRID_RANGES $pb]
    set in [get_cells -quiet -of_objects $pb]
    puts "PBCHECK $n range=$rc cells=[llength $in]"
}
# how many leaf cells exist under cpu_core / ascon_mmio, and how many landed in a pblock
set cpu   [get_cells -hier -quiet -filter {IS_PRIMITIVE && NAME =~ "*u_cpu_core/*"}]
set cry   [get_cells -hier -quiet -filter {IS_PRIMITIVE && NAME =~ "*u_ascon_mmio/*"}]
puts "PBCHECK leaf cpu=[llength $cpu] crypto=[llength $cry]"
set un 0
foreach c [get_cells -hier -quiet -filter {IS_PRIMITIVE}] {
    if {[llength [get_pblocks -quiet -of_objects $c]] == 0} { incr un }
}
puts "PBCHECK unconstrained_leaf_cells=$un"
close_project
