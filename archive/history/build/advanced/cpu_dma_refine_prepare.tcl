# One bounded physical experiment for the measured 100MHz -0.046ns cache path.
# Uses actual routed pin/net objects; no RTL, clock or timing exception changes.
set root [file normalize [file join [file dirname [info script]] ../..]]
set cpu_refine_out $root/data/advanced/dma_cpu/physopt_[clock format [clock seconds] -format %Y%m%d_%H%M%S]
file mkdir $cpu_refine_out
set pin [get_pins -of_objects [get_cells {cpu_dma_i/engine/inst/u_soc_top/u_cpu_core/u_dcache/tag_way0_reg_0_63_9_11}] -filter {REF_PIN_NAME == "ADDRA[0]"}]
if {[llength $pin]!=1} {error "Measured critical cache pin not found"}
set segments [get_nets -segments -of_objects $pin]
set driver [get_pins -leaf -of_objects $segments -filter {DIRECTION == OUT}]
set cpu_hot_net [get_nets -of_objects $driver]
if {[llength $cpu_hot_net]!=1} {error "Expected one critical driver net"}
set loads [llength [get_pins -leaf -of_objects [get_nets -segments $cpu_hot_net] -filter {DIRECTION == IN}]]
set cpu_before_replicas [llength [get_cells -hier -filter {NAME =~ *_replica*}]]
set fp [open $cpu_refine_out/before.txt w]
puts $fp "clock_period_ns=[get_property PERIOD [get_clocks clk_fpga_0]] setup=[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] hold=[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
puts $fp "driver=$driver net=$cpu_hot_net leaf_loads=$loads replicas_total=$cpu_before_replicas"
puts $fp "planned_command=phys_opt_design -directive AggressiveExplore"
puts $fp "force_replication_on_nets was experimentally rejected in post-route mode by Vivado 2025.2 (4-265); no constraint workaround is used."
close $fp
write_checkpoint $cpu_refine_out/before.dcp
puts "CPU_REFINE_PREPARED $cpu_refine_out loads=$loads"
