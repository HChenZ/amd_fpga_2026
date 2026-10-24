# Dump the full detail of the current worst setup paths (id_ex-internal) so the
# fix targets the real logic, not the symptom.
set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_routed.dcp]
report_timing -delay_type max -max_paths 4 -nworst 1 -path_type full_clock_expanded \
    -file [file join $root build local margin_20261020 worst_paths_detail.rpt]
puts "WALL DETAIL DONE"
