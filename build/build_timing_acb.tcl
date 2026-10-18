# V09: two strategies on a single fresh, immutable RTL/project snapshot.
# Launch through Vivado MCP: source .../build/build_timing_acb.tcl
# Set acb_root before sourcing when the session is outside the repository.
if {![info exists acb_root]} {set acb_root [file normalize [file join [file dirname [info script]] ..]]}
set root $acb_root
set work [file join $root build local timing_acb_impl]
set report [file join $root build reports timing_acb_20261018]
if {[file exists $work] || [file exists $report]} {error "Refusing to overwrite V09 work or report"}
if {![string match "2025.2*" [version -short]]} {error "Requires Vivado 2025.2"}
file copy [file join $root board vivado_zynq7000_xc7z020_baseline] $work
file copy [file join $root src rtl] [file join $work development_rtl]
file mkdir $report
cd $work
set rtl [file join $work development_rtl]
open_project [file join $work riscv_vivado_project.xpr]
if {[get_property PART [current_project]] ne "xc7z020clg400-1"} {error "Unexpected part"}
remove_files [get_files -of_objects [get_filesets sources_1] -filter {FILE_TYPE == Verilog || FILE_TYPE == "Verilog Header"}]
set sources [concat [glob [file join $rtl *.v]] [glob -nocomplain [file join $rtl *.vh]]]
foreach f [glob [file join $rtl ascon *]] {
    if {[file extension $f] in {.v .vh} && ![string match "*_tb.v" $f]} {lappend sources $f}
}
add_files -norecurse $sources
foreach f $sources {if {[file extension $f] eq ".v"} {set_property file_type SystemVerilog [get_files $f]}}
set_property include_dirs [list $rtl [file join $rtl ascon]] [get_filesets sources_1]
set_property top top_pl_bram [get_filesets sources_1]
update_compile_order -fileset sources_1
set fp [open [file join $report build_context.txt] w]
puts $fp "[version]\npart=[get_property PART [current_project]]\ntop=top_pl_bram\ndate=[clock format [clock seconds]]\nsource_head=[exec git -C $root rev-parse HEAD]\nsource_snapshot=$rtl"
puts $fp "constraints: [get_files -of_objects [get_filesets constrs_1]]"
puts $fp "strategies=Performance_ExplorePostRoutePhysOpt,Performance_ExploreWithRemap; jobs=2; clock/XDC unchanged"
foreach ip [get_ips] {
    puts $fp "IP $ip [get_property IPDEF $ip] locked=[get_property IS_LOCKED $ip]"
    if {[get_property IS_LOCKED $ip]} {close $fp;error "Locked IP: $ip"}
}
close $fp
# Store hashes of the actual build snapshot, not the later live working tree.
exec python [file join $root build snapshot_rtl_hashes.py] $rtl [file join $report source_hashes.json]
generate_target all [get_ips]
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
open_run synth_1
report_utilization -file [file join $report synth_utilization.rpt]
report_timing_summary -file [file join $report synth_timing.rpt]
close_design
source [file join $root build report_timing_endpoints.tcl]
foreach {name strategy} {postroute Performance_ExplorePostRoutePhysOpt remap Performance_ExploreWithRemap} {
    set dir [file join $report $name]
    file mkdir $dir
    create_run acb_$name -parent_run synth_1 -flow {Vivado Implementation 2025} -strategy $strategy -constrset constrs_1 -part xc7z020clg400-1
    launch_runs acb_$name -to_step {phys_opt_design (Post-Route)} -jobs 2
    wait_on_run acb_$name
    if {[get_property PROGRESS [get_runs acb_$name]] ne "100%"} {error "Implementation failed: $name"}
    open_run acb_$name
    report_utilization -file [file join $dir route_utilization.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained -file [file join $dir route_timing.rpt]
    report_timing -delay_type max -max_paths 30 -file [file join $dir route_paths.rpt]
    report_route_status -file [file join $dir route_status.rpt]
    export_timing_endpoints $dir $strategy
    write_checkpoint [file join $work acb_${name}_routed.dcp]
    close_design
}
close_project
puts "TIMING_ACB BUILD COMPLETE"
