# Rebuild a COPY of the recovered XC7Z020 project. Never open/save the original.
# vivado -mode batch -source build/build_ascon_review.tcl -notrace
set root [file normalize [file join [file dirname [info script]] ..]]
set work [file join $root build local ascon_vivado]
if {$argc > 0} {
    if {![regexp {^[a-z0-9_-]+$} [lindex $argv 0]]} {error "Build name must be a simple lowercase leaf"}
    set work [file join $root build local [lindex $argv 0]]
}
set resume [expr {$argc > 1 && [lindex $argv 1] eq "resume"}]
set report [file join $root build reports ascon_key_lifecycle]
if {$argc > 2} {
    if {![regexp {^[a-z0-9_-]+$} [lindex $argv 2]]} {error "Report name must be a simple lowercase leaf"}
    set report [file join $root build reports [lindex $argv 2]]
}
if {[file exists $work] && !$resume} { error "Refusing to overwrite existing build: $work" }
if {!$resume && [llength [glob -nocomplain -directory $report *]] > 0} {
    error "Refusing to overwrite existing reports: $report; supply a new third argument"
}
file mkdir $report
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2; no automatic upgrade" }
if {$resume} {
    cd $work
    open_project [file join $work riscv_vivado_project.xpr]
    if {[get_property PART [current_project]] ne "xc7z020clg400-1"} {error "Unexpected part"}
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Resume requires completed synthesis"}
} else {
file mkdir [file dirname $work]
file copy [file join $root board vivado_zynq7000_xc7z020_baseline] $work
file copy [file join $root src rtl] [file join $work development_rtl]
cd $work
set rtl [file join $work development_rtl]
open_project [file join $work riscv_vivado_project.xpr]
if {[get_property PART [current_project]] ne "xc7z020clg400-1"} { error "Unexpected part" }
# Keep recovered XCI, COE, XDC; replace ONLY the copied imports source set.
set old [get_files -of_objects [get_filesets sources_1] -filter {FILE_TYPE == Verilog || FILE_TYPE == "Verilog Header"}]
remove_files $old
set sources [concat [glob [file join $rtl *.v]] [glob -nocomplain [file join $rtl *.vh]]]
foreach f [glob [file join $rtl ascon *]] {
    if {([file extension $f] eq ".v" || [file extension $f] eq ".vh") && ![string match "*_tb.v" $f]} { lappend sources $f }
}
add_files -norecurse $sources
foreach f $sources {
    if {[file extension $f] eq ".v"} {set_property file_type SystemVerilog [get_files $f]}
}
set_property include_dirs [list $rtl [file join $rtl ascon]] [get_filesets sources_1]
set_property top top_pl_bram [get_filesets sources_1]
update_compile_order -fileset sources_1
set fp [open [file join $report build_context.txt] w]
puts $fp "[version]\npart=[get_property PART [current_project]]\ntop=top_pl_bram\nboard=unknown\nsource_head=[exec git -C $root rev-parse HEAD]"
puts $fp "source files: [get_files -compile_order sources -used_in synthesis]"
puts $fp "constraints: [get_files -of_objects [get_filesets constrs_1]]"
foreach ip [get_ips] {
    puts $fp "IP $ip [get_property IPDEF $ip] locked=[get_property IS_LOCKED $ip]"
    if {[get_property IS_LOCKED $ip]} {close $fp;error "Locked IP: $ip; upgrade not authorized by this script"}
}
close $fp
report_ip_status -file [file join $report ip_status.rpt]
generate_target all [get_ips]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"}
open_run synth_1
report_utilization -file [file join $report synth_utilization.rpt]
report_timing_summary -file [file join $report synth_timing.rpt]
close_design
}
# An independent implementation run avoids stale GeneratedRun metadata from the archive.
create_run key_review_impl -parent_run synth_1 -flow {Vivado Implementation 2025} -strategy {Vivado Implementation Defaults} -constrset constrs_1 -part xc7z020clg400-1
launch_runs key_review_impl -to_step route_design -jobs 4
wait_on_run key_review_impl
if {[get_property PROGRESS [get_runs key_review_impl]] ne "100%"} {error "Implementation failed: [get_property STATUS [get_runs key_review_impl]]"}
open_run key_review_impl
report_utilization -file [file join $report route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report route_timing.rpt]
report_timing -delay_type max -max_paths 20 -file [file join $report route_paths.rpt]
report_clock_interaction -file [file join $report clock_interaction.rpt]
check_timing -verbose -file [file join $report check_timing.rpt]
report_drc -file [file join $report route_drc.rpt]
report_methodology -file [file join $report methodology.rpt]
write_checkpoint -force [file join $work reviewed_routed.dcp]
# No bitstream generation or programming; inherited board pins are unverified.
close_project
