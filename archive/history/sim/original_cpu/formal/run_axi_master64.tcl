#============================================================================
# JasperGold TCL Script: run_axi_master64.tcl
# Description: Formal verification of axi_master (RV64)
#============================================================================

clear -all

analyze -sv ../rtl/axi_full_master.v
analyze -sv axi_master_props.sv
analyze -sv axi_master_bind.sv

elaborate -top axi_master -parameter XLEN 64

clock m_aclk
reset -expression {!m_arst_n}

set_prove_time_limit 120s
set_max_trace_length 30

prove -all

report -results -file axi_master64_results.txt -force
report -summary -file axi_master64_summary.txt -force
