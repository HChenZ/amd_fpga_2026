# Floorplan / directive experiments on the A1 netlist (alignment narrowed, WNS +0.016).
# The A1 wall is route-dominated (79% route on pc -> if/ex_mem CE), so floorplanning
# is worth re-testing here even though it did nothing on the pre-A1 netlist.
# Read-only on src/ and on the A1 project: every variant starts from the same A1
# post-opt checkpoint and writes into its own directory.
#
#   vivado -mode batch -source build/sweep_margin_a1.tcl -notrace -tclargs <variant>
#
# variants:
#   nopb_et    no pblock          place ExtraTimingOpt        route AggressiveExplore
#   pb2_et     X50Y0:X113Y99      place ExtraTimingOpt        route AggressiveExplore
#   pb3_epp    X50Y0:X113Y149     place ExtraPostPlacementOpt route AggressiveExplore
#   nopb_mgi   no pblock          place ExtraTimingOpt        route MoreGlobalIterations
set root [file normalize [file join [file dirname [info script]] ..]]
set variant [lindex $argv 0]
if {$variant eq ""} { error "usage: -tclargs <nopb_et|pb2_et|pb3_epp|nopb_mgi>" }
set src_dcp [file join $root build local bce_timing_a1 riscv_vivado_project.runs impl_m top_pl_bram_opt.dcp]
set workdir [file join $root build local margin_a1_20261020 $variant]
set repdir  [file join $root build reports margin_a1_20261020 $variant]
if {![file exists $src_dcp]} { error "missing A1 checkpoint: $src_dcp" }
file mkdir $workdir
file mkdir $repdir

set pblock ""
set place_d ExtraTimingOpt
set route_d AggressiveExplore
switch -- $variant {
    nopb_et  { }
    pb2_et   { set pblock {SLICE_X50Y0:SLICE_X113Y99} }
    pb3_epp  { set pblock {SLICE_X50Y0:SLICE_X113Y149} ; set place_d ExtraPostPlacementOpt }
    nopb_mgi { set route_d MoreGlobalIterations }
    default  { error "unknown variant $variant" }
}

open_checkpoint $src_dcp
if {[llength [get_clocks]] == 0} { error "no clocks in checkpoint" }
puts "A1 VARIANT $variant pblock=$pblock place=$place_d route=$route_d"
if {$pblock ne ""} {
    create_pblock pb_cpu_core
    add_cells_to_pblock pb_cpu_core [get_cells -quiet u_soc_axi_top/u_soc_top/u_cpu_core]
    resize_pblock pb_cpu_core -add $pblock
}
place_design -directive $place_d
phys_opt_design -directive AggressiveExplore
route_design -directive $route_d
phys_opt_design -directive AggressiveExplore

report_utilization -file [file join $repdir route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $repdir route_timing.rpt]
report_timing -delay_type max -max_paths 12 -file [file join $repdir route_paths.rpt]
report_route_status -file [file join $repdir route_status.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set fpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
set tns 0.0
foreach q $fpaths { set tns [expr {$tns + [get_property SLACK $q]}] }
set fp [open [file join $repdir result.txt] w]
puts $fp "RESULT a1_variant=$variant pblock=$pblock place=$place_d route=$route_d wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
close $fp
puts "RESULT a1_variant=$variant wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs]"
write_checkpoint -force [file join $workdir ${variant}_routed.dcp]
close_project
puts "A1 MARGIN $variant COMPLETE"
