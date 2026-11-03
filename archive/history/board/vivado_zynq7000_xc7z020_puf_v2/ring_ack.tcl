# Exactly one acknowledged feedback net per audited physical five-LUT ring.
# No invented RO frequency, no false paths, no DRC severity changes.
set root [file normalize [file join [file dirname [info script]] ../..]]
set gates [get_cells -hier -filter {NAME =~ */u_puf/bank/*gate0 && REF_NAME == LUT2}]
if {[llength $gates]!=256} {error "Expected 256 PUF ring gates, got [llength $gates]"}
set fp [open $root/data/advanced/puf_soc/ring_inventory.txt w]
foreach gate $gates {
    set fb [get_nets -of_objects [get_pins -of_objects $gate -filter {REF_PIN_NAME == I1}]]
    if {[llength $fb]!=1} {error "Ring feedback ambiguity $gate"}
    set driver [get_pins -leaf -of_objects $fb -filter {DIRECTION == OUT}]
    set expected "[file dirname $gate].stages\[4\].inv0/O"
    # gate path is bank/rings[n].gate0, so strip the final .gate0 suffix.
    set expected "[string range $gate 0 end-6].stages\[4\].inv0/O"
    if {[llength $driver]!=1 || [get_property NAME $driver] ne $expected} {error "Unexpected ring driver $gate: $driver expected=$expected"}
    set_property ALLOW_COMBINATORIAL_LOOPS TRUE $fb
    puts $fp "$gate feedback=$fb driver=$driver no_clock_defined=1"
}
puts $fp "RO_TIMING=NOT_MEASURED; no frequency bound; NOT timing signoff."
close $fp
