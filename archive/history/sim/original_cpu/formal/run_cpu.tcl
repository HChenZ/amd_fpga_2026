#============================================================================
# JasperGold TCL Script: run_cpu.tcl
# Description:
#   Full-CPU pipeline formal verification under the current cache-aware model.
#   - top_formal provides deterministic abstract I/D memory responses
#   - Verifies bypass, stall/flush priority, x0, PC and load-use properties
#
# Usage: jg -batch run_cpu.tcl
#============================================================================

# ------------------------------------------------------------------
# 1. Clear previous session
# ------------------------------------------------------------------
clear -all

puts "=========================================="
puts "  Full-CPU Pipeline Formal Verification"
puts "  Memory model: abstract cache responses"
puts "=========================================="

# ------------------------------------------------------------------
# 2. Read RTL design files (all pipeline modules)
# ------------------------------------------------------------------
analyze -sv ../rtl/defines.v

analyze -sv ../rtl/if_stage.v
analyze -sv ../rtl/if_id.v
analyze -sv ../rtl/id_stage.v
analyze -sv ../rtl/id_ex.v
analyze -sv ../rtl/ex_stage.v
analyze -sv ../rtl/ex_mem.v
analyze -sv ../rtl/mem_stage.v
analyze -sv ../rtl/mem_wb.v
analyze -sv ../rtl/regfile.v
analyze -sv ../rtl/ctrl.v
analyze -sv ../rtl/bypass.v
analyze -sv ../rtl/csr_file.v
analyze -sv ../rtl/branch_predictor.v
analyze -sv ../rtl/mult.v
analyze -sv ../rtl/divider.v
analyze -sv ../rtl/icache.v
analyze -sv ../rtl/dcache.v
analyze -sv ../rtl/cpu_core.v

# Formal-friendly cache-aware wrapper
analyze -sv top_formal.sv

# SVA properties and bind
analyze -sv cpu_pipeline_props.sv
analyze -sv cpu_pipeline_bind.sv

# ------------------------------------------------------------------
# 3. Elaborate
# ------------------------------------------------------------------
elaborate -top top_formal -parameter XLEN 32 -parameter RAM_DEPTH 16384

# ------------------------------------------------------------------
# 4. Clock and reset
# ------------------------------------------------------------------
clock clk
reset -expression {!rst_n}

# ------------------------------------------------------------------
# 5. Assumptions / Constraints
#    Tie off interrupts for basic ISA tests
# ------------------------------------------------------------------
assume -name no_sw_irq  {ireq_software  == 1'b0}
assume -name no_tmr_irq {ireq_timer     == 1'b0}
assume -name no_ext_irq {ireq_external  == 1'b0}

# ------------------------------------------------------------------
# 6. Proof settings
# ------------------------------------------------------------------
set_prove_time_limit 300s
set_max_trace_length 50

# ------------------------------------------------------------------
# 7. Run proof engines
# ------------------------------------------------------------------
prove -all

# ------------------------------------------------------------------
# 8. Report results
# ------------------------------------------------------------------
report -results -file cpu_results.txt -force
report -summary -file cpu_summary.txt -force

puts "=========================================="
puts "  Done. Results: cpu_results.txt"
puts "=========================================="
