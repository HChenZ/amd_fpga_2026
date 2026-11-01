#!/usr/bin/env bash
# 批次 D：把"多一次 phys_opt_design"与"给 sel 寄存器设属性"彻底分开
#
#   2×2 设计（全部 Performance_ExploreWithRemap，核心 10 ns，RTL = src/rtl）：
#     pr_ctl          : 无 pass、无属性            （批次 A，+0.087）
#     pr_selprops     : 无 pass、有属性            （批次 C）
#     pr_physopt_only : 有 pass、无属性            （本批）
#     pr_rep2_sel     : 有 pass、有属性            （批次 B，+0.184）
#   本批跑两次同样的 phys_opt-only，用来看"多一次 pass"本身是否可复现。
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
echo "[$(date +%H:%M:%S)] starting batch D"

run () {
    local tag=$1
    echo "[$(date +%H:%M:%S)] launch $tag (physopt only)"
    "$VIVADO" -mode batch -source build/timing_tests/run_prod_arm.tcl -notrace \
        -log "C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/tests_20261024/logs/$tag.log" \
        -journal "C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/tests_20261024/logs/$tag.jou" \
        -tclargs "$tag" "20.000" "physopt" "99999" "*__none__*" "128" "0" > "$LOGS/$tag.stdout" 2>&1
    echo "[$(date +%H:%M:%S)] done $tag rc=$?"
}

run pr_physopt_only &
run pr_physopt_b &
wait
echo "[$(date +%H:%M:%S)] BATCH D COMPLETE"
for t in pr_physopt_only pr_physopt_b; do
    echo "--- $t ---"
    cat "$ROOT/build/reports/tests_20261024/$t/result.txt" 2>/dev/null || echo "(no result)"
done
