#============================================================================
# JasperGold TCL Script: run_cpu64.tcl
# Description:
#   Full-CPU pipeline formal verification under the current cache-aware model.
#   - top_formal provides deterministic abstract I/D memory responses
#   - Elaborates top_formal with XLEN=64
#============================================================================

clear -all

puts "=========================================="
puts "  Full-CPU Pipeline Formal Verification"
puts "  Mode       : RV64"
puts "  Memory model: abstract cache responses"
puts "=========================================="

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

analyze -sv cpu_pipeline_props.sv
analyze -sv cpu_pipeline_bind.sv

elaborate -top top_formal -parameter XLEN 64 -parameter RAM_DEPTH 16384

clock clk
reset -expression {!rst_n}

assume -name no_sw_irq  {ireq_software  == 1'b0}
assume -name no_tmr_irq {ireq_timer     == 1'b0}
assume -name no_ext_irq {ireq_external  == 1'b0}

set_prove_time_limit 300s
set_max_trace_length 50

prove -all

report -results -file cpu64_results.txt -force
report -summary -file cpu64_summary.txt -force

puts "=========================================="
puts "  Done. Results: cpu64_results.txt"
puts "=========================================="
