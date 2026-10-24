# Produce the programming file from the accepted champion netlist and record every
# artefact needed for a freeze/traceability entry (bitstream hash, DRC, final timing,
# BRAM init source).
#
#   vivado -mode batch -source build/backend_opt_20261021/write_bitstream_champion.tcl -notrace
#
# Assumes the recovered baseline pin/clock set (clk = 50 MHz @ U18) because the board is
# an xc7z020clg400-1 target; if the physical board's clock pin/frequency differs this
# programming file must be regenerated from a board-specific XDC.
set root [file normalize [file join [file dirname [info script]] .. ..]]
set var  "pl_ndh_crit200_ntr"
set dcp  [file join $root build local backend_opt_20261021 $var ${var}_routed.dcp]
set out  [file join $root build reports backend_opt_20261021 $var]
set bitdir [file join $root build local backend_opt_20261021 $var]
if {![file exists $dcp]} { error "missing $dcp" }
if {[llength [glob -nocomplain [file join $out bitstream_info.txt]]] > 0} {
    error "bitstream_info.txt already exists -- refusing to overwrite evidence"
}
open_checkpoint $dcp

# what firmware is actually inside the BRAM
foreach c [get_cells -quiet -hier -filter {REF_NAME =~ "blk_mem_gen*"}] {
    puts "BITINFO bram_cell=[get_property NAME $c] ref=[get_property REF_NAME $c]"
}
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "BITINFO pre_write wns=[format %.3f $wns] whs=[format %.3f $whs]"

set bitfile [file join $bitdir "${var}.bit"]
write_bitstream -force -bin_file $bitfile

set fp [open [file join $out bitstream_info.txt] w]
puts $fp "BITSTREAM variant=$var"
puts $fp "dcp=$dcp"
puts $fp "bit=$bitfile"
if {[file exists $bitfile]} {
    puts $fp "bit_size=[file size $bitfile]"
    puts $fp "bit_sha256=[lindex [exec sha256sum $bitfile] 0]"
    if {[file exists [file join $bitdir "${var}.bin"]]} {
        puts $fp "bin_size=[file size [file join $bitdir "${var}.bin"]]"
        puts $fp "bin_sha256=[lindex [exec sha256sum [file join $bitdir "${var}.bin"]] 0]"
    }
}
puts $fp "wns=[format %.3f $wns] whs=[format %.3f $whs]"
puts $fp "clocks={[get_clocks]}"
set pins {}
foreach p [get_ports] { lappend pins "[get_property NAME $p]=[get_property PACKAGE_PIN $p]" }
puts $fp "ports={$pins}"
puts $fp "tool=[version -short] date=[clock format [clock seconds]]"
puts $fp "note=pin/clock set from the recovered baseline const.xdc (clk 50 MHz @ U18); regenerate from a board-specific XDC if the physical board differs; BRAM init is the baseline COE, not the Ascon firmware"
close $fp
puts "BITINFO DONE"
close_project
