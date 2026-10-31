# Load only into synthesized puf_mmio_physical_v2, out-of-context.
# No clock-group cuts, no blanket false paths, no package pin assumptions.
# Caller must provide puf_physical_out and explicit IO budgets in env below.
if {[get_property TOP [current_fileset]] ne "puf_mmio_physical_v2"} {error "Wrong physical top"}
if {![info exists ::puf_physical_out]} {error "Set ::puf_physical_out to a unique evidence directory"}
foreach v {PUF_IO_INPUT_MAX_NS PUF_IO_OUTPUT_MAX_NS} {
    if {![info exists ::env($v)] || ![string is double -strict $::env($v)] || $::env($v)<0} {error "Explicit budget required: $v"}
}
set have_ro_bound [info exists ::env(PUF_RO_PERIOD_NS)]
if {$have_ro_bound} {
    if {![string is double -strict $::env(PUF_RO_PERIOD_NS)] || $::env(PUF_RO_PERIOD_NS)<=0 || ![info exists ::env(PUF_RO_BOUND_SOURCE)]} {error "Positive PUF_RO_PERIOD_NS and PUF_RO_BOUND_SOURCE required"}
} elseif {![info exists ::env(PUF_ALLOW_UNBOUNDED_STRUCTURE)] || $::env(PUF_ALLOW_UNBOUNDED_STRUCTURE) ne "1"} {
    error "RO minimum-period bound missing. Supply explicit bound/source, or deliberately request structure-only mode."
}
proc puf_cells {pattern expected} {
    set c [get_cells -hier -filter "NAME =~ $pattern && IS_SEQUENTIAL"]
    if {[llength $c]!=$expected} {error "Expected $expected registers for $pattern, got [llength $c]"}
    return $c
}
proc puf_one {name} {
    set c [get_cells -hier -filter "NAME == $name"]
    if {[llength $c]!=1} {error "Expected one cell $name"}
    return $c
}
proc puf_bound {label ns src dst {skew 0}} {
    if {![llength $src] || ![llength $dst]} {error "Empty handshake constraint $label"}
    set dp [get_pins -of_objects $dst -filter {REF_PIN_NAME == D}]
    if {[llength $dp]!=[llength $dst]} {error "Destination D count mismatch $label"}
    set_max_delay -datapath_only $ns -from $src -to $dp
    if {$skew>0} {set_bus_skew $skew -from $src -to $dp}
    puts $::puf_constraint_log "bound $label ns=$ns skew=$skew source_regs=[llength $src] destination_D=[llength $dp]"
}
set ::puf_constraint_log [open $::puf_physical_out/constraint_inventory.txt w]
puts $::puf_constraint_log "version=[version -short] top=puf_mmio_physical_v2 mode=out_of_context"
puts $::puf_constraint_log "core=10ns management=40ns INDEPENDENT primary input clocks (not generated/phase related)"
puts $::puf_constraint_log "IO budgets: input max=$::env(PUF_IO_INPUT_MAX_NS)ns/min=0; output max=$::env(PUF_IO_OUTPUT_MAX_NS)ns/min=0. Engineering OOC assumptions, not board measurements."
if {![llength [get_clocks -quiet core_clk]]} {create_clock -name core_clk -period 10 [get_ports clk]}
if {![llength [get_clocks -quiet management_clk]]} {create_clock -name management_clk -period 40 [get_ports ro_clk]}
set inputs [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != ro_clk}]
set_input_delay -clock core_clk -max $::env(PUF_IO_INPUT_MAX_NS) $inputs
set_input_delay -clock core_clk -min 0 $inputs
set_output_delay -clock core_clk -max $::env(PUF_IO_OUTPUT_MAX_NS) [all_outputs]
set_output_delay -clock core_clk -min 0 [all_outputs]

