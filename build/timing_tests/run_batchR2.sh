#!/usr/bin/env bash
# R2 波次：sel_* 单根/双根复制 + 必要的对照臂
#
# 背景（html_v2/rtl.html R1 节 + docs/timing_route_tests_20261024.md §10.6）：
#   上一轮 pr_rep2_sel / pr_sel_b 对 4 条 sel_* 网做 -force_replication_on_nets，
#   结果 rep_cells 51→51（一个副本都没生成），但 WNS 从 +0.087 变成 +0.184。
#   日志显示 phys_opt 只「Identified 12 candidate nets / Optimized 0 net」，而且那 12 个
#   对象其实只是 4 根网的 3 级别名（Vivado 自己打了 Using parent net ... 的提示）。
#   所以这一轮要回答三个问题：
#     Q1 单根拆（页面的建议）是不是就能生成副本？        -> r2_net1 / r2_net2
#     Q2 +0.184 到底是不是复制带来的？                    -> r2_popt / r2_ctl
#     Q3 不生成副本的原因是别名、MAX_FANOUT 写错对象（该写在 cell 上）、
#        还是工具判定负载已够近？                          -> r2_net1_cell / r2_all4_cell /
#                                                            r2_net1_aggr / r2_net1_mf16
#
# 全部 Performance_ExploreWithRemap 全流程、核心 10 ns、钩子挂在 PHYS_OPT_DESIGN.TCL.POST。
set -u
ROOT=/c/wenjian/game/FPGA2026/ours/amd_fpga_2026
VIVADO=/c/ruanjian/2025.2/Vivado/bin/vivado.bat
LOGS=$ROOT/build/local/tests_20261025/logs
RPT=$ROOT/build/reports/tests_20261025
mkdir -p "$LOGS"
cd "$ROOT" || exit 1

run () {
    local tag=$1 mode=$2 hook=$3
    local tclhook=""
    [ -n "$hook" ] && tclhook="C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/timing_tests/$hook"
    echo "[$(date +%H:%M:%S)] launch $tag mode=$mode hook=${hook:-none}"
    "$VIVADO" -mode batch -source build/timing_tests/run_rep2.tcl -notrace \
        -log "C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/tests_20261025/logs/$tag.log" \
        -journal "C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/tests_20261025/logs/$tag.jou" \
        -tclargs "$tag" "20.000" "$mode" "$tclhook" > "$LOGS/$tag.stdout" 2>&1
    echo "[$(date +%H:%M:%S)] done $tag rc=$?"
}

# 等前台的 vivado（例如 preflight）退出
echo "[$(date +%H:%M:%S)] waiting for other vivado to exit..."
for i in $(seq 1 240); do
    n=$(tasklist 2>/dev/null | grep -ci "vivado.exe")
    if [ "$n" -eq 0 ]; then break; fi
    sleep 20
done
sleep 30

echo "=================== WAVE A ==================="
run r2_ctl        ctl  ""                       &
run r2_popt       hook hooks/r2_popt.tcl        &
run r2_net1       hook hooks/r2_net1.tcl        &
run r2_net2       hook hooks/r2_net2.tcl        &
wait

echo "=================== WAVE B ==================="
run r2_net1_cell  hook hooks/r2_net1_cell.tcl   &
run r2_all4_cell  hook hooks/r2_net4_cell.tcl   &
run r2_net1_aggr  hook hooks/r2_net1_aggr.tcl   &
run r2_net1_mf16  hook hooks/r2_net1_mf16.tcl   &
wait

echo "[$(date +%H:%M:%S)] BATCH R2 COMPLETE"
for t in r2_ctl r2_popt r2_net1 r2_net2 r2_net1_cell r2_all4_cell r2_net1_aggr r2_net1_mf16; do
    echo "--- $t ---"
    cat "$RPT/$t/result.txt" 2>/dev/null || echo "(no result)"
done
