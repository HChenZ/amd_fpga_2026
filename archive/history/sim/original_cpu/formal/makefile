#============================================================================
# Makefile for JasperGold Formal Verification
#   - bypass:        standalone bypass module verification
#   - icache/dcache: cache module protocol and fill-state verification
#   - bus_interconnect/cpu_axi_bridge/axi_master: bus and AXI verification
#   - cpu:           full-CPU pipeline verification (default merged RV32 image)
#============================================================================

JG ?= jg

.PHONY: bypass bypass-gui bypass64 bypass64-gui regfile regfile-gui regfile64 regfile64-gui predictor predictor-gui predictor64 predictor64-gui icache icache-gui icache64 icache64-gui dcache dcache-gui dcache64 dcache64-gui bus_interconnect bus_interconnect-gui bus_interconnect64 bus_interconnect64-gui cpu_axi_bridge cpu_axi_bridge-gui cpu_axi_bridge64 cpu_axi_bridge64-gui axi_master axi_master-gui axi_master64 axi_master64-gui cpu cpu-gui cpu64 cpu64-gui allmods clean

# ---- Bypass Module Only ----
bypass:
	rm -rf jgproject/
	$(JG) -batch run.tcl

bypass-gui:
	rm -rf jgproject/
	$(JG) run.tcl

bypass64:
	rm -rf jgproject/
	$(JG) -batch run_bypass64.tcl

bypass64-gui:
	rm -rf jgproject/
	$(JG) run_bypass64.tcl

# ---- Register File Only ----
regfile:
	rm -rf jgproject/
	$(JG) -batch run_regfile.tcl

regfile-gui:
	rm -rf jgproject/
	$(JG) run_regfile.tcl

regfile64:
	rm -rf jgproject/
	$(JG) -batch run_regfile64.tcl

regfile64-gui:
	rm -rf jgproject/
	$(JG) run_regfile64.tcl

# ---- Branch Predictor Only ----
predictor:
	rm -rf jgproject/
	$(JG) -batch run_predictor.tcl

predictor-gui:
	rm -rf jgproject/
	$(JG) run_predictor.tcl

predictor64:
	rm -rf jgproject/
	$(JG) -batch run_predictor64.tcl

predictor64-gui:
	rm -rf jgproject/
	$(JG) run_predictor64.tcl

# ---- Instruction Cache Only ----
icache:
	rm -rf jgproject/
	$(JG) -batch run_icache.tcl

icache-gui:
	rm -rf jgproject/
	$(JG) run_icache.tcl

icache64:
	rm -rf jgproject/
	$(JG) -batch run_icache64.tcl

icache64-gui:
	rm -rf jgproject/
	$(JG) run_icache64.tcl

# ---- Data Cache Only ----
dcache:
	rm -rf jgproject/
	$(JG) -batch run_dcache.tcl

dcache-gui:
	rm -rf jgproject/
	$(JG) run_dcache.tcl

dcache64:
	rm -rf jgproject/
	$(JG) -batch run_dcache64.tcl

dcache64-gui:
	rm -rf jgproject/
	$(JG) run_dcache64.tcl

# ---- Bus Interconnect Only ----
bus_interconnect:
	rm -rf jgproject/
	$(JG) -batch run_bus_interconnect.tcl

bus_interconnect-gui:
	rm -rf jgproject/
	$(JG) run_bus_interconnect.tcl

bus_interconnect64:
	rm -rf jgproject/
	$(JG) -batch run_bus_interconnect64.tcl

bus_interconnect64-gui:
	rm -rf jgproject/
	$(JG) run_bus_interconnect64.tcl

# ---- Cache-to-AXI Bridge Only ----
cpu_axi_bridge:
	rm -rf jgproject/
	$(JG) -batch run_cpu_axi_bridge.tcl

cpu_axi_bridge-gui:
	rm -rf jgproject/
	$(JG) run_cpu_axi_bridge.tcl

cpu_axi_bridge64:
	rm -rf jgproject/
	$(JG) -batch run_cpu_axi_bridge64.tcl

cpu_axi_bridge64-gui:
	rm -rf jgproject/
	$(JG) run_cpu_axi_bridge64.tcl

# ---- AXI Master Only ----
axi_master:
	rm -rf jgproject/
	$(JG) -batch run_axi_master.tcl

axi_master-gui:
	rm -rf jgproject/
	$(JG) run_axi_master.tcl

axi_master64:
	rm -rf jgproject/
	$(JG) -batch run_axi_master64.tcl

axi_master64-gui:
	rm -rf jgproject/
	$(JG) run_axi_master64.tcl

# ---- Merge all riscv-tests hex into one file ----
merge all_tests.hex:
	ARCH=RV32 bash merge_hex.sh

merge64:
	ARCH=RV64 bash merge_hex.sh

# ---- Full CPU Pipeline ----
cpu:
	rm -rf jgproject/
	$(JG) -batch run_cpu.tcl

cpu-gui:
	rm -rf jgproject/
	$(JG) run_cpu.tcl

cpu64:
	rm -rf jgproject/
	$(JG) -batch run_cpu64.tcl

cpu64-gui:
	rm -rf jgproject/
	$(JG) run_cpu64.tcl

allmods: bypass bypass64 regfile regfile64 predictor predictor64 icache icache64 dcache dcache64 bus_interconnect bus_interconnect64 cpu_axi_bridge cpu_axi_bridge64 axi_master axi_master64 cpu cpu64

# ---- Default ----
run: bypass

# ---- Clean ----
clean:
	rm -rf jgproject/ results/
	rm -f all_tests.hex _run_tmp.tcl
	rm -f *_results.txt *_summary.txt
	rm -f *.jdb *.log *.vcd
