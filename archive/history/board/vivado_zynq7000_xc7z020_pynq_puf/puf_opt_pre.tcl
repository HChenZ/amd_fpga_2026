# impl_1 opt_design pre-hook: the netlist exists here, unlike when XDC is read.
# 1) Acknowledge the intentional RO loops (same pin-based method as build/keys_ro_allow_loops.tcl).
# 2) Re-create the RO pblock of build/keys_ro_pblock.xdc with the BD hierarchy of this overlay.
#    The original XDC path (u_soc_axi_top/...) would silently match nothing inside the BD wrapper.
source [file join [file dirname [file normalize [info script]]] ../../build/keys_ro_allow_loops.tcl]
set ro_luts [get_cells -quiet -hier -filter {NAME =~ "*u_ro/*" && REF_NAME =~ "LUT*"}]
if {[llength $ro_luts] != 1280} {error "Expected 1280 RO LUTs, found [llength $ro_luts]"}
set puf [get_cells -quiet -hier -filter {NAME =~ "*/u_puf_key/u_puf"}]
if {[llength $puf] != 1} {error "Expected exactly one u_puf_key/u_puf instance, found [llength $puf]"}
create_pblock pb_ro_puf
add_cells_to_pblock pb_ro_puf $puf
resize_pblock pb_ro_puf -add {SLICE_X60Y115:SLICE_X113Y149}
puts "PUF_PBLOCK: cell=$puf ro_luts=[llength $ro_luts]"
