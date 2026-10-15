#!/usr/bin/env bash
# Build the Ascon MMIO-accelerator firmware and run it on the RISC-V softcore
# (soc_top now includes the ascon_mmio peripheral), then report PASS/FAIL +
# hardware cycle benchmarks.
#
#   bash sim/ascon/run_ascon_hw.sh
#
# Exit 0 only if the firmware prints DONE and no test FAILed.
set -euo pipefail

cd "$(dirname "$0")/../.."   # repo root

IVERILOG="${IVERILOG:-/c/wenjian/.vscode/iverilog/bin/iverilog}"
VVP="${VVP:-/c/wenjian/.vscode/iverilog/bin/vvp}"

# 1. cross-compile firmware -> hex (padded to 32768 words)
bash src/firmware/ascon_hw_rv32/build.sh

# 2. compile the simulation platform. Exclude top.v / top_pl_bram.v (Vivado IP).
mkdir -p build/local/ascon_hw
RTL=$(ls src/rtl/*.v | grep -v '/top.v$' | grep -v '/top_pl_bram.v$')
"$IVERILOG" -g2012 -I src/rtl -I src/rtl/ascon -o build/local/ascon_hw/tb_ascon_hw.vvp \
    $RTL \
    src/rtl/ascon/ascon_mmio.v \
    src/rtl/ascon/ascon_aead_core.v \
    src/rtl/ascon/crypto_aead.v \
    sim/ascon/axi_slave_bram.v \
    sim/ascon/tb_ascon_sw.v

# 3. run
"$VVP" build/local/ascon_hw/tb_ascon_hw.vvp +HEX=build/local/ascon_hw/ascon_hw.hex
