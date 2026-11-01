#!/usr/bin/env bash
# 批次 C：复现性 + 消融
#
# 批次 B 的两个意外：
#   pr_rep2_sel  = +0.184（对照 +0.087）—— 但它【一个副本都没生成】（FF 17187，与对照相同）
#   pr_rep2_state= +0.039 —— 复制了 state[3]（60 个副本），比对照差 0.048
#   pr_rep2_both = +0.149
#
# 所以本批要回答三件事：
#   1) +0.184 能不能复现？（同钩子再跑一次 → pr_sel_b）
#   2) −0.048 能不能复现？（pr_state_b）
#   3) +0.184 到底来自「属性（EQREG NO / MAX_FANOUT）」还是来自「多跑一次 phys_opt_design」？
#      → pr_selprops：同样设属性，但不调用 phys_opt_design（dorep 0）
#
# 全部：Performance_ExploreWithRemap 全流程，核心 10 ns，RTL = src/rtl（C+D）。
set -u
ROOT=/c/wenjian/game/FPGA2026/ours/amd_fpga_2026
VIVADO=/c/ruanjian/2025.2/Vivado/bin/vivado.bat
LOGS=$ROOT/build/local/tests_20261024/logs
mkdir -p "$LOGS"
cd "$ROOT" || exit 1

for i in $(seq 1 240); do
    n=$(tasklist 2>/dev/null | grep -ci "vivado.exe")
    if [ "$n" -eq 0 ]; then break; fi
    sleep 20
done
sleep 60
echo "[$(date +%H:%M:%S)] starting batch C"

run () {
    local tag=$1 mode=$2 fo=$3 pats=$4 mf=$5 dorep=$6
    echo "[$(date +%H:%M:%S)] launch $tag fo=$fo dorep=$dorep pats=$pats"
    "$VIVADO" -mode batch -source build/timing_tests/run_prod_arm.tcl -notrace \
        -log "C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/tests_20261024/logs/$tag.log" \
        -journal "C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/tests_20261024/logs/$tag.jou" \
        -tclargs "$tag" "20.000" "$mode" "$fo" "$pats" "$mf" "$dorep" > "$LOGS/$tag.stdout" 2>&1
    echo "[$(date +%H:%M:%S)] done $tag rc=$?"
}

run pr_sel_b       hook 128 "*id_ex_u/sel_*"                     128 1 &
run pr_state_b     hook 400 "*u_crypto_aead/state*"              128 1 &
run pr_both_b      hook 128 "*u_crypto_aead/state* *id_ex_u/sel_*" 128 1 &
run pr_selprops    hook 128 "*id_ex_u/sel_*"                     128 0 &
wait
echo "[$(date +%H:%M:%S)] BATCH C COMPLETE"
for t in pr_sel_b pr_state_b pr_both_b pr_selprops; do
    echo "--- $t ---"
    cat "$ROOT/build/reports/tests_20261024/$t/result.txt" 2>/dev/null || echo "(no result)"
done
