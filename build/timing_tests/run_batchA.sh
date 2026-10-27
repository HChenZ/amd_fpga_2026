#!/usr/bin/env bash
# 生产策略复制臂矩阵（批次 A）
#   每个臂：独立工程副本（build/local/tests_20261024/<tag>/），独立日志，互不干扰。
#   RTL = src/rtl（当前 HEAD 3cfbe51，含 C+D）。核心时钟 100 MHz = 输入 20.000 ns（MMCM x2）。
#   策略统一 Performance_ExploreWithRemap；hook 臂只在 PHYS_OPT_DESIGN.TCL.POST 挂复制钩子。
set -u
ROOT=/c/wenjian/game/FPGA2026/ours/amd_fpga_2026
VIVADO=/c/ruanjian/2025.2/Vivado/bin/vivado.bat
LOGS=$ROOT/build/local/tests_20261024/logs
mkdir -p $LOGS
cd $ROOT

run () {
    local tag=$1 period=$2 mode=$3 fo=$4 pats=$5 mf=$6 dorep=$7
    echo "[$(date +%H:%M:%S)] launch $tag mode=$mode fo=$fo mf=$mf dorep=$dorep pats=$pats"
    "$VIVADO" -mode batch -source build/timing_tests/run_prod_arm.tcl -notrace \
        -log "$LOGS/$tag.log" -journal "$LOGS/$tag.jou" \
        -tclargs "$tag" "$period" "$mode" "$fo" "$pats" "$mf" "$dorep" > "$LOGS/$tag.stdout" 2>&1
    echo "[$(date +%H:%M:%S)] done $tag rc=$?"
}

run pr_ctl        20.000 ctl  0   "*"                      128 0 &
run pr_ctl2       20.000 ctl  0   "*"                      128 0 &
run pr_rep_state  20.000 hook 400 "*u_crypto_aead/state*"  128 1 &
run pr_mfonly     20.000 hook 400 "*u_crypto_aead/state*"  128 0 &
wait
echo "[$(date +%H:%M:%S)] BATCH A COMPLETE"
for t in pr_ctl pr_ctl2 pr_rep_state pr_mfonly; do
    echo "--- $t ---"
    cat "$ROOT/build/reports/tests_20261024/$t/result.txt" 2>/dev/null || echo "(no result)"
done
