#============================================================================
# JasperGold TCL Script: run.tcl
# Description: Formal verification of bypass forwarding MUX
# Usage: jg run.tcl
#============================================================================

# ------------------------------------------------------------------
# 1. Clear previous session
# ------------------------------------------------------------------
clear -all

# ------------------------------------------------------------------
# 2. Read design and property files
# ------------------------------------------------------------------
analyze -sv      ../rtl/bypass.v
analyze -sv      bypass_props.sv
analyze -sv      bypass_bind.sv

# ------------------------------------------------------------------
# 3. Elaborate - set bypass as top module
# ------------------------------------------------------------------
elaborate -top bypass -parameter XLEN 32

# ------------------------------------------------------------------
# 4. Clock and reset (bypass is combinational, but JG needs a clock)
#    Create a free-running virtual clock
# ------------------------------------------------------------------
clock -none
reset -none

# ------------------------------------------------------------------
# 5. Proof settings
# ------------------------------------------------------------------
set_prove_time_limit 60s
set_max_trace_length 10

# ------------------------------------------------------------------
# 6. Run proof engines
# ------------------------------------------------------------------
prove -all

# ------------------------------------------------------------------
# 7. Report results
# ------------------------------------------------------------------
report -results -file bypass_results.txt -force
report -summary -file bypass_summary.txt -force

# ------------------------------------------------------------------
# 8. Optional: save session for GUI review
# ------------------------------------------------------------------
# save -jdb bypass.jdb
