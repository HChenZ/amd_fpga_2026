# Timing-margin experiments: post-opt netlist -> place / phys_opt / route variants.
# Read-only on the source project, RTL, board XDC and the reference DCP.
# Every variant starts from the SAME post-opt checkpoint of the accepted
# Performance_ExploreWithRemap run (WNS +0.007), so differences are purely
# place/route + floorplan, not RTL or synthesis.
#
#   vivado -mode batch -source build/sweep_margin_phys.tcl -notrace -tclargs <variant>
#
# variants:
#   pb2_et      pblock X50Y0:X113Y99   place ExtraTimingOpt  physopt AggressiveExplore
#   pb3_epp     pblock X50Y0:X113Y149  place ExtraPostPlacementOpt
#   nopb_et     no pblock              place ExtraTimingOpt  (control = current state)
#   pb2_alt     pblock X50Y0:X113Y99   place ExtraTimingOpt  physopt AlternateFlowWithRetiming
#
# All variants: route -directive AggressiveExplore, then post-route
# phys_opt_design -directive AggressiveExplore (setup only; hold is re-checked).

set root   [file normalize [file join [file dirname [info script]] ..]]
set variant [lindex $argv 0]
if {$variant eq ""} { error "usage: -tclargs <pb2_et|pb3_epp|nopb_et|pb2_alt>" }

set src_dcp [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_opt.dcp]
set workdir [file join $root build local margin_20261020 $variant]
set repdir  [file join $root build reports margin_20261020 $variant]
file mkdir $workdir
file mkdir $repdir
if {![file exists $src_dcp]} { error "missing reference checkpoint: $src_dcp" }
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2" }

set pblock   ""
set place_d  ExtraTimingOpt
set physopt_d AggressiveExplore
switch -- $variant {
    pb2_et  { set pblock {SLICE_X50Y0:SLICE_X113Y99} }
    pb3_epp { set pblock {SLICE_X50Y0:SLICE_X113Y149} ; set place_d ExtraPostPlacementOpt }
    nopb_et { }
    pb2_alt { set pblock {SLICE_X50Y0:SLICE_X113Y99} ; set physopt_d AlternateFlowWithRetiming }
    default { error "unknown variant $variant" }
}

open_checkpoint $src_dcp
set clks [get_clocks]
if {[llength $clks] == 0} { error "no clocks after open_checkpoint - constraints not embedded" }
puts "VARIANT $variant clocks=$clks pblock=$pblock place=$place_d physopt=$physopt_d"

if {$pblock ne ""} {
    if {[llength [get_pblocks -quiet pb_cpu_core]] > 0} { delete_pblocks pb_cpu_core }
    create_pblock pb_cpu_core
    add_cells_to_pblock pb_cpu_core [get_cells -quiet u_soc_axi_top/u_soc_top/u_cpu_core]
    resize_pblock pb_cpu_core -add $pblock
    puts "PBLOCK [get_property GRID_RANGES [get_pblocks pb_cpu_core]]"
}

place_design -directive $place_d
phys_opt_design -directive $physopt_d
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore

report_utilization -file [file join $repdir route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $repdir route_timing.rpt]
report_timing -delay_type max -max_paths 12 -file [file join $repdir route_paths.rpt]
report_route_status -file [file join $repdir route_status.rpt]

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set fpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
set fep [llength $fpaths]
set tns 0.0
foreach p $fpaths { set tns [expr {$tns + [get_property SLACK $p]}] }
set luts [llength [get_cells -hier -filter {PRIMITIVE_GROUP == "LUT"}]]

set ctx [open [file join $repdir result.txt] w]
puts $ctx "RESULT variant=$variant wns=[format %.3f $wns] tns=[format %.3f $tns] failing=$fep whs=[format %.3f $whs] pblock=$pblock place=$place_d physopt=$physopt_d"
puts $ctx "source_head=[exec git -C $root rev-parse --short HEAD] date=[clock format [clock seconds]] host=[exec hostname]"
close $ctx
puts "RESULT variant=$variant wns=[format %.3f $wns] tns=[format %.3f $tns] failing=$fep whs=[format %.3f $whs]"

write_checkpoint -force [file join $workdir ${variant}_routed.dcp] -routing
close_project
puts "MARGIN VARIANT $variant COMPLETE"
