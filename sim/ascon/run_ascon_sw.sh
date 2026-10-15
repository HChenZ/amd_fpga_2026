#!/usr/bin/env bash
# Build the Ascon-AEAD128 software image and run it on the RISC-V softcore
# (soc_top) in Icarus simulation, then report PASS/FAIL + cycle benchmarks.
#
#   bash sim/ascon/run_ascon_sw.sh
#
# Exit 0 only if the firmware prints DONE and no test FAILed.
set -euo pipefail

cd "$(dirname "$0")/../.."   # repo root

IVERILOG="${IVERILOG:-/c/wenjian/.vscode/iverilog/bin/iverilog}"
VVP="${VVP:-/c/wenjian/.vscode/iverilog/bin/vvp}"

# 1. cross-compile firmware -> 32-bit little-endian hex (padded to 32768 words)
bash src/firmware/ascon_rv32/build.sh

# 2. compile the simulation platform (soc_top + AXI BRAM slave + UART monitor).
#    Exclude top.v / top_pl_bram.v (they instantiate Vivado IP Icarus can't model).
mkdir -p build/local/ascon_sw
RTL=$(ls src/rtl/*.v | grep -v '/top.v$' | grep -v '/top_pl_bram.v$')
"$IVERILOG" -g2012 -I src/rtl -o build/local/ascon_sw/tb_ascon_sw.vvp \
    $RTL sim/ascon/axi_slave_bram.v sim/ascon/tb_ascon_sw.v

# 3. run
"$VVP" build/local/ascon_sw/tb_ascon_sw.vvp +HEX=build/local/ascon_sw/ascon_sw.hex
