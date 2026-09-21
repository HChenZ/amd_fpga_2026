#============================================================================
# JasperGold TCL Script: run_predictor64.tcl
# Description: Formal verification of branch predictor (RV64)
#============================================================================

clear -all

analyze -sv ../rtl/branch_predictor.v
analyze -sv predictor_props.sv
analyze -sv predictor_bind.sv

elaborate -top predictor -parameter XLEN 64 -parameter INDEX_WIDTH 6

clock clk
reset -expression {!rst_n}

set_prove_time_limit 60s
set_max_trace_length 10

prove -all

report -results -file predictor64_results.txt -force
report -summary -file predictor64_summary.txt -force
