#!/usr/bin/env bash
# Build the Ascon ISE firmware and run it on the RISC-V softcore (with the
# custom-0 permutation instruction), then report PASS/FAIL + cycle benchmark.
#
#   bash sim/ascon/run_ascon_ise.sh
#
# Exit 0 only if the firmware prints DONE and no test FAILed.
set -euo pipefail

cd "$(dirname "$0")/../.."   # repo root

IVERILOG="${IVERILOG:-/c/wenjian/.vscode/iverilog/bin/iverilog}"
VVP="${VVP:-/c/wenjian/.vscode/iverilog/bin/vvp}"

# 1. cross-compile firmware -> hex (padded to 32768 words)
bash src/firmware/ascon_ise_rv32/build.sh

# 2. compile the simulation platform (CPU + ascon ISE + MMIO accel + BRAM + tb)
mkdir -p build/local/ascon_ise
RTL=$(ls src/rtl/*.v | grep -v '/top.v$' | grep -v '/top_pl_bram.v$')
"$IVERILOG" -g2012 -I src/rtl -I src/rtl/ascon -o build/local/ascon_ise/tb_ascon_ise.vvp \
    $RTL \
    src/rtl/ascon/ascon_ise.v \
    src/rtl/ascon/ascon_mmio.v \
    src/rtl/ascon/ascon_aead_core.v \
    src/rtl/ascon/crypto_aead.v \
    sim/ascon/axi_slave_bram.v \
    sim/ascon/tb_ascon_sw.v

# 3. run
"$VVP" build/local/ascon_ise/tb_ascon_ise.vvp +HEX=build/local/ascon_ise/ascon_ise.hex
