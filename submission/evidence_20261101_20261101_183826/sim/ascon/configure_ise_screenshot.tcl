# Vivado 2025.2: attach the existing self-checking ISE TB to the open PUF3 project.
# Run from the Vivado Tcl Console: source <repo>/sim/ascon/configure_ise_screenshot.tcl
# Only the new simulation fileset is configured; no synthesis/implementation runs.
set ise_root [file normalize [file join [file dirname [info script]] ../..]]
if {[version -short] ne "2025.2"} {error "This configuration is verified with Vivado 2025.2"}
if {[get_property PART [current_project]] ne "xc7z020clg400-1"} {error "Unexpected part"}
if {[get_property TOP [get_filesets sources_1]] ne "pynq_puf3_wrapper"} {error "Open the PUF3 project first"}
set ise_simset sim_ise_screenshot
if {![llength [get_filesets -quiet $ise_simset]]} {create_fileset -simset $ise_simset}
set ise_fs [get_filesets $ise_simset]
set ise_tb [file join $ise_root sim/ascon/tb_key_ise.v]
if {![llength [get_files -quiet -of_objects $ise_fs $ise_tb]]} {
    add_files -fileset $ise_simset -norecurse $ise_tb
}
set_property FILE_TYPE SystemVerilog [get_files -of_objects $ise_fs $ise_tb]
set_property SOURCE_SET sources_1 $ise_fs
set_property TOP tb_key_ise $ise_fs
set_property TOP_LIB xil_defaultlib $ise_fs
set_property INCREMENTAL false $ise_fs
set_property INCLUDE_DIRS [list [file join $ise_root src/rtl] [file join $ise_root src/rtl/ascon]] $ise_fs
set_property target_simulator XSim [current_project]
set_property xsim.elaborate.debug_level all $ise_fs
set_property xsim.simulate.runtime {} $ise_fs
set_property xsim.simulate.log_all_signals false $ise_fs
set_property xsim.simulate.no_quit true $ise_fs
set ise_out [file join $ise_root build/local/pynq_puf3/ise_screenshot]
file mkdir $ise_out
set_property xsim.simulate.wdb [file join $ise_out ise_screenshot.wdb] $ise_fs
set_property xsim.simulate.custom_tcl [file join $ise_root sim/ascon/run_ise_screenshot.tcl] $ise_fs
current_fileset -simset $ise_fs
update_compile_order -fileset $ise_simset
set ise_fp [open [file join $ise_out configuration.txt] w]
puts $ise_fp "tool=[version -short] part=[get_property PART [current_project]] design_top=[get_property TOP [get_filesets sources_1]]"
puts $ise_fp "project=[get_property NAME [current_project]] directory=[get_property DIRECTORY [current_project]]"
puts $ise_fp "simset=$ise_simset simulation_top=[get_property TOP $ise_fs] backend=XSim mode=behavioral"
puts $ise_fp "tb=$ise_tb vectors=[file join $ise_root data/ascon/permutation.mem]"
puts $ise_fp "synth_status=[get_property STATUS [get_runs synth_1]] impl_status=[get_property STATUS [get_runs impl_1]]"
puts $ise_fp "custom_tcl=[get_property xsim.simulate.custom_tcl $ise_fs]"
close $ise_fp
puts "ISE screenshot simulation configured: $ise_simset / tb_key_ise"
puts "Run Simulation -> Run Behavioral Simulation; the test and focused waveform are automatic."
