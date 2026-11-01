# 实现策略扫掠（Strategy Sweep）结果与分析 —— 全量 33 策略版

> 2026-11-01：历史top_pl_bram策略扫掠，不是当前PUF3性能/时序表，也不是继续扫描授权。
> 原策略数据与失败保留，当前候选看 version_entrypoints.md。

> V10 留存更新：旧 sweep RPT/汇总 JSON 已按用户要求删除，本文排名是历史记录。
> 当前最终双策略报告及清理后重跑入口见 [清理说明](workspace_cleanup.md)。
> 后续并行会话已重新导出部分 sweep 报告与汇总，用户确认暂时保留；它们不是本轮重新实现结果。

日期 2026-10-17/18；任务 V06/I08 续接；owner TBD。基线 f52bc49（fix/ascon-key-lifecycle），
Vivado 2025.2 build 6299465，part xc7z020clg400-1，top=top_pl_bram，本机 DESKTOP-5H4M0DR。
未改任何 RTL/XDC/XCI/COE；全部实现共享一次综合，只换实现策略。原始 baseline 工程未打开，
隔离副本在 build/local/strategy_sweep/（git 忽略）。本版覆盖 2025.2 标准实现流程
（Vivado Implementation 2025）**全部 33 个内置策略**。

## 方法

- 脚本 `build/sweep_strategy_timing.tcl`：复制 baseline + 当前 src/rtl → 综合一次 →
  每个策略 `create_run -parent_run synth_1` → 按最终步骤分组并行波（3 路 × 6 jobs，
  含布线后 phys_opt 的策略直接启动到 `phys_opt_design (Post-Route)`）→ 每策略 8 份报告
  + checkpoint + TSV 汇总行。多次中断续跑（resume），最终四批全部 exit 0。
- 聚合 `build/aggregate_strategy_sweep.py` 从 .rpt 解析并与 TSV 交叉核对。
- 已验证不可测项：Vivado Advanced Implementation 2025 流程在 xc7z020（7 系）上
  **不被支持**（12-25131 静默回退标准流程，实测产出与标准流程逐位相同）；其独有策略
  Performance_AggressiveExplore / Performance_NetDelay_medium /
  Congestion_SSI_SpreadLogic_medium / Vivado Advanced Implementation Defaults
  仅 GUI 可用，批处理无法测量。

## 结果总表（33 策略，按 WNS 从好到差）

| 排名 | 策略 | WNS ns | TNS ns | 失败端点 | LUT | FF |
|---|---:|---:|---:|---:|---:|
| 1 | **Performance_ExploreWithRemap** | **-0.118** | **-1.008** | **22** | 11643 | 15949 |
| 2 | Performance_ExplorePostRoutePhysOpt | -0.177 | -2.968 | 31 | 11636 | 15949 |
| 3 | Congestion_SpreadLogic_medium | -0.195 | -3.480 | 60 | 11594 | 15957 |
| 4 | Performance_WLBlockPlacement | -0.220 | -0.893 | 9 | 11602 | 15949 |
| 5 | Congestion_SpreadLogic_low | -0.254 | -5.692 | 63 | 11581 | 15949 |
| 6 | Performance_Explore | -0.273 | -6.040 | 36 | 11636 | 15949 |
| 7 | Performance_EarlyBlockPlacement | -0.316 | -5.742 | 110 | 11632 | 15950 |
| 8 | Performance_NetDelay_high | -0.325 | -18.945 | 163 | 11565 | 15950 |
| 9 | Power_ExploreArea | -0.341 | -10.122 | 137 | 11532 | 15936 |
| 10 | Performance_HighUtilSLRs | -0.351 | -11.565 | 137 | 11573 | 15951 |
| 11 | Performance_Auto_1 / _2 / _3 | -0.383 | -8.075 | 55 | 11636 | 15949 |
| 12 | Power_DefaultOpt | -0.395 | -48.912 | 449 | 11768 | 15954 |
| 13 | Performance_BalanceSLLs / BalanceSLRs / SpreadSLLs | -0.402 | -15.984 | 223 | 11581 | 15956 |
| 14 | Performance_RefinePlacement | -0.418 | -83.748 | 692 | 11569 | 15953 |
| 15 | Congestion_SSI_SpreadLogic_low | -0.418 | -83.748 | 692 | 11569 | 15953 |
| 16 | Performance_ExtraTimingOpt | -0.477 | -52.165 | 484 | 11638 | 15949 |
| 17 | Congestion_SpreadLogic_high | -0.509 | -55.034 | 455 | 11635 | 15949 |
| 18 | Area_Explore | -0.511 | -43.277 | 381 | 11236 | 15948 |
| 19 | Performance_Retiming | -0.518 | -172.762 | 953 | 11561 | 15949 |
| 20 | Performance_NetDelay_low | -0.548 | -27.612 | 145 | 11611 | 15949 |
| 21 | Area_ExploreWithRemap | -0.570 | -43.228 | 375 | 11646 | 15949 |
| 22 | Congestion_SSI_SpreadLogic_high | -0.595 | -61.355 | 524 | 11590 | 15957 |
| 23 | Flow_RunPhysOpt | -0.662 | -60.832 | 430 | 11587 | 15960 |
| 24 | Flow_RunPostRoutePhysOpt | -0.662 | -60.755 | 430 | 11587 | 15960 |
| 25 | Performance_WLBlockPlacementFanoutOpt | -0.716 | -410.196 | 1540 | 11565 | 15949 |
| 26 | Vivado Implementation Defaults | -0.942 | -433.585 | 1579 | 11562 | 15949 |
| 27 | Area_ExploreSequential | -0.943 | -65.018 | 374 | 11427 | 15932 |
| 28 | Flow_RuntimeOptimized | -1.273 | -1076.033 | 3749 | 11606 | 15949 |
| 29 | Flow_Quick | -32.884 | -321610.344 | 34289 | 11603 | 15949 |

