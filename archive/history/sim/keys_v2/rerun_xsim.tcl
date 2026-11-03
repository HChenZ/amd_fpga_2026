# Source only after opening the existing isolated build/local/puf_xsim/p.xpr.
# Never create/force a project; preserve every invocation in a new directory.
set root [file normalize [file join [file dirname [info script]] ../..]]
set work [file normalize [get_property DIRECTORY [current_project]]]
if {$work ne [file normalize $root/build/local/puf_xsim]} {error "Wrong project: $work"}
set out [file join $root data advanced puf xsim_final_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
file mkdir $out
set ::puf_final_xsim_out $out
set hex [file normalize $root/data/advanced/puf/cpu_v2_20261030_010334_900335/firmware/puf_v2.hex]
if {[info exists ::puf_hex]} {set hex [file normalize $::puf_hex]}
if {![file exists $hex]} {error "Missing verified firmware $hex"}
set_property target_simulator XSim [current_project]
set fp [open $out/project_inputs.txt w]
puts $fp "version=[version]\npart=[get_property PART [current_project]]\nproject=$work\nhex=$hex"
foreach f [get_files] {puts $fp "source=[get_property NAME $f]"}
close $fp
foreach top {tb_ro_health_v2 tb_puf_aead_v2 tb_puf_mmio_v2 tb_puf_cpu_v2 tb_puf_cpu_diag_v2} {
    set_property top $top [get_filesets sim_1]
    set limit [expr {[string match tb_puf_cpu* $top] ? "20ms" : "2ms"}]
    set_property xsim.simulate.runtime $limit [get_filesets sim_1]
    set_property -dict [list xsim.simulate.xsim.more_options "-testplusarg HEX=$hex"] [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -mode behavioral -simset sim_1
    set dir $work/p.sim/sim_1/behav/xsim
    set fp [open $dir/simulate.log r]; set log [read $fp]; close $fp
    file mkdir $out/$top
    foreach f [glob -nocomplain $dir/*.log $dir/*.tcl $dir/*.bat $dir/*.prj] {file copy $f $out/$top/[file tail $f]}
    close_sim
    set marker [expr {$top eq "tb_puf_cpu_diag_v2" ? "TEST_PASS tb_puf_cpu_v2 diagnostic=1" : "TEST_PASS $top"}]
    if {[string first $marker $log]<0 || [regexp -nocase {fatal:|assertion failed|ERROR:} $log]} {error "Functional gate failed $top in $out"}
    puts "XSIM_FUNCTIONAL_PASS $top"
}
set fp [open $out/result.txt w]; puts $fp "status=PASS tops=5 version=[version -short] hex=$hex board=NOT_RUN"; close $fp
puts "PUF_XSIM_FINAL_PASS $out"
