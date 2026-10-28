#!/usr/bin/env bash
# elab_check.sh —— 用 iverilog 把 PYNQ overlay 的完整层次 elaborate 一遍
#
# 目的：在没有 Vivado 的情况下抓"端口名/位宽接错"。Xilinx IP（axi_bram_ctrl_0 /
# blk_mem_gen_0）用 sim/pynq/ip_stubs.v 的空壳顶替，所以这里 **不是功能验证**，
# 只证明 top_pynq → pynq_soc → top → soc_top → ... 整棵树能连起来。
#
# 文件清单与 board/vivado_zynq7000_xc7z020_pynq/readme.md §6 第 2 步的要求一致：
#   - src/rtl 里除 top_pl_bram.v / soc_top.v 之外的全部
#   - rtl_p0/ 的 soc_top.v 与 ascon_mmio.v（P0 签核版，覆盖 keys 版）
#   - src/rtl/ascon 里除 ascon_mmio.v / ascon_aead_2_tb.v 之外的全部
#   - src/rtl/pynq/*.v
set -euo pipefail
cd "$(dirname "$0")/../.."

IV=${IVERILOG:-/c/wenjian/.vscode/iverilog/bin/iverilog.exe}
OUT=${1:-build/local/pynq/elab_check.vvp}

mkdir -p "$(dirname "$OUT")"

FILES=()
for f in src/rtl/*.v; do
    case "$(basename "$f")" in
        top_pl_bram.v|soc_top.v) continue ;;
    esac
    FILES+=("$f")
done
FILES+=(board/vivado_zynq7000_xc7z020_pynq/rtl_p0/soc_top.v)
for f in src/rtl/ascon/ascon_aead_2.v src/rtl/ascon/ascon_aead_core.v \
         src/rtl/ascon/ascon_ise.v src/rtl/ascon/ascon_permutation.v \
         src/rtl/ascon/ascon_round.v src/rtl/ascon/ascon_word.v \
         src/rtl/ascon/crypto_aead.v; do
    FILES+=("$f")
done
FILES+=(board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v)
FILES+=(src/rtl/pynq/pynq_ctl.v src/rtl/pynq/pynq_mbox.v \
        src/rtl/pynq/pynq_soc.v src/rtl/pynq/top_pynq.v)

echo "elaborating ${#FILES[@]} source files"
"$IV" -g2012 -I src/rtl -I src/rtl/ascon -t null -o /dev/null \
    sim/pynq/ip_stubs.v "${FILES[@]}"
echo "ELAB CHECK: PASS (${#FILES[@]} files, Xilinx IP replaced by stubs)"
