# 只读复核最终设计的物理环结构。必须在 open_run impl_1 之后运行。
# 不修改任何属性、不创建时钟、不改变 DRC 严重度。
if {![info exists ::puf_min_out]} {
    set ::puf_min_out [file normalize [file join [file dirname [info script]] ../../data/advanced/puf_min/audit_ring_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]]
}
file mkdir $::puf_min_out
set cells [get_cells -hier -filter {NAME =~ */bank/rings* && REF_NAME =~ LUT*}]
if {[llength $cells] != 1280} {error "Expected 1280 physical ring LUTs, got [llength $cells]"}
set fp [open $::puf_min_out/ring_topology.tsv w]
puts $fp "cell\ttype\tloc\tbel\tdont_touch\toutput_net\tfeedback_ack\tpblock"
set ack 0
foreach c $cells {
    set net [get_nets -of_objects [get_pins -of_objects $c -filter {REF_PIN_NAME == O}]]
    set a [get_property ALLOW_COMBINATORIAL_LOOPS $net]
    if {$a eq "1"} {incr ack}
    puts $fp "$c\t[get_property REF_NAME $c]\t[get_property LOC $c]\t[get_property BEL $c]\t[get_property DONT_TOUCH $c]\t$net\t$a\t[get_property PBLOCK $c]"
}
close $fp
set in_pb [llength [filter $cells {PBLOCK =~ "*pb_ro_puf"}]]
if {$ack != 256} {error "Expected exactly 256 acknowledged feedback nets, got $ack"}
if {$in_pb != 1280} {error "RO LUTs outside pb_ro_puf: $in_pb of 1280"}
set fp [open $::puf_min_out/ring_audit.txt w]
puts $fp "ro_luts=1280 feedback_acks=$ack ro_luts_in_pblock=$in_pb"
puts $fp "RO_TIMING=NOT_MEASURED; no oscillator clock defined; NOT a timing signoff"
close $fp
puts "PUF_MIN_RING_AUDIT_PASS LUTs=1280 feedback_acks=$ack in_pblock=$in_pb"
