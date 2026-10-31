# Full reproducible offline flow in a NEW session/project, jobs=2.
# Check machine RAM/load before invoking this script alongside other builds.
set here [file dirname [file normalize [info script]]]
source $here/setup.tcl
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis incomplete"}
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
source $here/reports.tcl
# Preserve initial-route failure reports, then optimize actual routing/logic.
phys_opt_design -directive AggressiveExplore
set ::puf_report_label optimized
set ::puf_report_current 1
source $here/reports.tcl
source $here/audit_rings.tcl
write_checkpoint -force $root/data/advanced/puf_soc/optimized/puf_postroute.dcp
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]<0 || [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]<0} {
    error "Timed subset failed; reports retained; no candidate bit emitted"
}
write_bitstream -force $root/data/advanced/puf_soc/optimized/puf_diagnostic.bit
puts "PUF_SOC_DIAGNOSTIC_BIT_COMPLETE: no full timing signoff; RO bounds not measured"