参考（V06，另一台机器 xyq，同工具/part/RTL）：Default -0.942/-433.585/1579、
Performance_ExplorePostRoutePhysOpt -0.177/-2.968/31 —— 本机重跑逐位一致，跨机可复现。

## 关键发现

1. **仍无策略在旧 RTL 上收敛 100 MHz**，但第一名易主：
   **Performance_ExploreWithRemap（-0.118/-1.008/22 端点）** 超过此前最优
   ExplorePostRoutePhysOpt（-0.177）0.059 ns。它在 2025.2 里自带布线后 phys_opt
   （IS_ENABLED=1、directive Explore）+ Remap，是 Explore 族的最强变体。
2. **Auto_1/2/3 三兄弟结果完全相同**（-0.383/-8.075/55）：ML 派生指令在此设计上
   收敛到同一配置，且不如 Explore 族 —— 该设计的策略甜区在 Explore/Remap 组合。
3. **SLL 三兄弟完全相同**（-0.402×3）、**Flow_RunPhysOpt 与 Flow_RunPostRoutePhysOpt
   相同**（-0.662×2）、**SSI_SpreadLogic_low 与 RefinePlacement 相同**（-0.418×2）：
   在单 die 7 系上这些 SSI/流程变体退化为同一指令集，数据交叉验证了测量一致性。
4. **SpreadLogic 方向反转**：medium（-0.195，第 3）> low（-0.254）> high（-0.509），
   与此前"high 最好"的单点结论相反；此前只用 high 是欠采样的教训。
5. **WLBlockPlacement 失败端点仅 9 个**（-0.220）：路径最集中，若配合 RTL 定点修复
   是候选。WLBlockPlacementFanoutOpt 反而最差之一（-0.716）——fanout 优化副作用。
6. **Area 族确实省资源**：LUT 11236~11427（-3%），但时序 -0.51~-0.94。
   Flow_Quick 灾难性（WNS -32.9、hold -0.146、TNS -321610），仅作运行时换时序的极值参考。
7. **结合 dcache 新 RTL 的收敛预期**：dcache 流水线版（修复功能后）在
   ExplorePostRoutePhysOpt 下 WNS=-0.055；按 ExploreWithRemap 相对提升 ~0.059 ns
   外推，**新 RTL + ExploreWithRemap ≈ +0.004 ns，100 MHz 极可能收敛**。
   这是当前最高确定度的收尾路径：修 dcache 功能（方案见 dcache_fix_plan_for_opencode.md）
   → 用 ExploreWithRemap 复测。

## 结论与建议

- 旧 RTL 策略空间已完全关闭（33/33 测完，最优 -0.118）；生产构建策略更新为
  **Performance_ExploreWithRemap**。
- 收尾主线：dcache 功能修复 → 功能回归全绿 → ExploreWithRemap 复测 → 若仍差
  极少量再动 captured_addr_reg/CE 使能解耦。
- 100 MHz timing not met 状态保持到实测收敛；上板门禁（板型/pinout/IO delay/
  固件镜像）仍待 B02/B03/V01/I08/Y01。

## 证据位置

- 报告：`build/reports/strategy_sweep_20261017/<run>/`（每策略 8 份报告 + strategy_props.txt）
- 汇总：`data/ascon/results/strategy_sweep_20261017/strategy_sweep_summary.{json,csv}`
- 综合/实现日志与 checkpoint：`build/local/strategy_sweep{,_log}/`（git 忽略，失败尝试日志保留）
- 流程与踩坑沉淀为 skill `vivado-strategy-sweep`
