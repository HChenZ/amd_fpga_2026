#============================================================================
# JasperGold TCL Script: run_dcache64.tcl
# Description: Formal verification of dcache (RV64)
#============================================================================

clear -all

analyze -sv ../rtl/dcache.v
analyze -sv dcache_props.sv
analyze -sv dcache_bind.sv

elaborate -top dcache -parameter XLEN 64 -parameter DCACHE_SET_SIZE 64 -parameter DCACHE_LINE_WORDS 4

clock clk
reset -expression {!rst_n}

set_prove_time_limit 120s
set_max_trace_length 30

prove -all

report -results -file dcache64_results.txt -force
report -summary -file dcache64_summary.txt -force
