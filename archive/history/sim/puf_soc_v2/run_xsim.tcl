# Use only the NEW PUF SoC session/project. Models are simulation-only.
set root [file normalize [file join [file dirname [info script]] ../..]]
set work $root/board/vivado_zynq7000_xc7z020_puf_v2/work
if {[file normalize [get_property DIRECTORY [current_project]]] ne $work} {error "Wrong project"}
set out $root/data/advanced/puf_soc/xsim_[clock format [clock seconds] -format %Y%m%d_%H%M%S]
file mkdir $out
set_property used_in_simulation false [get_files */keys_v2/ro_array_v2.v]
add_files -fileset sim_1 -norecurse [list $root/sim/puf_soc_v2/ro_array_model.sv $root/sim/keys/DNA_PORT_sim.v $root/sim/ascon/axi_slave_bram.v $root/sim/puf_soc_v2/tb_puf_soc_v2.sv]
set_property target_simulator XSim [current_project]
set_property file_type SystemVerilog [get_files */ascon/*.v]
set_property xsim.compile.xvlog.more_options {} [get_filesets sim_1]
set_property include_dirs [list $root/src/rtl $root/src/rtl/ascon] [get_filesets sim_1]
set_property xsim.simulate.runtime 20ms [get_filesets sim_1]
set_property -dict [list xsim.simulate.xsim.more_options "-testplusarg \"HEX=$root/data/advanced/puf_soc/firmware/puf_v2.hex\""] [get_filesets sim_1]
foreach variant {bfm vendor} {
 if {$variant eq "vendor"} {set_property verilog_define PUF_VENDOR_BRAM [get_filesets sim_1]} else {set_property verilog_define {} [get_filesets sim_1]}
 foreach top {tb_puf_soc_v2 tb_puf_soc_diag_v2} {
    set_property top $top [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -mode behavioral -simset sim_1
    set d $work/puf_soc.sim/sim_1/behav/xsim
    file mkdir $out/${variant}_$top
    foreach f [glob -nocomplain $d/*.log $d/*.tcl $d/*.bat $d/*.prj] {file copy $f $out/${variant}_$top/[file tail $f]}
    set fp [open $d/simulate.log r]; set log [read $fp]; close $fp
    close_sim
    if {[string first "TEST_PASS tb_puf_soc_v2" $log]<0 || [regexp -nocase {fatal:|ERROR:} $log]} {error "XSim functional failure $top: $out"}
 }
}
set fp [open $out/result.txt w]
puts $fp "PASS normal and diagnostic with AXI BRAM BFM AND vendor board BRAM wrapper; modeled RO/DNA; board NOT_MEASURED; [version -short]"
close $fp
puts "PUF_SOC_XSIM_PASS $out"
