#!/usr/bin/env bash
# 密钥子系统全部定向测试：PUF/KDF 主流程 + MMIO 窗口
set -euo pipefail
cd "$(dirname "$0")/../.."
IV="${IVERILOG_DIR:-/c/wenjian/.vscode/iverilog/bin}"
OUT=build/local/keys
mkdir -p "$OUT"
COMMON="src/rtl/keys/device_dna.v src/rtl/keys/ro_unit.v src/rtl/keys/ro_puf_core.v src/rtl/keys/puf_key.v src/rtl/ascon/ascon_permutation.v sim/keys/DNA_PORT_sim.v sim/keys/BUFG_sim.v sim/keys/LUT_sim.v"

"$IV/iverilog" -g2012 -I src/rtl -I src/rtl/ascon -s tb_puf_key  -o "$OUT/tb_puf_key.vvp"  $COMMON sim/keys/tb_puf_key.v
"$IV/iverilog" -g2012 -I src/rtl -I src/rtl/ascon -s tb_key_mmio -o "$OUT/tb_key_mmio.vvp" $COMMON src/rtl/keys/key_mmio.v sim/keys/tb_key_mmio.v
"$IV/vvp" "$OUT/tb_puf_key.vvp"
"$IV/vvp" "$OUT/tb_key_mmio.vvp"
