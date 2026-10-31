# 实现后报告。只记录事实：不修改时钟、不加时序例外、不降级 DRC。
if {![info exists ::puf_min_out]} {error "Set ::puf_min_out (source setup.tcl first)"}
if {[llength [get_runs -quiet impl_1]] == 0} {error "No impl_1 run in this project"}
open_run impl_1

report_timing_summary -report_unconstrained -file $::puf_min_out/timing.rpt
report_timing -max_paths 20 -file $::puf_min_out/setup_paths.rpt
report_timing -delay_type min -max_paths 20 -file $::puf_min_out/hold_paths.rpt
report_utilization -file $::puf_min_out/utilization.rpt
# 分层资源：用来解释"最小版"到底花在哪里（计数器/快照/健康逻辑/回读多路）
report_utilization -hierarchical -hierarchical_depth 3 -file $::puf_min_out/utilization_hier.rpt
report_utilization -pblocks [get_pblocks -quiet pb_ro_puf] -file $::puf_min_out/pblock_utilization.rpt
report_drc -file $::puf_min_out/drc.rpt
report_methodology -file $::puf_min_out/methodology.rpt
report_clock_interaction -file $::puf_min_out/clock_interaction.rpt
report_cdc -file $::puf_min_out/cdc.rpt
report_clocks -file $::puf_min_out/clocks.rpt
report_route_status -file $::puf_min_out/route_status.rpt
check_timing -verbose -file $::puf_min_out/check_timing.rpt
write_xdc -force $::puf_min_out/applied_constraints.xdc
puts "PUF_MIN_REPORTS_OK $::puf_min_out"
