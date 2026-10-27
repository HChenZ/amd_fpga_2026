#!/usr/bin/env bash
# 生产策略复制臂矩阵（批次 B）—— 修正选点后重跑
#
# 批次 A 的 pr_rep_state 用「驱动单元名」做匹配，而本项目那根网叫 state[3]、
# 驱动它的单元叫 FSM_sequential_state_reg[3]，于是 candidates=0（臂白跑）。
# 本批改模板为「网名 OR 单元名」匹配，并加两条消融臂。
#
# 全部：Performance_ExploreWithRemap 全流程 + PHYS_OPT_DESIGN.TCL.POST 钩子，核心 10 ns。
set -u
ROOT=/c/wenjian/game/FPGA2026/ours/amd_fpga_2026
VIVADO=/c/ruanjian/2025.2/Vivado/bin/vivado.bat
LOGS=$ROOT/build/local/tests_20261024/logs
mkdir -p "$LOGS"
cd "$ROOT" || exit 1

# 等批次 A 的 4 个 vivado 全部退出（含 90 s 冷却），避免 8 个 Vivado 抢同一台机
echo "[$(date +%H:%M:%S)] waiting for other vivado to exit..."
for i in $(seq 1 240); do
    n=$(tasklist 2>/dev/null | grep -ci "vivado.exe")
    if [ "$n" -eq 0 ]; then break; fi
    sleep 20
done
sleep 90
echo "[$(date +%H:%M:%S)] starting batch B"

run () {
    local tag=$1 mode=$2 fo=$3 pats=$4 mf=$5 dorep=$6
    echo "[$(date +%H:%M:%S)] launch $tag mode=$mode fo=$fo mf=$mf dorep=$dorep pats=$pats"
    "$VIVADO" -mode batch -source build/timing_tests/run_prod_arm.tcl -notrace \
        -log "C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/tests_20261024/logs/$tag.log" \
        -journal "C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/tests_20261024/logs/$tag.jou" \
        -tclargs "$tag" "20.000" "$mode" "$fo" "$pats" "$mf" "$dorep" > "$LOGS/$tag.stdout" 2>&1
    echo "[$(date +%H:%M:%S)] done $tag rc=$?"
}

# 1) 修正后的定点复制：只拆 state[*]（参照非生产流程的 rep_ff400）
run pr_rep2_state hook 400 "*u_crypto_aead/state*"                              128 1 &
# 2) 消融：只拆 sel_*（D 之后新墙的那 4 条 fo≈171 的 1 位网）
run pr_rep2_sel   hook 128 "*id_ex_u/sel_*"                                     128 1 &
# 3) 叠加：state + sel_* 一起拆（验证"第二轮要停手"在生产流程上是否同样成立）
run pr_rep2_both  hook 128 "*u_crypto_aead/state* *id_ex_u/sel_*"               128 1 &
wait
echo "[$(date +%H:%M:%S)] BATCH B COMPLETE"
for t in pr_rep2_state pr_rep2_sel pr_rep2_both; do
    echo "--- $t ---"
    cat "$ROOT/build/reports/tests_20261024/$t/result.txt" 2>/dev/null || echo "(no result)"
done
