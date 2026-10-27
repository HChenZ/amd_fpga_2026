#!/usr/bin/env bash
# R2C 波次：机制隔离 —— +0.097 到底是「属性」「调用」「被选中的网」还是「压力」带来的
#
# 已知（R2 波次 8 臂，全部 Performance_ExploreWithRemap / 10 ns，副本一律 51）：
#   r2_ctl +0.087 | r2_popt(裸 phys_opt) +0.087
#   r2_net1 / r2_net2 / r2_net1_cell / r2_all4_cell / r2_net1_aggr / r2_net1_mf16 全部 +0.184
#   也就是说：设属性 + 调 -force_replication_on_nets → +0.184，与选几根、选谁、MAX_FANOUT 取 16 还是 128 无关。
#
# 本波四个臂回答「少了哪一味就不灵」：
#   r2_noprop  只有调用，不设任何属性
#   r2_tiny    只有调用，且作用在一根 fo=3 的无关小网上（选点无关性）
#   r2_x2      属性 + 连调两次（可叠加性）
#   r2_tight   不给属性也不复制，改成把时钟临时收紧到 9 ns 让 phys_opt 真的有事可做
set -u
ROOT=/c/wenjian/game/FPGA2026/ours/amd_fpga_2026
VIVADO=/c/ruanjian/2025.2/Vivado/bin/vivado.bat
LOGS=$ROOT/build/local/tests_20261025/logs
RPT=$ROOT/build/reports/tests_20261025
mkdir -p "$LOGS"
cd "$ROOT" || exit 1

run () {
    local tag=$1 hook=$2
    echo "[$(date +%H:%M:%S)] launch $tag hook=$hook"
    "$VIVADO" -mode batch -source build/timing_tests/run_rep2.tcl -notrace \
        -log "C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/tests_20261025/logs/$tag.log" \
        -journal "C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/tests_20261025/logs/$tag.jou" \
        -tclargs "$tag" "20.000" hook \
            "C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/timing_tests/hooks/$hook" \
        > "$LOGS/$tag.stdout" 2>&1
    echo "[$(date +%H:%M:%S)] done $tag rc=$?"
}

echo "=================== WAVE C ==================="
run r2_noprop r2c_noprop.tcl &
run r2_tiny   r2c_tiny.tcl   &
run r2_x2     r2c_x2.tcl     &
run r2_tight  r2c_tight.tcl  &
wait

echo "[$(date +%H:%M:%S)] BATCH R2C COMPLETE"
for t in r2_noprop r2_tiny r2_x2 r2_tight; do
    echo "--- $t ---"
    cat "$RPT/$t/result.txt" 2>/dev/null || echo "(no result)"
done
