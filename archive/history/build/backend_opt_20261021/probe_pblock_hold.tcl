# Did the pblock actually hold? Count cells of each pblock that ended up outside
# its GRID_RANGES, on a routed variant checkpoint.
#   vivado -mode batch -source build/backend_opt_20261021/probe_pblock_hold.tcl \
#          -notrace -tclargs <variant>
set root    [file normalize [file join [file dirname [info script]] .. ..]]
set variant [lindex $argv 0]
set dcp [file join $root build local backend_opt_20261021 $variant ${variant}_routed.dcp]
if {![file exists $dcp]} { error "missing $dcp" }
open_checkpoint $dcp
set pbs [get_pblocks]
puts "HOLD $variant pblocks=[llength $pbs]"
proc rng_bounds {range} {
    # range like SLICE_X0Y0:SLICE_X113Y49
    if {![regexp {SLICE_X(\d+)Y(\d+):SLICE_X(\d+)Y(\d+)} $range -> x0 y0 x1 y1]} { return "" }
    return [list $x0 $x1 $y0 $y1]
}
foreach pb $pbs {
    set name [get_property NAME $pb]
    set ranges [get_property GRID_RANGES $pb]
    set bnd [rng_bounds [lindex $ranges 0]]
    if {$bnd eq ""} { puts "HOLD $name ranges=$ranges (unparsed)" ; continue }
    lassign $bnd x0 x1 y0 y1
    set tot 0 ; set out 0
    foreach c [get_cells -quiet -of_objects $pb] {
        # hierarchical cells have no SITE; walk their leaves
        set leaves $c
        if {[get_property -quiet SITE $c] eq ""} {
            set leaves [get_cells -quiet -hier -filter "NAME =~ \"[get_property NAME $c]/*\" && IS_PRIMITIVE"]
        }
        foreach l $leaves {
            set st [get_property -quiet SITE $l]
            if {![regexp {SLICE_X(\d+)Y(\d+)} $st -> x y]} { continue }
            incr tot
            if {$x < $x0 || $x > $x1 || $y < $y0 || $y > $y1} { incr out }
        }
    }
    puts "HOLD $name range=[lindex $ranges 0] placed=$tot outside=$out"
}
close_project
