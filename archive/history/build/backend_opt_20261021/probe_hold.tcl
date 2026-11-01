# Hold-side attribution of one routed variant: who owns WHS, how thin is it, and how
# many endpoints are inside the project's +0.05 ns hold gate.
#   vivado -mode batch -source build/backend_opt_20261021/probe_hold.tcl -notrace \
#          -tclargs pl_ndh_crit200_ntr
set root    [file normalize [file join [file dirname [info script]] .. ..]]
set variant [lindex $argv 0]
set dcp [file join $root build local backend_opt_20261021 $variant ${variant}_routed.dcp]
if {![file exists $dcp]} { error "missing $dcp" }
set outdir [file join $root build reports backend_opt_20261021 $variant]
open_checkpoint $dcp

set MODS {ascon_mmio ascon_ise icache dcache if_stage if_id id_ex ex_stage csr_file ex_mem mem_wb predictor uart_ctrl cpi_cnt bus_interconnect}
proc owner {pin} {
    global MODS
    foreach m $MODS { if {[string match "*/[set m]/*" $pin]} { return $m } }
    return other
}

set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "HOLD $variant wns=[format %.3f $wns] whs=[format %.3f $whs]"

# all hold paths below the gate
set paths [get_timing_paths -quiet -max_paths 200000 -nworst 1 -hold -slack_less_than 0.05]
set n [llength $paths]
array unset own ; array set own {}
set worst {}
foreach p $paths {
    set o [owner [get_property ENDPOINT_PIN $p]]
    if {![info exists own($o)]} { set own($o) 0 }
    incr own($o)
}
foreach k [lsort [array names own]] { lappend worst "$k=$own($k)" }
puts "HOLD $variant endpoints_below_0p05=$n owners={[join $worst { }]}"

# how thin: count at several hold thresholds
foreach t {0.01 0.02 0.03 0.05 0.075 0.1} {
    set c [llength [get_timing_paths -quiet -max_paths 200000 -nworst 1 -hold -slack_less_than $t]]
    puts "HOLD $variant lt$t=$c"
}

report_timing -delay_type min -max_paths 20 -nworst 1 -input_pins \
    -file [file join $outdir hold_paths.rpt]
puts "HOLD $variant DONE"
close_project
