# Sanity check of the candidate starting checkpoints: clocks, black boxes, WNS.
#   vivado -mode batch -source build/backend_opt_20261021/probe_dcp.tcl -notrace
set root [file normalize [file join [file dirname [info script]] .. ..]]
set cands [list \
    [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_opt.dcp] \
    [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_postroute_physopt.dcp] \
    [file join $root build local bce_timing_a1_pr riscv_vivado_project.runs synth_1 top_pl_bram.dcp] ]
foreach dcp $cands {
    if {![file exists $dcp]} { puts "MISSING $dcp" ; continue }
    open_checkpoint $dcp
    set clks {}
    foreach c [get_clocks] { lappend clks "[get_property NAME $c]@[format %.3f [get_property PERIOD $c]]ns" }
    set bb [llength [get_cells -hier -quiet -filter {IS_BLACKBOX}]]
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set placed [llength [get_cells -hier -quiet -filter {IS_PRIMITIVE && SITE != ""}]]
    set leaf [llength [get_cells -hier -quiet -filter {IS_PRIMITIVE}]]
    puts "DCP [file tail [file dirname $dcp]]/[file tail $dcp] clocks={$clks} blackboxes=$bb wns=[format %.3f $wns] placed=$placed/$leaf"
    close_design
}
puts "PROBE_DCP DONE"
