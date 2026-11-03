#============================================================================
# JasperGold TCL Script: run_icache.tcl
# Description: Formal verification of icache (RV32)
#============================================================================

clear -all

analyze -sv ../rtl/icache.v
analyze -sv icache_props.sv
analyze -sv icache_bind.sv

elaborate -top icache -parameter XLEN 32 -parameter ICACHE_SET_SIZE 64 -parameter ICACHE_LINE_WORDS 4

clock clk
reset -expression {!rst_n}

set_prove_time_limit 120s
set_max_trace_length 30

prove -all

report -results -file icache_results.txt -force
report -summary -file icache_summary.txt -force
