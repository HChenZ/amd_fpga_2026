# Source after puf_xsim.tcl in its isolated project. Physical structure inspection,
# not RO-frequency signoff: actual oscillator bounds require hardware measurements.
set root [file normalize [file join [file dirname [info script]] ../..]]
add_files -norecurse [list $root/src/rtl/keys_v2/ro_array_v2.v $root/src/rtl/keys_v2/puf_physical_v2.v $root/src/rtl/keys_v2/puf_mmio_physical_v2.v]
set_property file_type SystemVerilog [get_files $root/src/rtl/keys_v2/*.v]
set_property top puf_mmio_physical_v2 [current_fileset]
update_compile_order -fileset sources_1
puts "PUF_PHYSICAL_OOC_READY"
