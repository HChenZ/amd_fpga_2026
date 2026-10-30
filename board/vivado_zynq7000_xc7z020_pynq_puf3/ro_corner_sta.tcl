# Analysis-only RO-domain timing check on a routed checkpoint (does not change the bit).
#   vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf/ro_corner_sta.tcl -tclargs <routed.dcp> <out_dir>
# 1) ro_clk: create_generated_clock (clk/4 from ro_clk_div_reg[1]); no measurement needed.
# 2) RO oscillators: period bounds come from the vendor delay model of every routed ring
#    (sum of LUT rise+fall arcs + 2x net delays), FAST_MIN and SLOW_MAX per ring.
#    Each corner is analysed with the RO period of the same corner, so ring and counter
#    logic track together; no board measurement and no invented margin.
set dcp [lindex $argv 0]
set out [file normalize [lindex $argv 1]]
file mkdir $out
open_checkpoint $dcp
set fp [open $out/ro_corner_sta.txt w]
proc say {msg} {global fp; puts $msg; puts $fp $msg; flush $fp}
say "dcp=[file normalize $dcp] tool=[version -short]"

if {![llength [get_clocks -quiet ro_clk]]} {
    create_generated_clock -name ro_clk -divide_by 4 \
        -source [get_pins -hier -filter {NAME =~ "*u_soc_top/ro_clk_div_reg[1]/C"}] \
        [get_pins -hier -filter {NAME =~ "*u_soc_top/ro_clk_div_reg[1]/Q"}]
}

proc pin_of {cell name} {return [get_pins -of_objects $cell -filter "REF_PIN_NAME == $name"]}
proc stage {cell from corner} {
    set p [pin_of $cell $from]
    set a [get_timing_arcs -from $p -to [pin_of $cell O]]
    set d [get_net_delays -of_objects [get_nets -of_objects $p] -to $p]
    return [expr {[lindex [get_property DELAY_${corner}_RISE $a] 0] + [lindex [get_property DELAY_${corner}_FALL $a] 0] + 2.0*[get_property $corner $d]}]
}
set nands [get_cells -hier -filter {NAME =~ "*u_ro/u_nand"}]
set invs  [get_cells -hier -filter {NAME =~ "*u_ro/g_inv*"}]
array set ring {}
foreach c $invs {lappend ring([string range $c 0 [string last /g_inv $c]-1]) $c}
set fast {}; set slow {}
foreach n $nands {
    set r [string range $n 0 end-7]
    if {[llength $ring($r)] != 4} {error "ring $r: [llength $ring($r)] inverters"}
    set tf [stage $n I1 FAST_MIN]; set ts [stage $n I1 SLOW_MAX]
    foreach c $ring($r) {set tf [expr {$tf + [stage $c I0 FAST_MIN]}]; set ts [expr {$ts + [stage $c I0 SLOW_MAX]}]}
    lappend fast $tf; lappend slow $ts
}
set fast [lsort -real $fast]; set slow [lsort -real $slow]
# delays are in ps; fastest ring = smallest period
set pf [expr {[lindex $fast 0]/1000.0}]; set ps [expr {[lindex $slow 0]/1000.0}]
say "rings=[llength $nands]"
say [format "FAST_MIN ring period ns: min %.3f max %.3f -> fastest RO %.0f MHz" $pf [expr {[lindex $fast end]/1000.0}] [expr {1000.0/$pf}]]
say [format "SLOW_MAX ring period ns: min %.3f max %.3f -> fastest RO %.0f MHz" $ps [expr {[lindex $slow end]/1000.0}] [expr {1000.0/$ps}]]
say [format "20-bit counter wraps above %.0f MHz (window 65536 x 40 ns)" [expr {1048576.0/(65536*40e-9)/1e6}]]

proc ro_clocks {per} {
    set osc [get_pins -of_objects [get_cells -hier -filter {NAME =~ "*u_ro/g_inv[4].u_inv"}] -filter {REF_PIN_NAME == O}]
    for {set g 0} {$g < 4} {incr g} {create_clock -name ro_osc$g -period $per [lrange $osc [expr {$g*64}] [expr {$g*64+63}]]}
}
proc worst {from to type} {
    set p [get_timing_paths -from [get_clocks $from] -to [get_clocks $to] -$type -max_paths 1]
    if {![llength $p]} {return "none"}
    return [format "%.3f (%s -> %s, skew %.3f)" [get_property SLACK $p] [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p] [get_property SKEW $p]]
}
foreach {corner off per} [list Slow Fast $ps Fast Slow $pf] {
    ro_clocks [format %.3f $per]
    config_timing_corners -corner $off -delay_type none
    config_timing_corners -corner $corner -delay_type min_max
    say "== $corner corner, RO period [format %.3f $per] ns =="
    foreach g {ro_osc0 ro_osc1 ro_osc2 ro_osc3} {say "  $g intra setup [worst $g $g setup]"; say "  $g intra hold  [worst $g $g hold]"}
    say "  ro_clk intra setup [worst ro_clk ro_clk setup]"
    say "  ro_clk intra hold  [worst ro_clk ro_clk hold]"
    say "  clk_fpga_0->ro_clk hold [worst clk_fpga_0 ro_clk hold]"
    say "  ro_clk->clk_fpga_0 setup [worst ro_clk clk_fpga_0 setup]"
    report_timing_summary -no_detailed_paths -file $out/timing_summary_[string tolower $corner].rpt
}
config_timing_corners -corner Slow -delay_type min_max
config_timing_corners -corner Fast -delay_type min_max
check_timing -override_defaults no_clock -file $out/check_timing_no_clock.rpt
report_clock_interaction -file $out/clock_interaction.rpt
close $fp
puts "RO_CORNER_STA_DONE"
