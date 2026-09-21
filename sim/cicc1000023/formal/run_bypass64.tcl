#============================================================================
# JasperGold TCL Script: run_bypass64.tcl
# Description: Formal verification of bypass forwarding MUX (RV64)
#============================================================================

clear -all

analyze -sv ../rtl/bypass.v
analyze -sv bypass_props.sv
analyze -sv bypass_bind.sv

elaborate -top bypass -parameter XLEN 64

clock -none
reset -none

set_prove_time_limit 60s
set_max_trace_length 10

prove -all

report -results -file bypass64_results.txt -force
report -summary -file bypass64_summary.txt -force
