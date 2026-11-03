#============================================================================
# JasperGold TCL Script: run_bus_interconnect.tcl
# Description: Formal verification of bus_interconnect (RV32)
#============================================================================

clear -all

analyze -sv ../rtl/bus_interconnect.v
analyze -sv bus_interconnect_props.sv
analyze -sv bus_interconnect_bind.sv

elaborate -top bus_interconnect -parameter XLEN 32

clock clk
reset -expression {!rst_n}

set_prove_time_limit 120s
set_max_trace_length 30

prove -all

report -results -file bus_interconnect_results.txt -force
report -summary -file bus_interconnect_summary.txt -force