# Acknowledge exactly one feedback net in each audited five-LUT ring. Any other
# loop remains a DRC failure. Define RO clocks only from an explicit external bound.
set ringluts [get_cells -hier -filter {NAME =~ bank/* && REF_NAME =~ LUT*}]
if {[llength $ringluts]!=1280} {error "Expected 1280 ring LUTs"}
for {set i 0} {$i<256} {incr i} {
    set gate [puf_one [format {bank/rings[%d].gate0} $i]]
    if {[get_property REF_NAME $gate] ne "LUT2"} {error "Bad ring gate $i"}
    for {set j 1} {$j<5} {incr j} {
        set inv [puf_one [format {bank/rings[%d].stages[%d].inv0} $i $j]]
        if {[get_property REF_NAME $inv] ne "LUT1"} {error "Bad ring stage $i/$j"}
    }
    set fb [get_nets -of_objects [get_pins -of_objects $gate -filter {REF_PIN_NAME == I1}]]
    if {[llength $fb]!=1} {error "Feedback net count $i"}
    set driver [get_pins -leaf -of_objects $fb -filter {DIRECTION == OUT}]
    set expected_driver [format {bank/rings[%d].stages[4].inv0/O} $i]
    if {[llength $driver]!=1 || [get_property NAME $driver] ne $expected_driver} {error "Unexpected feedback driver $i: $driver"}
    set_property ALLOW_COMBINATORIAL_LOOPS TRUE $fb
    if {$have_ro_bound} {create_clock -name [format ro_%03d $i] -period $::env(PUF_RO_PERIOD_NS) $driver}
    puts $::puf_constraint_log "ring=$i LUTs=5 feedback=$fb oscillator_pin=$driver clock_defined=$have_ro_bound"
}
if {$have_ro_bound} {
    puts $::puf_constraint_log "RO_TIMING=CONDITIONAL period_ns=$::env(PUF_RO_PERIOD_NS) bound_source=$::env(PUF_RO_BOUND_SOURCE). This is an assumed guaranteed minimum period, not a frequency measurement."
} else {puts $::puf_constraint_log "RO_TIMING=NOT_MEASURED missing oscillator bound; no RO clocks invented; structural implementation only."}

set s peripheral/keys/sampler
puf_bound completion_toggle 10 [puf_cells $s/complete_reg 1] [list [puf_one [format {%s/cp_reg[0]} $s]]]
puf_bound request_toggle 40 [puf_cells $s/request_reg 1] [list [puf_one [format {%s/rq_reg[0]} $s]]]
# The absolute 20ns arrival bound is the bundled-data guarantee. Do not add a
# bus-skew constraint through synthesized capture/erase mux logic (TIMING-37/39).
puf_bound completion_result 20 [puf_cells $s/result_reg* 128] [puf_cells $s/captured_result_reg* 128]
# Constants bits 1,6,7 were optimized out in the fixed default parameter set.
puf_bound completion_error 20 [puf_cells $s/sample_error_reg* 5] [puf_cells $s/captured_error_reg* 5]
puf_bound phase_to_osc_sync 20 [puf_cells $s/phase_reg* 2] [puf_cells $s/counters*.u_counter/p0_reg* 512]
puf_bound ack_to_management_sync 40 [puf_cells $s/counters*.u_counter/ack_reg* 512] [puf_cells $s/counters*.a0_reg* 512]
puf_bound stopped_count_snapshot 40 [puf_cells $s/counters*.u_counter/count_reg* 5120] [puf_cells $s/snapshot_reg* 5120] 20
puf_bound stopped_overflow_snapshot 40 [puf_cells $s/counters*.u_counter/overflow_reg 256] [puf_cells $s/overflow_snapshot_reg* 256] 20

# Only raw asynchronous reset assertions into the reset synchronizer CLR pins
# are excluded. Final release-stage -> local sequential reset timing stays timed.
set reset_sync [concat [puf_cells $s/ro_reset_release_reg* 2] [puf_cells $s/counters*.u_counter/reset_release_reg* 512]]
set reset_clr [get_pins -of_objects $reset_sync -filter {REF_PIN_NAME == CLR}]
if {[llength $reset_clr]!=514} {error "Reset sync CLR count mismatch"}
set_false_path -from [get_ports rst_n] -to $reset_clr
set_false_path -from [puf_cells peripheral/clear_reg 1] -to $reset_clr
puts $::puf_constraint_log "reset_assertion_only: from rst_n and peripheral/clear_reg to exactly 514 reset synchronizer CLR pins; functional reset endpoints NOT excluded"
puts $::puf_constraint_log "ASYNC_REG_count=[llength [get_cells -hier -filter {ASYNC_REG == TRUE}]]"
close $::puf_constraint_log
write_xdc $::puf_physical_out/applied_constraints.xdc
puts "PUF_CONSTRAINTS_APPLIED ro_bound=$have_ro_bound"
