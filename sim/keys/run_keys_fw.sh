#!/usr/bin/env bash
# 跑密钥子系统自检固件（仿真）：编译 soc_top(rtl_keys) + TB + 固件 hex
set -euo pipefail
cd "$(dirname "$0")/../.."
IV="${IVERILOG_DIR:-/c/wenjian/.vscode/iverilog/bin}"
OUT=build/local/keys_fw
mkdir -p "$OUT"
[ -f "$OUT/keys.hex" ] || bash src/firmware/keys_rv32/build.sh >/dev/null

# 编译前先删旧 vvp：iverilog 在部分 elaboration 错误下仍返回 0，
# 不删就会拿上一版二进制跑出"看起来 PASS"的假结果（本项目踩过）。
rm -f "$OUT/tb_keys_fw.vvp"
"$IV/iverilog" -g2012 -I src/rtl -I src/rtl/ascon -I sim/ascon -s tb_keys_fw   -o "$OUT/tb_keys_fw.vvp"   build/local/rtl_keys/soc_top.v   build/local/rtl_keys/ascon/ascon_mmio.v   $(ls build/local/rtl_keys/*.v | grep -v -E "/(top|top_pl_bram|soc_top)\.v$")   $(ls build/local/rtl_keys/ascon/*.v | grep -v "ascon_mmio.v")   build/local/rtl_keys/keys/*.v   sim/ascon/axi_slave_bram.v sim/keys/DNA_PORT_sim.v sim/keys/BUFG_sim.v sim/keys/LUT_sim.v   sim/keys/tb_keys_fw.v 2>&1 | tee "$OUT/compile.log"
if grep -qE "error:|errors during" "$OUT/compile.log" || [ ! -f "$OUT/tb_keys_fw.vvp" ]; then
    echo "COMPILE FAILED — 不跑仿真"; exit 1
fi
"$IV/vvp" "$OUT/tb_keys_fw.vvp" +HEX="$OUT/keys.hex"
