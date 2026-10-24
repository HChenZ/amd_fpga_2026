# Hold-side repair on an already-routed champion netlist: no re-place, no re-route of
# the whole design -- only the tool's hold-fix pass, which adds delay at the sinks that
# are short at the fast corner.
#
#   vivado -mode batch -source build/backend_opt_20261021/run_holdfix.tcl -notrace \
#          -tclargs <holdfix-arm>
#
# arms: hf_explore | hf_aggr | hf_aggr_both
# The base netlist is the campaign winner (pl_ndh_crit200_ntr, WNS +0.138 / WHS +0.017).
set root [file normalize [file join [file dirname [info script]] .. ..]]
set arm  [lindex $argv 0]
if {$arm eq ""} { error "usage: -tclargs <hf_explore|hf_aggr|hf_aggr_both>" }
set base [file join $root build local backend_opt_20261021 pl_ndh_crit200_ntr pl_ndh_crit200_ntr_routed.dcp]
if {![file exists $base]} { error "missing base checkpoint $base" }
set workdir [file join $root build local backend_opt_20261021 $arm]
set repdir  [file join $root build reports backend_opt_20261021 $arm]
file mkdir $workdir
file mkdir $repdir
if {[llength [glob -nocomplain [file join $repdir result.txt]]] > 0} {
    error "arm $arm already has a result (refusing to overwrite evidence)"
}

proc readback {tag} {
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
    puts "HOLDFIX $tag wns=[format %.3f $wns] whs=[format %.3f $whs]"
    return [list $wns $whs]
}

open_checkpoint $base
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2" }
lassign [readback "$arm BEFORE"] wns0 whs0
set luts0 [llength [get_cells -hier -quiet -filter {PRIMITIVE_GROUP == "LUT"}]]

switch -- $arm {
    hf_explore   { phys_opt_design -directive ExploreWithHoldFix }
    hf_aggr      { phys_opt_design -directive ExploreWithAggressiveHoldFix }
    hf_aggr_both { phys_opt_design -directive ExploreWithAggressiveHoldFix
                   phys_opt_design -aggressive_hold_fix }
    hf_clock     { phys_opt_design -clock_opt }
    hf_clock_hold { phys_opt_design -clock_opt
                    phys_opt_design -aggressive_hold_fix }
    default { error "unknown arm $arm" }
}

lassign [readback "$arm AFTER"] wns1 whs1
set luts1 [llength [get_cells -hier -quiet -filter {PRIMITIVE_GROUP == "LUT"}]]

report_utilization -file [file join $repdir route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $repdir route_timing.rpt]
report_timing -delay_type min -max_paths 20 -nworst 1 -input_pins -file [file join $repdir hold_paths.rpt]
report_route_status -file [file join $repdir route_status.rpt]
set fpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
set tns 0.0
foreach p $fpaths { set tns [expr {$tns + [get_property SLACK $p]}] }
set hpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -hold -slack_less_than 0.0]

set fp [open [file join $repdir result.txt] w]
puts $fp "RESULT variant=$arm wns=[format %.3f $wns1] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs1] hold_failing=[llength $hpaths] luts=$luts1 luts_before=$luts0"
puts $fp "BEFORE wns=[format %.3f $wns0] whs=[format %.3f $whs0] base=pl_ndh_crit200_ntr_routed.dcp"
puts $fp "KNOBS holdfix=$arm (post-route only, no re-place/re-route)"
puts $fp "SOURCE tool=[version -short] date=[clock format [clock seconds]]"
close $fp
puts "RESULT variant=$arm wns=[format %.3f $wns1] whs=[format %.3f $whs1] dwns=[format %.3f [expr {$wns1-$wns0}]] dwhs=[format %.3f [expr {$whs1-$whs0}]]"
write_checkpoint -force [file join $workdir ${arm}_routed.dcp]
close_project
puts "HOLDFIX $arm COMPLETE"
