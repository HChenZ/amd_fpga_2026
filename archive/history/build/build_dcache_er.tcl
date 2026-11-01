# Independent timing measurement of the modified dcache.v (MISS_CAPTURE pipeline).
# Fresh isolated copy; the running strategy sweep project is NOT touched.
# vivado -mode batch -source build/build_dcache_pipe.tcl -notrace -log ... [-tclargs <tag>]
# Optional <tag> gives a separate work/report dir so earlier evidence is kept.
set root [file normalize [file join [file dirname [info script]] ..]]
set tag [expr {[llength $argv] > 0 ? "_[lindex $argv 0]" : ""}]
set work [file join $root build local ascon_dcache_pipe$tag]
set report [file join $root build reports dcache_pipe_20261018$tag]
if {[file exists $work]} {error "Refusing to overwrite existing build: $work"}
if {![string match "2025.2*" [version -short]]} {error "Requires Vivado 2025.2"}
file mkdir [file dirname $work]
file copy [file join $root board vivado_zynq7000_xc7z020_baseline] $work
file copy [file join $root src rtl] [file join $work development_rtl]
file mkdir $report
cd $work
set rtl [file join $work development_rtl]
open_project [file join $work riscv_vivado_project.xpr]
if {[get_property PART [current_project]] ne "xc7z020clg400-1"} {error "Unexpected part"}
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
puts $fp "[version]\npart=[get_property PART [current_project]]\ntop=top_pl_bram\nhost=[exec hostname]\ndate=[clock format [clock seconds]]\nsource_head=[exec git -C $root rev-parse HEAD]"
puts $fp "worktree_dirty_rtl=dcache.v (MISS_CAPTURE pipeline, uncommitted) tag=$tag"
puts $fp "constraints: [get_files -of_objects [get_filesets constrs_1]]"
foreach ip [get_ips] {
    puts $fp "IP $ip [get_property IPDEF $ip] locked=[get_property IS_LOCKED $ip]"
    if {[get_property IS_LOCKED $ip]} {close $fp;error "Locked IP: $ip"}
}
close $fp
generate_target all [get_ips]
launch_runs synth_1 -jobs 6
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
open_run synth_1
report_utilization -file [file join $report synth_utilization.rpt]
report_timing_summary -file [file join $report synth_timing.rpt]
close_design
create_run dcache_pipe_er -parent_run synth_1 -flow {Vivado Implementation 2025} -strategy Performance_ExploreWithRemap -constrset constrs_1 -part xc7z020clg400-1
launch_runs dcache_pipe_er -to_step {phys_opt_design (Post-Route)} -jobs 6
wait_on_run dcache_pipe_er
if {[get_property PROGRESS [get_runs dcache_pipe_er]] ne "100%"} {error "Implementation failed: [get_property STATUS [get_runs dcache_pipe_er]]"}
open_run dcache_pipe_er
report_utilization -file [file join $report route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report route_timing.rpt]
report_timing -delay_type max -max_paths 20 -file [file join $report route_paths.rpt]
report_route_status -file [file join $report route_status.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set fpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
set fep [llength $fpaths]
set tns 0.0
foreach p $fpaths { set tns [expr {$tns + [get_property SLACK $p]}] }
puts "RESULT wns=[format %.3f $wns] tns=[format %.3f $tns] failing=$fep whs=[format %.3f $whs]"
write_checkpoint [file join $work dcache_pipe_routed.dcp]
close_project
puts "DCACHE_PIPE BUILD COMPLETE"
