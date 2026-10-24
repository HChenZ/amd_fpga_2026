# Probe device geometry + current CPU-core placement spread from the routed snapshot.
# Read-only: does not modify the source project / RTL / XDC.
# vivado -mode batch -source build/probe_geometry.tcl -notrace
set root [file normalize [file join [file dirname [info script]] ..]]
set dcp [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_routed.dcp]
open_checkpoint $dcp

set xs {}
set ys {}
foreach s [get_sites -quiet -filter {SITE_TYPE == "SLICEL" || SITE_TYPE == "SLICEM"}] {
    if {[regexp {SLICE_X([0-9]+)Y([0-9]+)} [get_property NAME $s] m x y]} {
        lappend xs $x
        lappend ys $y
    }
}
set xmin [lindex [lsort -integer $xs] 0]
set xmax [lindex [lsort -integer $xs] end]
set ymin [lindex [lsort -integer $ys] 0]
set ymax [lindex [lsort -integer $ys] end]
puts "DEVICE slice grid X $xmin .. $xmax ; Y $ymin .. $ymax"
puts "DEVICE clock_regions: [get_clock_regions]"

proc bbox {pattern label} {
    set minx 9999
    set maxx -1
    set miny 9999
    set maxy -1
    set n 0
    foreach c [get_cells -hier -quiet $pattern] {
        set s [get_sites -quiet -of_objects $c]
        if {$s eq ""} { continue }
        if {[regexp {SLICE_X([0-9]+)Y([0-9]+)} [get_property NAME $s] m x y]} {
            if {$x < $minx} {set minx $x}
            if {$x > $maxx} {set maxx $x}
            if {$y < $miny} {set miny $y}
            if {$y > $maxy} {set maxy $y}
            incr n
        }
    }
    puts "BBOX $label cells=$n X=$minx..$maxx span=[expr {$maxx-$minx+1}] Y=$miny..$maxy span=[expr {$maxy-$miny+1}]"
}
bbox u_soc_axi_top/u_soc_top/u_cpu_core/* cpu_core
bbox u_soc_axi_top/u_soc_top/u_cpu_core/u_icache/* icache
bbox u_soc_axi_top/u_soc_top/u_cpu_core/u_dcache/* dcache
bbox u_soc_axi_top/u_soc_top/u_cpu_core/u_csr_file/* csr_file
bbox u_soc_axi_top/u_soc_top/u_cpu_core/u_ex_stage/* ex_stage
bbox u_soc_axi_top/u_soc_top/u_cpu_core/u_if_stage/* if_stage
bbox u_soc_axi_top/u_soc_top/u_axi_interconnect*/* interco

foreach cr [get_clock_regions] {
    set avail [llength [get_sites -quiet -of_objects $cr -filter {SITE_TYPE == "SLICEL" || SITE_TYPE == "SLICEM"}]]
    puts "CR $cr avail_slices=$avail"
}
puts "PROBE DONE"
