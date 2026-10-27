#!/usr/bin/env bash
# 密钥子系统定向测试：DNA 读取 / PUF enroll+reconstruct / 无 helper 降级 / DNA-only 确定性 / helper 破环
set -euo pipefail
cd "$(dirname "$0")/../.."
IV="${IVERILOG_DIR:-/c/wenjian/.vscode/iverilog/bin}"
OUT=build/local/keys
mkdir -p "$OUT"

SRC="src/rtl/keys/device_dna.v src/rtl/keys/ro_unit.v src/rtl/keys/ro_puf_core.v src/rtl/keys/puf_key.v"
SRC="$SRC src/rtl/ascon/ascon_permutation.v sim/keys/DNA_PORT_sim.v sim/keys/tb_puf_key.v"

"$IV/iverilog" -g2012 -I src/rtl -I src/rtl/ascon -s tb_puf_key -o "$OUT/tb_puf_key.vvp" $SRC
"$IV/vvp" "$OUT/tb_puf_key.vvp"
