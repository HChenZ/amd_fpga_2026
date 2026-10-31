# Read-only audit of the final optimized physical ring bank.
set root [file normalize [file join [file dirname [info script]] ../..]]
set cells [get_cells -hier -filter {NAME =~ */u_puf/bank/* && REF_NAME =~ LUT*}]
if {[llength $cells]!=1280} {error "Expected 1280 physical ring LUTs"}
set fp [open $root/data/advanced/puf_soc/optimized/ring_topology.tsv w]
puts $fp "cell\ttype\tloc\tbel\tdont_touch\toutput_net\tfeedback_ack"
set ack_count 0
foreach c $cells {
    set net [get_nets -of_objects [get_pins -of_objects $c -filter {REF_PIN_NAME == O}]]
    set ack [get_property ALLOW_COMBINATORIAL_LOOPS $net]
    if {$ack eq "1"} {incr ack_count}
    puts $fp "$c\t[get_property REF_NAME $c]\t[get_property LOC $c]\t[get_property BEL $c]\t[get_property DONT_TOUCH $c]\t$net\t$ack"
}
close $fp
if {$ack_count!=256} {error "Expected exactly 256 acknowledged feedback nets, got $ack_count"}
puts "PUF_RING_AUDIT_PASS LUTs=1280 feedback_acks=$ack_count no_RO_timing_signoff"
