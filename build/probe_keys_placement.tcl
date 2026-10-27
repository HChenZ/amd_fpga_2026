# 核查 RO 阵列的实际落点：u_puf 下所有叶子 cell 的 PBLOCK 归属与坐标范围
set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint [file join $root build local keys_sta keys_routed.dcp]

set leaves [get_cells -quiet -hier -filter "NAME =~ \"*u_puf_key/u_puf/*\""]
puts "PUF_LEAVES [llength $leaves]"
set minx 9999 ; set maxx -1 ; set miny 9999 ; set maxy -1 ; set n 0 ; set inp 0
foreach c $leaves {
    if {[get_property PBLOCK $c] eq "pb_ro_puf"} { incr inp }
    set s [get_sites -quiet -of_objects $c]
    if {$s eq ""} { continue }
    if {[regexp {SLICE_X([0-9]+)Y([0-9]+)} [get_property NAME $s] m x y]} {
        if {$x < $minx} {set minx $x} ; if {$x > $maxx} {set maxx $x}
        if {$y < $miny} {set miny $y} ; if {$y > $maxy} {set maxy $y}
        incr n
    }
}
puts "PUF_IN_PBLOCK $inp"
puts "PUF_PLACED_SITES $n"
puts "PUF_BBOX X=$minx..$maxx Y=$miny..$maxy"
# CPU 核的落点，确认没被挤进 pblock 区域
set cpu [get_cells -quiet -hier -filter "NAME =~ \"*u_cpu_core/*\""]
set cminx 9999 ; set cmaxx -1 ; set cminy 9999 ; set cmaxy -1
foreach c $cpu {
    set s [get_sites -quiet -of_objects $c]
    if {$s eq ""} { continue }
    if {[regexp {SLICE_X([0-9]+)Y([0-9]+)} [get_property NAME $s] m x y]} {
        if {$x < $cminx} {set cminx $x} ; if {$x > $cmaxx} {set cmaxx $x}
        if {$y < $cminy} {set cminy $y} ; if {$y > $cmaxy} {set cmaxy $y}
    }
}
puts "CPU_BBOX X=$cminx..$cmaxx Y=$cminy..$cmaxy"
puts "PUF PLACEMENT PROBE DONE"
