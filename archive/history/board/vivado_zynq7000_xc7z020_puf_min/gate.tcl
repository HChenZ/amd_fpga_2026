# 门禁 + 报告 + 写 bitstream。要求：impl_1 已经 route_design 完成。
# 不做 phys_opt_design —— 门禁明确不依赖布线后优化。
#
# 门禁（任一失败即 error，且不写 bitstream）：
#   WNS >= +0.5ns、WHS >= 0（WNS>=0 且 WHS>=0 时 TNS/THS 必然为 0）
#   DRC Error = 0
#   Netlist 29-160 计数 = 0（impl_1 与 synth_1 运行日志）
#   DDR* / FIXED_IO* 顶层端口存在
#   RO LUT = 1280 且全部在 pb_ro_puf 内；256 个环反馈网逐个确认
set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here ../..]]
if {![info exists ::puf_min_out]} {error "Set ::puf_min_out before sourcing gate.tcl"}
set work [file normalize [get_property DIRECTORY [current_project]]]

open_run impl_1
source $here/reports.tcl
source $here/audit_rings.tcl

set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set drc_err [llength [get_drc_violations -quiet -filter {SEVERITY == "Error"}]]
set drc_crit [llength [get_drc_violations -quiet -filter {SEVERITY == "Critical Warning"}]]

proc log_29_160 {path} {
    if {![file exists $path]} {return -1}
    set f [open $path r]; set t [read $f]; close $f
    return [regexp -all {CRITICAL WARNING: \[Netlist 29-160\]} $t]
}
set n29160_impl [log_29_160 $work/puf_min.runs/impl_1/runme.log]
set n29160_synth [log_29_160 $work/puf_min.runs/synth_1/runme.log]

set ddr_ports [llength [get_ports -quiet DDR*]]
set fio_ports [llength [get_ports -quiet FIXED_IO*]]
set ro_luts [get_cells -quiet -hier -filter {NAME =~ */bank/rings* && REF_NAME =~ LUT*}]
set ro_in_pb [llength [filter $ro_luts {PBLOCK =~ "*pb_ro_puf"}]]

set fp [open $::puf_min_out/gate.txt w]
puts $fp "class=STRUCTURAL_ONLY_NO_RO_TIMING_SIGNOFF"
puts $fp "board=NOT_RUN"
puts $fp "part=[get_property PART [current_project]] top=[get_property TOP [current_fileset]] version=[version -short]"
puts $fp "post_route_phys_opt_design=NOT_RUN (flow stops at route_design; no manual phys_opt_design)"
puts $fp "post_place_phys_opt_design=ENABLED (Vivado 默认实现步骤，不是事后 AggressiveExplore 补救)"
puts $fp "wns_ns=$wns"
puts $fp "whs_ns=$whs"
puts $fp "tns_ths_zero_implied_by_wns_whs=[expr {$wns >= 0 && $whs >= 0}]"
puts $fp "drc_error=$drc_err"
puts $fp "drc_critical_warning=$drc_crit"
puts $fp "netlist_29_160_impl=[format %d $n29160_impl]"
puts $fp "netlist_29_160_synth=[format %d $n29160_synth]"
puts $fp "ddr_top_ports=$ddr_ports"
puts $fp "fixed_io_top_ports=$fio_ports"
puts $fp "ro_luts=[llength $ro_luts]"
puts $fp "ro_luts_in_pblock=$ro_in_pb"
close $fp
puts "PUF_MIN_GATE wns=$wns whs=$whs drc_err=$drc_err drc_crit=$drc_crit n29160_impl=$n29160_impl n29160_synth=$n29160_synth ddr=$ddr_ports fio=$fio_ports ro_luts=[llength $ro_luts] ro_in_pb=$ro_in_pb"
puts "PUF_MIN_GATE_FILE $::puf_min_out/gate.txt"

if {$n29160_impl != 0 || $n29160_synth != 0} {
    error "PS pin constraints landed on internal pins (Netlist 29-160); no bitstream written"
}
if {$ddr_ports == 0 || $fio_ports == 0} {
    error "DDR*/FIXED_IO* top-level ports missing; no bitstream written"
}
if {$wns < 0.5} {error "Setup slack $wns ns is below the +0.5 ns gate; no bitstream written"}
if {$whs < 0} {error "Hold slack $whs ns is negative; no bitstream written"}
if {$drc_err != 0} {error "DRC Error = $drc_err; no bitstream written"}
if {[llength $ro_luts] != 1280 || $ro_in_pb != 1280} {
    error "RO structure/pblock gate failed ([llength $ro_luts] LUTs, $ro_in_pb in pblock)"
}

write_bitstream -force $::puf_min_out/puf_min.bit
file copy -force $work/puf_min.gen/sources_1/bd/puf/hw_handoff/puf.hwh $::puf_min_out/puf.hwh
puts "PUF_MIN_BIT_OK $::puf_min_out"
