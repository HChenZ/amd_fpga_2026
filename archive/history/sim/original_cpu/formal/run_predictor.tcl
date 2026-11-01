#============================================================================
# JasperGold TCL Script: run_predictor.tcl
# Description: Formal verification of branch predictor (RV32)
#============================================================================

clear -all

analyze -sv ../rtl/branch_predictor.v
analyze -sv predictor_props.sv
analyze -sv predictor_bind.sv

elaborate -top predictor -parameter XLEN 32 -parameter INDEX_WIDTH 6

clock clk
reset -expression {!rst_n}

set_prove_time_limit 60s
set_max_trace_length 10

prove -all

report -results -file predictor_results.txt -force
report -summary -file predictor_summary.txt -force
