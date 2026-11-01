# 探针：大扇出网清单（只读 DCP）
#   vivado -mode batch -source build/timing_tests/probe_fanout.tcl -notrace \
#          -tclargs <routed.dcp|post-opt.dcp> <out.txt> [min_pins] [pattern]
set root [file normalize [file join [file dirname [info script]] ../..]]
set dcp  [lindex $argv 0]
set out  [lindex $argv 1]
set minp [expr {[llength $argv] > 2 ? [lindex $argv 2] : 128}]
set pat  [expr {[llength $argv] > 3 ? [lindex $argv 3] : ""}]
if {$dcp eq "" || $out eq ""} { error "usage: -tclargs <dcp> <out.txt> \[min_pins\] \[name_pattern\]" }
open_checkpoint $dcp
set fp [open $out w]

puts $fp "=== global high-fanout nets (top 40, fo >= $minp) ==="
set items {}
foreach n [get_nets -quiet -hier -filter "FLAT_PIN_COUNT >= $minp"] {
    set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
    if {[llength $drv] != 1} { continue }
    set dc [get_cells -quiet -of_objects $drv]
    set ref [expr {$dc ne "" ? [get_property REF_NAME $dc] : "?"}]
    if {$ref in {BUFG BUFGCE BUFGCE_DIV BUFG_GT BUFR BUFH BUFIO BUFMR MMCME2_ADV PLLE2_ADV PS7}} { continue }
    lappend items [list [get_property FLAT_PIN_COUNT $n] [get_property NAME $n] [get_property NAME $dc] $ref]
}
foreach it [lrange [lsort -integer -decreasing -index 0 $items] 0 39] {
    lassign $it fo nm drv ref
    set loc [expr {$dc ne "" ? [get_property LOC $dc] : "?"}]
    puts $fp [format "  fo=%-6d %-8s %-26s %s" $fo $loc $ref $nm]
}

if {$pat ne ""} {
    puts $fp "\n=== nets matching '$pat' (fo >= 8), sorted by fanout ==="
    set sel {}
    foreach n [get_nets -quiet -hier -filter "NAME =~ \"$pat\" && FLAT_PIN_COUNT >= 8"] {
        set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
        if {[llength $drv] != 1} { continue }
        set dc [get_cells -quiet -of_objects $drv]
        set ref [expr {$dc ne "" ? [get_property REF_NAME $dc] : "?"}]
        set loc [expr {$dc ne "" ? [get_property LOC $dc] : "?"}]
        lappend sel [list [get_property FLAT_PIN_COUNT $n] [get_property NAME $n] $ref $loc]
    }
    puts $fp [format "  (%d nets)" [llength $sel]]
    foreach it [lsort -integer -decreasing -index 0 $sel] {
        lassign $it fo nm ref loc
        puts $fp [format "  fo=%-6d %-9s %-6s %s" $fo $loc $ref $nm]
    }
}

# 最差 30 条路径的起点/终点（便于把网和路径对上）
puts $fp "\n=== worst 30 setup paths ==="
foreach p [get_timing_paths -quiet -max_paths 30 -nworst 1 -setup] {
    puts $fp [format "  %+.3f  %s  ->  %s" [get_property SLACK $p] \
              [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
}
close $fp
puts "FANOUT PROBE DONE -> $out"
