# Read-only topology inspection on the currently open physical design.
if {![info exists ::puf_physical_out]} {error "Set ::puf_physical_out"}
set f [open $::puf_physical_out/topology_final.tsv w]
puts $f "kind\tname\tref\tloc\tbel\tattribute"
set ringcells [get_cells -hier -filter {NAME =~ bank/* && REF_NAME =~ LUT*}]
set asyncs [get_cells -hier -filter {ASYNC_REG == TRUE}]
set caps [get_cells -hier -filter {(NAME =~ peripheral/keys/sampler/captured_result_reg* || NAME =~ peripheral/keys/sampler/captured_error_reg*) && IS_SEQUENTIAL}]
if {[llength $ringcells]!=1280 || [llength $asyncs]!=2568 || [llength $caps]!=133} {error "Unexpected topology counts"}
foreach pair [list [list ring $ringcells DONT_TOUCH] [list synchronizer $asyncs ASYNC_REG] [list capture $caps IS_SEQUENTIAL]] {
    lassign $pair kind cells attribute
    foreach c $cells {puts $f "$kind\t$c\t[get_property REF_NAME $c]\t[get_property LOC $c]\t[get_property BEL $c]\t[get_property $attribute $c]"}
}
for {set i 0} {$i<256} {incr i} {
    set prefix [format {bank/rings[%d]} $i]
    set previous "$prefix.gate0/O"
    for {set j 1} {$j<5} {incr j} {
        set name [format {%s.stages[%d].inv0} $prefix $j]
        set c [get_cells -hier -filter "NAME == $name"]
        set net [get_nets -of_objects [get_pins -of_objects $c -filter {REF_PIN_NAME == I0}]]
        set driver [get_pins -leaf -of_objects $net -filter {DIRECTION == OUT}]
        if {[llength $driver]!=1 || [get_property NAME $driver] ne $previous} {error "Broken ring stage $i/$j: $driver"}
        puts $f "ring_arc\t$previous -> $name/I0\t[get_property INIT $c]\t-\t-\tverified"
        set previous "$name/O"
    }
    set gate [get_cells -hier -filter "NAME == $prefix.gate0"]
    set net [get_nets -of_objects [get_pins -of_objects $gate -filter {REF_PIN_NAME == I1}]]
    set driver [get_pins -leaf -of_objects $net -filter {DIRECTION == OUT}]
    if {[llength $driver]!=1 || [get_property NAME $driver] ne $previous} {error "Broken feedback $i"}
    if {![get_property ALLOW_COMBINATORIAL_LOOPS $net]} {error "Missing precise loop acknowledgement $i"}
    puts $f "ring_arc\t$previous -> $prefix.gate0/I1\t[get_property INIT $gate]\t-\t-\tverified"
}
close $f
set f [open $::puf_physical_out/topology_summary.txt w]
puts $f "ring_luts=1280 rings=256 lut_per_ring=5 verified_arcs=1280 async_reg=2568 core_payload_capture=133"
puts $f "clock_objects=[get_clocks] RO_PERIOD_BOUND_NOT_SUPPLIED"
set fixed_pins 0
foreach p [get_ports] {if {[get_property PACKAGE_PIN $p] ne ""} {incr fixed_pins}}
puts $f "fixed_package_pins=$fixed_pins"
close $f
puts "PUF_PHYSICAL_TOPOLOGY_PASS"
