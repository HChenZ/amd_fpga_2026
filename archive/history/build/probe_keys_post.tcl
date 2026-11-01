# 集成后核查：RO 阵列是否真的落在 pblock 里，以及 80 MHz 下的余量
set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint [file join $root build local keys_sta keys_routed.dcp]

# ---- 1) pblock 里的 cell 数与 X/Y 跨度
set pb [get_pblocks -quiet pb_ro_puf]
set n  [llength [get_cells -quiet -of_objects $pb]]
puts "PBLOCK pb_ro_puf cells=$n"
set minx 9999 ; set maxx -1 ; set miny 9999 ; set maxy -1
foreach c [get_cells -quiet -of_objects $pb] {
    set s [get_sites -quiet -of_objects $c]
    if {$s eq ""} { continue }
    if {[regexp {SLICE_X([0-9]+)Y([0-9]+)} [get_property NAME $s] m x y]} {
        if {$x < $minx} {set minx $x} ; if {$x > $maxx} {set maxx $x}
        if {$y < $miny} {set miny $y} ; if {$y > $maxy} {set maxy $y}
    }
}
puts "PBLOCK_RO_BBOX X=$minx..$maxx Y=$miny..$maxy"

# ---- 2) 100 MHz 现况
set w [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "WNS_100MHZ $w"

# ---- 3) 同网表只改周期，估 90/80 MHz
foreach {lbl per} {90MHz 11.111 80MHz 12.500 75MHz 13.333} {
    reset_timing
    create_clock -period $per -name clk [get_ports clk]
    update_timing -full
    set s [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    puts "WNS_$lbl $s"
}
puts "KEYS STA PROBE DONE"
