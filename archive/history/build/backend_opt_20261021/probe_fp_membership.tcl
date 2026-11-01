# Membership check for a hold-oriented floorplan, without placing.
#   vivado -mode batch -source build/backend_opt_20261021/probe_fp_membership.tcl \
#          -notrace -tclargs hfp1
set root [file normalize [file join [file dirname [info script]] .. ..]]
set tag  [lindex $argv 0]
set dcp  [file join $root build local backend_opt_20261021 pl_ndh_crit200_ntr pl_ndh_crit200_ntr_routed.dcp]
open_checkpoint $dcp
source [file join $root build local backend_opt_20261021 floorplan ${tag}.tcl]
foreach pb [get_pblocks] {
    set n  [get_property NAME $pb]
    set in [get_cells -quiet -of_objects $pb]
    set leaves 0
    foreach c $in {
        if {[get_property -quiet SITE $c] ne ""} { incr leaves } else {
            incr leaves [llength [get_cells -quiet -hier -filter "NAME =~ \"[get_property NAME $c]/*\" && IS_PRIMITIVE"]]
        }
    }
    puts "FPMEM $tag $n ranges=[get_property GRID_RANGES $pb] members=[llength $in] leaves=$leaves"
}
set un 0
foreach c [get_cells -hier -quiet -filter {IS_PRIMITIVE}] {
    if {[llength [get_pblocks -quiet -of_objects $c]] == 0} { incr un }
}
puts "FPMEM $tag unconstrained_leaves=$un"
close_project
puts "FPMEM $tag DONE"
