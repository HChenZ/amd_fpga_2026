# Independent XSim suite. Does not open or modify released projects.
set root [file normalize [file join [file dirname [info script]] ../..]]
set work [file join $root build local puf_xsim]
create_project p $work -part xc7z020clg400-1
set src {}
foreach f {ro_counter_v2.v ro_puf_core_v2.v puf_key_v2.v puf_aead_v2.v puf_mmio_v2.v} {lappend src $root/src/rtl/keys_v2/$f}
lappend src $root/src/rtl/ascon/crypto_aead.v $root/src/rtl/keys/device_dna.v
foreach f {branch_predictor.v bypass.v cpu_core.v csr_file.v ctrl.v dcache.v divider.v ex_mem.v ex_stage.v icache.v id_ex.v id_stage.v if_id.v if_stage.v mem_stage.v mem_wb.v mult.v regfile.v} {lappend src $root/src/rtl/$f}
lappend src $root/src/rtl/ascon/ascon_ise.v
add_files -norecurse $src
set_property file_type SystemVerilog [get_files *.v]
set_property include_dirs [list $root/src/rtl $root/src/rtl/ascon] [get_filesets sources_1]
set tb [list $root/sim/keys/DNA_PORT_sim.v]
foreach f {tb_ro_health_v2.sv tb_puf_aead_v2.sv tb_puf_mmio_v2.sv tb_puf_cpu_v2.sv} {lappend tb $root/sim/keys_v2/$f}
add_files -fileset sim_1 -norecurse $tb
set_property xsim.simulate.runtime 20ms [get_filesets sim_1]
set hex [file normalize $root/build/local/keys_v2/puf_v2.hex]
if {[info exists ::puf_hex]} {set hex [file normalize $::puf_hex]}
if {![file exists $hex]} {
    set candidates [lsort [glob -nocomplain $root/data/advanced/puf/cpu_v2_*/firmware/puf_v2.hex]]
    if {[llength $candidates]==0} {error "Build and run CPU firmware first, or set ::puf_hex"}
    set hex [lindex $candidates end]
}
set out [file join $root data advanced puf xsim_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
file mkdir $out
foreach top {tb_ro_health_v2 tb_puf_aead_v2 tb_puf_mmio_v2 tb_puf_cpu_v2 tb_puf_cpu_diag_v2} {
    set_property top $top [get_filesets sim_1]
    set_property -dict [list xsim.simulate.xsim.more_options "-testplusarg HEX=$hex"] [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -mode behavioral -simset sim_1
    set logfile $work/p.sim/sim_1/behav/xsim/simulate.log
    set fp [open $logfile r];set log [read $fp];close $fp
    file copy $logfile $out/$top.log
    close_sim
    if {![regexp {TEST_PASS|PUF.*PASS} $log] || [regexp -nocase {fatal:|assertion failed} $log]} {error "Functional gate failed for $top: $out"}
    puts "XSIM_FUNCTIONAL_PASS $top"
}
set fp [open $out/result.txt w];puts $fp "status=PASS vivado=[version -short] tops=5 board=NOT_RUN hex=$hex";close $fp
puts "PUF_XSIM_SUITE_PASS $out"
