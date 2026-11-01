# Verify the frequency-headroom claim on the SAME routed netlist.
# reset_timing + a single create_clock on the input port; the MMCM output clock is
# auto-derived (x2), so the core clock follows the input period. No placement or
# routing is redone: this measures existing arrival times against a longer
# requirement, which is exactly what lowering the frequency does.
set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_routed.dcp]

proc headroom {label in_period} {
    reset_timing
    create_clock -period $in_period -name clk [get_ports clk]
    update_timing -full
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
    set gen [get_clocks -quiet clk_out1_clk_wiz_0]
    set corep [expr {$gen ne "" ? [get_property PERIOD $gen] : "n/a"}]
    puts [format "HEADROOM %-14s in=%s ns core=%s ns WNS=%s ns WHS=%s ns" $label $in_period $corep $wns $whs]
}

headroom reference_100MHz 20.000
headroom at_90MHz         22.222
headroom at_80MHz         25.000
headroom at_75MHz         26.667
puts "HEADROOM PROBE DONE"
