#============================================================================
# JasperGold TCL Script: run_cpu_axi_bridge.tcl
# Description: Formal verification of cpu_axi_bridge (RV32)
#============================================================================

clear -all

analyze -sv ../rtl/cpu_axi_bridge.v
analyze -sv cpu_axi_bridge_props.sv
analyze -sv cpu_axi_bridge_bind.sv

elaborate -top cpu_axi_bridge -parameter XLEN 32

clock clk
reset -expression {!rst_n}

set_prove_time_limit 120s
set_max_trace_length 30

prove -all

report -results -file cpu_axi_bridge_results.txt -force
report -summary -file cpu_axi_bridge_summary.txt -force
