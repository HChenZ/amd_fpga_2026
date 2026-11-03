#============================================================================
# JasperGold TCL Script: run_regfile.tcl
# Description: Formal verification of regfile (RV32)
#============================================================================

clear -all

analyze -sv ../rtl/regfile.v
analyze -sv regfile_props.sv
analyze -sv regfile_bind.sv

elaborate -top regfile -parameter XLEN 32

clock clk
reset -expression {!rst_n}

set_prove_time_limit 60s
set_max_trace_length 10

prove -all

report -results -file regfile_results.txt -force
report -summary -file regfile_summary.txt -force
