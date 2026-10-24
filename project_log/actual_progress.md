# 实际进度

## 2026-10-20 — V11 时序余量取证：P&R 空间关闭，建议降频；上板清单成文

owner TBD；基线 `3c6f134`（工作区 clean）。未改 RTL/XDC/XCI/COE，未 commit/push，未上板。

- **余量取证**：4 个 P&R 变体（同一 post-opt netlist，隔离目录）并行实测，
  WNS 分别 +0.008（无 pblock/ExtraTimingOpt）、+0.020（3-region pblock/ExtraPostPlacementOpt）、
  +0.001、+0.001（紧 pblock 两版）；TNS 0、失败端点 0。加上此前 33 策略扫掠与
  V09 修复，**P&R 侧余量空间判定关闭**，最佳 +0.020 ns 不构成可用余量。
- **根因修正**：不是单条坏路径。`acb_remap_routed.dcp` 实测 slack 分布
  <0.1 ns 55 条、<0.3 ns 334 条、<0.5 ns 1058 条、<1.0 ns 3731 条；
  4 个变体各自的最差路径互不相同（`id_ex sel_*_o → if_id CE / dcache DIADI`、
  `ex_mem → dcache lru`、`pc → icache tag → csr → ISE state CE`），
  说明这是一道整体 Fmax 墙（≈100.1 MHz），单点 RTL 断链只能防翻负、不能加余量。
- **布局实测**：`u_cpu_core` 分布 X32..106 / Y0..113，`u_dcache` 单模块跨 111 行，
  全设计仅 22% LUT；但 pblock 紧约束并未改善（+0.001），故布局不是解。
- **建议**：上板频率定 80 MHz；同一已布线网表只改时钟周期实测 WNS：
  90 MHz +0.965、80 MHz +2.340、75 MHz +3.165（折算到最终网表 ≈ +1.11/+2.48/+3.31），
  WHS 恒 +0.023；cycles/cpb/加速比不变。保 100 MHz 则只做 ISE CE 断链防翻负。
  任何上板版本必须重新 STA（PS7/IO/时钟源全变）。
- **文档**：[时序余量方案](../docs/timing_margin_plan.md)、[上板分步清单](../docs/board_bringup_plan.md)；
  新增脚本 `build/sweep_margin_phys.tcl`、`build/probe_timing_wall.tcl`、`build/probe_geometry{,2}.tcl`；
  证据 `build/reports/margin_20261020/*/`、`build/local/margin_20261020/`。
- **未完成**：降频后的实测 STA（需改 XCI，待用户决定）；L1 RTL 断链（属 RTL owner）；
  B02/B03/B04/V01/V03/Y01~Y05/S01~S05 状态不变。
- 首轮脚本用 `get_timing_paths -pulse_width` 取 WPWS 抛错（2025.2 无该选项），
  发生在写 result.txt 之前；RPT 正常，数字取自 `route_timing.rpt`，脚本已修正。

### 追加：砍 dcache 评估 + 架构改动方案（用户询问）

- 导出 14164 条 slack<2.0 ns 路径逐条分类（`build/probe_path_classes.tcl` →
  `build/local/margin_20261020/paths_lt_2p0.csv`）：
  `id_ex_u` 最差 **−0.140**（647 条 <0.5 ns）、`u_if_stage` −0.071（358）、
  `u_dcache` −0.071（308）、`u_icache` +0.074（124）、`u_ex_stage`/`u_ascon_ise` +0.133（206/198）、
  `u_ascon_mmio` +0.108（1670 条 <1.0 ns）。最差 10 条中 9 条从 `id_ex_u` 的旁路选择寄存器出发。
- **砍 dcache 结论：时序收益 0**（所有 dcache 相关路径消失后剩余 WNS 仍 −0.140，最差路径在
  id_ex 内部），性能为负（load 命中 1 拍 → AXI 读 ≥4 拍，且软件基线掉得比 ISE 多，
  会虚增加速比）。不做。
- 收益模型：单模块 +1.5 ns → 只有 id_ex 能到 −0.071；dcache+id_ex +0.089；再加 if_stage +0.108；
  全部模块才 +1.281 → **要 +1.0 ns 必须多模块协同**。
- 方案与门禁：[cpu_timing_architecture_plan.md](../docs/cpu_timing_architecture_plan.md)
  （B `bus_addr_r` CE 断链、C store buffer 一级、E ISE cancel 移出 CE 锥——均 0 周期；
  A id_ex 旁路网提前寄存、D if 控制、F mmio 内部拆拍）。估算 2.5 天 + 全套回归，与 10-27 冻结冲突。
- 并行免费尝试：`build/synth_margin_variants.tcl`（flatten full + PerformanceOptimized /
  AlternateRoutability / rebuilt+AlternateRoutability，实现统一 ExploreWithRemap），
  结果 `build/reports/synth_margin_20261020/<tag>/`；**已跑完**：
  `flat_perf`（full+PerformanceOptimized）**WNS +0.034** / TNS 0 / 0 失败；
  `flat_alt` −0.470（561 失败）；`rebuilt_alt` −0.008（3 失败）。综合选项不是解，
  但 flatten=full 可与方案 A 一起带。

### 追加 2：B + E 补丁落地并验证等价（用户指示“先做 B+C+E”）

- 补丁（可直接 `git apply`，未改 `src/rtl`）：`build/patches/timing_B_dcache_bus_addr_ce.patch`
  （dcache `bus_addr_r` 使能改为 `cache_access_fire`，去掉 cacheable 12 位比较与地址依赖）、
  `build/patches/timing_E_ascon_ise_cancel_ce.patch`（`cancel` 移出 320 位 `state` 使能，
  改为 `cancel_d` 延迟一拍物理清零 + `{cancel,cancel_d}` 读掩码，写入优先于清零）。
- 等价性（`build/check_bce_patches.sh`，控制组=当前 `src/rtl`，打补丁=隔离副本）：
  ise PASS/2496、ise+HOLD_ISE PASS/2496、ise+RESET_ISE PASS/2496、
  ise 安全套件 **402 checks PASS/0 failed**、hw PASS（99/670 cyc）、
  sw PASS（17353/21515/17847/22094 cyc）——**六种场景逐项一致，周期数完全相同**。
- 说明文档：[timing_bce_patches.md](../docs/timing_bce_patches.md)。
- STA（ExploreWithRemap，打补丁 RTL）已提交后台运行，结果待补；
  预期 WNS 仍在 −0.14/+0.01 量级（#1 在 id_ex CE 锥，B/E 碰不到）。
- C（store buffer）本轮未做：它解的是 #3/#4（−0.047/−0.019），需处理 back-to-back store、
  store→load 字节转发、fill 端口冲突，风险高于收益，排在方案 A 之后。

### 追加 3：B/E 判定净负，A1 落地（2026-10-20 22:50）

- **B/E 不落地**。功能/周期全等价，但 STA 实测：`e_only`（仅 ISE cancel −0.273 ns / 137 失败端点）、
  `e2`（dcache CE + 修正版 cancel，−0.643 ns / 649 失败端点），对照 control +0.007。
  原因：WNS 对网表扰动有 ±0.7 ns 敏感度，这两处只重排使能、不减逻辑深度。
- **A1 落地**（`build/patches/timing_A1_ex_stage_alignment_narrow.patch`）：
  `src/rtl/ex_stage.v` 非对齐判定改用 3 位部分和（`(a+b)[2:0] == (a[2:0]+b[2:0])[2:0]`），
  把 32 位地址加法器从 `trap → flush → ID/EX 使能` 锥里摘出。
  实测 **WNS +0.016 / TNS 0 / 0 失败端点 / WHS +0.012 / LUT 11821(+3)**；
  最差类由 13 级/8 CARRY4/logic 3.564 ns 变为 9~10 级/1~2 CARRY4/logic ~1.93 ns。
  功能与周期六场景逐项一致（ise/stall/reset 2496、安全 402/0、hw PASS、sw 17353/21515/17847/22094）。
- **100 MHz 天花板**：A1 + 4 个 floorplan/directive 变体 = +0.003 / +0.022 / −0.041 / −0.297，
  最优 **+0.022**（A1 + pblock X50Y0:X113Y99）。最差路径始终是 `pc → icache tag → CE`
  （logic ~2 ns、route ~7.6 ns 占 78%）。不改流水结构，100 MHz 余量就到 +0.02 量级为止。
- 下一步二选一：`icache` tag 打一拍（+1 取指周期，需重测全部 benchmark，与 10-27 冻结冲突），
  或演示/上板定 80 MHz（同网表实测 +2.340 ns，cycles/cpb/加速比不变）。
- 证据：`build/reports/bce_timing_20261020{,_a1,_a1_pr,_b_only,_e_only,_e2}/`、
  `build/reports/margin_a1_20261020/*/`、`build/local/patches*/`。



## 2026-10-18 — V10 数据复验一致；并行恢复产物按用户决定暂保留

owner TBD。用户明确选择保留最终双策略 RPT，清理旧报告/无用 BAT/JSON/TXT 及可再生缓存，
并要求删除后重检数据。曾执行删除564个文件（17.82MiB），含312旧RPT、66中间JSON、48TXT、4BAT；
随后并行会话恢复/重生成6个路径，用户最新决定暂时保留，当前并非只剩最终报告。
必要元数据、最终DCP、生产源、KAT、ISA控制/最终候选结果未删。逐文件删除hash及231项保留hash已记录。
8项CPU新label真实重编译/仿真全部PASS，源码/有效固件bin/测试输出/周期逐项一致；
安全/5单元一致，ISA仍49 PASS+ma_data既有1 FAIL；231项保留hash均不变。
原复验脚本exit 1及FAIL JSON保留：唯一失败是删除目标重新出现的留存检查，不是数据不一致。
复验判读为数据PASS、留存DEFERRED；本任务最终清理收口blocked，等待并行任务结束再确认。
本次不改RTL/固件/XDC，不重做布局布线；旧汇总脚本增加缺报告时的明确退出提示。
详见 [V10 清理与复验](../docs/workspace_cleanup.md)。未commit/push，未上板。

## 2026-10-18 — V09 100 MHz 芯片级 STA 收敛（已核验）

owner TBD；基线 f52bc49 + 工作区 dcache/ascon_ise/ex_stage/mult 修改（另一个 AI 完成，
本 Agent 独立核验）。未 commit/push；未上板。

- **收敛结果（已核验两份最终报告 timing_acb_20261018/）**：
  Performance_ExplorePostRoutePhysOpt WNS=+0.001/TNS=0/0 失败端点/WHS=+0.031；
  Performance_ExploreWithRemap WNS=+0.007/TNS=0/0/WHS=+0.023。100 MHz STA 通过。
  此前 93 个 ISE s_reg 复位端点与 48 个乘法器端点全部消除。
- **功能回归（ACB 套件，已核验）**：sw/hw/ise 与 security、stall/reset 注入全 PASS；
  ISA 49 PASS + 1 FAIL（rv32ui_ma_data），与修改前对照组完全一致（既有失败，非本次引入）。
  周期恢复：hw 670 / ise 2496（与 HEAD 持平）。
- **余量警示**：收敛余量仅 1-7 ps，处于布局噪声量级（s_reg 路径实测跨布局摆动
  -0.05~-0.128）。双策略同为正提供一定防误证，但此后任何 RTL 改动都可能重新翻负；
  建议以此为冻结检查点，再动必须全套复验。
- **未完成**：板级 IO delay/板型/pinout（B02/B03）、PS/PYNQ（P1）、Ascon 固件镜像
  替换（COE 仍 FreeRTOS）、板上 KAT/benchmark（V01/I08/Y01）。芯片级收敛不等于上板通过。
- 证据：build/reports/timing_acb_20261018/{postroute,remap}/、
  data/ascon/results/key_lifecycle/*_timing_acb*.json、data/ascon/results/isa/{fix_r1_control,timing_acb}/。

## 2026-10-18 — V09 A→C→B 与双策略完成：既有 100 MHz STA 通过

owner TBD；用户要求先解除 93 个 ISE 私有复位端点，再处理乘法器 48 端点、恢复 store/MMIO 延迟。
已通过独立 fix_r1 DCP 端点导出证实基线分类 93/48/11/4（共 156），未改原 DCP/扫掠工程。
A 注册 ISE 局部 reset；C 注册乘法输入/输出、done 保持到 ack；B 仅让 load miss 走 MISS_CAPTURE。
A/C 定向 Icarus 与 XSim 测试通过，恢复的 50 项 RV32I/M 指令体全部重跑：49 PASS、ma_data FAIL；
控制快照同样失败（不支持硬件非对齐读），不隐去 exit 1 或宣称全绿。最终整机 8 项、
MMIO/ISE 生命周期及单元 5/5 全部 PASS，生产源码 hash 与当前工作区匹配。
软件、hw full MMIO、ISE 周期恢复到 HEAD 的 17353（enc16B）/670/2496，B 的性能代价已收回。
两策略同快照实现通过 Ross 完成（exit 0，3895.571秒）：PostRoute WNS=+0.001/TNS=0/WHS=+0.031；
Remap WNS=+0.007/TNS=0/WHS=+0.023，均 0 setup/hold/pulse 失败端点、0 路由错误。
**原 93 个 ISE、48 个乘法器、11 个 dcache 与 4 个其他端点类别全部归零**；未改 LRU/频率/时序例外。
40 个生产源 hash 与测试工作区一致，XDC 与 baseline 副本 hash 相同。
候选推荐 Remap（LUT11752/FF16040/BRAM38.5/DSP4）；只余 7ps，不宣称跨变更鲁棒性。
这仅是既有约束下 STA 通过：3 个输入/3 个输出仍缺 IO delay，方法学/板级电气与 DRC/实板未验收。
详见 [V09 验证](../docs/timing_acb_validation.md)。
V09 本轮范围 done；未 commit/push，未上板；完整特权/RV64/嵌套中断门禁仍未验收。
下一接收 B03/V01/I08，先做板卡与 IO/电气约束/DRC，再进行 bitstream/实板 KAT。

## 2026-10-18 — V08 dcache MISS_CAPTURE 功能修复 fix_r1 + Ross 接入 OpenCode

owner TBD；基线 f52bc49 + 工作区。按 [dcache_fix_plan_for_opencode.md](../docs/dcache_fix_plan_for_opencode.md) 执行。

- **Ross**：本机已有 vivado-mcp-server 2026.9.1；登记到 OpenCode 全局配置 `mcp.servers.vivado`
  （`--stdio`，VIVADO_PATH=2025.2），已实测连接并用于 vivado-rtl-lint。
- **dcache.v 修复**：MMIO 读改为固定延迟移位（对齐延后一拍的 bus_mmio_re）；MISS_CAPTURE
  全部改用 IDLE 拍寄存的请求类型标志，不再读活 hit/cacheable/cpu_re_i；总线请求一律单拍脉冲
  （原 bus_mem_re_r 在 FILL 期间保持高，会让互连排队第二个伪读突发）。接口不变。
- **功能门禁全 PASS**：HEAD 对照筛选、wt 筛选、sw/hw/ise、hw/ise --security（123/0、402/0）、
  单元 4/4、ise --stall/--reset；Ross lint 2 条 WARNING 与 HEAD 完全相同。
- **周期代价（同工具链对 HEAD）**：sw +0.3%，hw full MMIO 670→717（+7.0%），ise 2496→2550（+2.2%）。
- **时序（ExplorePostRoutePhysOpt）**：WNS=-0.128/TNS=-11.213/156 端点，WHS=0.005，路由无错误。
  **门禁 4.4（WNS≥-0.078）未过，100 MHz timing not met**。最差 20 条路径无 dcache，
  新最差为 pc_reg→ascon_ise s_reg/R（复位/冲刷扇出，布线占 80%）。证据见
  [清单 §11](../docs/dcache_fix_checklist_en.md)。
- 未 commit/push；未上板。下一步：ISE s_reg 复位扇出路径；可选只让 load miss 走 MISS_CAPTURE。

## 2026-10-18 — V08 全量 33 策略扫掠完成 + dcache 流水线评估

owner TBD；基线 f52bc49。用户授权补测"其余全部策略"并评估另一个 AI 的 dcache 优化。

- **策略扫掠**：四批共 35 个 run（33 个 2025.2 标准流程策略 + 2 个回退重复已剔除），
  全部 exit 0。最优 **Performance_ExploreWithRemap WNS=-0.118/TNS=-1.008/22 端点**，
  超过此前最优 ExplorePostRoutePhysOpt（-0.177）。33 策略完整排名与分析见
  [ascon_strategy_sweep.md](../docs/ascon_strategy_sweep.md)。
  高级实现流程（Vivado Advanced Implementation 2025）在 xc7z020 上不支持（12-25131
  静默回退），其 4 个独有策略批处理不可测，已记录。
- **dcache 流水线版（另一个 AI）**：独立实测（Performance_ExplorePostRoutePhysOpt）
  MISS_CAPTURE 版 WNS=-0.055/TNS=-1.122/40 端点（三版最佳，DONT_TOUCH 版 -0.078）。
  但功能回归 sw 模式 TIMEOUT：CPU 在 t=275、pc=0x100083f0 死锁（MMIO 读等待依赖
  bus_rdata_valid_i 而 bus_mmio_re_r 仅 1 拍脉冲，握手永不完成）。HEAD 原版 PASS 对照。
  两版均功能不可用；修复方案交付另一个 AI：[dcache_fix_plan_for_opencode.md](../docs/dcache_fix_plan_for_opencode.md)
  + [英文清单](../docs/dcache_fix_checklist_en.md)。遗留同名 module 实验文件已移入
  src/rtl/dcache_experiments/（Vivado 同名模块静默选文件的坑）。
- **收敛预期**：新 RTL（修复后）-0.055 + ExploreWithRemap 相对提升 ~0.059 →
  ≈+0.004 ns，100 MHz 极可能收敛；待功能修复后实测。
- 100 MHz timing not met 保持；上板门禁 B02/B03/V01/I08/Y01 不变。未 commit/push。

## 2026-10-18 — V08 实现策略扫掠（Strategy Sweep）

owner TBD；基线 f52bc49，本机 DESKTOP-5H4M0DR（V06 两轮在 xyq 机上）。用户授权
全量 10 策略扫掠并记录数据与分析；未改任何 RTL/XDC/XCI/COE，未 commit/push。

- 本机 Vivado 2025.2 原缺 Zynq-7000 器件库（open_project 报 part 不可用）；用户经
  "Add Design Tools or Devices 2025.2"（C:/ruanjian/.xinstall/2025.2/xsetup.exe）
  补装 Zynq-7000 后 `get_parts xc7z020clg400-1` 通过。
- 新脚本 build/sweep_strategy_timing.tcl（隔离工程、共享 synth、按最终步骤分组
  3 路×6 jobs 并行波、TSV 断点续跑）+ build/aggregate_strategy_sweep.py（.rpt 解析
  交叉核对）。多次中断续跑，最终 exit 0、SWEEP COMPLETE、10/10 策略完成、无真实 ERROR。
- 结果：最优 **Performance_ExplorePostRoutePhysOpt WNS=-0.177/TNS=-2.968/31 失败端点**，
  其次 Performance_Explore -0.273、NetDelay_high -0.325；最差 Default -0.942。
  与本机重跑的 Default/ExplorePostRoute 与 V06 xyq 机逐位一致（跨机可复现）。
- 结论：10 个内置策略无一收敛 100 MHz；策略空间已关闭，剩余 0.177 ns 属 CPU
  id_ex→dcache CE/DIADI 地址计算路径（路由主导），转入 RTL 修复。
  详见 [策略扫掠分析](../docs/ascon_strategy_sweep.md)，数据在 data/ascon/results/strategy_sweep_20261017/。
- 流程与踩坑沉淀为 skill vivado-strategy-sweep；报告在 build/reports/strategy_sweep_20261017/。
- 上板门禁不变：100 MHz timing not met，B02/B03/V01/I08/Y01 仍待接收。

## 2026-10-17 — V07 Ross/工程Skills评估与有限审查

owner TBD；先完成稳定检查点`2b48a8a730267787b399fe06304ae5e2b53ff203`并推送，草稿
[PR4](https://github.com/HChenZ/amd_fpga_2026/pull/4)明确100 MHz未收敛、未上板；原工作区保留。
Ross官方Windows Server下载遇AMD会话错误19，本机未安装/配置，MCP timing/utilization均not_measured。
文档核实2026.1完整测试基线及各Skill版本差异；当前2025.2/Tcl保留，未升级或启动网络控制服务。

只安装Matt Pocock code-review/diagnosing-bugs/tdd/pr四项，固定提交、无插件重复；12文件hash一致，
本机Codex skills/list四项enabled、0 errors。按code-review做只读双轴审查：需求0项，规范1项P2
（缺失/部分实现快照可能误判匹配）。修复证据门禁，5项测试PASS，独立复核关闭该发现。
新最终源码清单119文件，六组CPU输入和实现RTL未变，无需重跑长仿真或Vivado。

评估与优先级见[工具报告](../docs/ross_and_engineering_skills_evaluation.md)、
[双轴审查](../docs/ascon_branch_review.md)及`data/ascon/results/tool_evaluation/`。
V07评估完成不表示Ross接入或V06时序/板级门禁完成；下轮先核板型和CPU/cache剩余路径，Sweep延后。


## 2026-10-17 — V06 阶段性收尾与证据复核

owner TBD；工作区 E:/amd_fpga_2026_key_lifecycle，分支 fix/ascon-key-lifecycle。
2026-10-16的两轮实现均完整结束；本日只读复核源码/日志/报告，不重开Vivado，不做第三轮优化。
117个源码hash、所有物理报告hash、六组CPU测试输入和实现RTL快照均匹配；XDC/COE及原baseline未改。
blk_mem_gen独立副本仅有工具元数据/checksum改写，功能参数不变，双侧hash已保存。

- 最终软件/MMIO/ISE原KAT均PASS；动态密钥安全检查132/123/402项全部PASS。
  Host Final 28661项、C失败输出23965项、MMIO/ISE RTL 13212/1500项、4个CPU单测、
  4个RTL故障注入门禁与867请求逐周期等价检查均PASS。复用哈希一致证据，未重跑长测试。
- 最终Vivado2025.2、xc7z020clg400-1、top_pl_bram：WNS=-0.177ns、TNS=-2.968ns，
  31个setup失败端点；WHS=0.015ns/THS=0、WPWS=3.750ns/TPWS=0。
  LUT11636/FF15949/BRAM38.5/DSP4；23917个net fully routed，routing errors=0。
- **100 MHz timing not met**。DRC已报告95 Warning/0 Critical Warning/0 Error（部分规则达到上限），
  Methodology另23 Warning。cache地址/hold控制剩余路径、LUT派生复位、BRAM异步控制、PS7与板级IO覆盖仍需处理。
- 安全修复与时序分析可作为阶段性成果提交；V06保留in_progress，上板门禁未过。
  官方固定KAT与运行时参数边界明确，新增3组公开Key/Nonce；没有真实秘密或生成缓存纳入提交。

完整证据：[最终汇总](../data/ascon/results/key_lifecycle/final_validation_summary.json)、
[时序审查](../docs/ascon_timing_review.md)、[密钥审查](../docs/ascon_key_management.md)。
下一接收 B02/B03/V01/I08/Y01；先保存Git检查点，再进行用户授权的Ross/Skills低风险评估。


## 2026-10-16 — V06 密钥生命周期与上板前审查

owner TBD；基于最新 origin/main `c37ecae`，独立 worktree / `fix/ascon-key-lifecycle`。
用户本轮明确授权检查通过后自动 commit/push，原工作区未提交改动全部保留。

- 三套实现均已存在，不能沿用下文早期“未实现 ISE”的结论。新增 [密钥生命周期审查](../docs/ascon_key_management.md)
  与 [板卡清单](../docs/ascon_board_checklist.md)，详细结果索引为 `data/ascon/results/key_lifecycle/validation_summary.json`。
- 修复：MMIO idle CTRL[2] ZEROIZE、BUSY/失败/越界读保护、旧输出清理和尾字屏蔽；
  ISE 失败输出擦除/长度、部分密文 Tag 指针、状态清理、非法索引、完成保持；
  CPU 提前译码遗漏的 custom 操作数旁路/load-use；软件 C 本地敏感对象擦除。
- 固定官方 KAT 不变；3组公开动态 Key/Nonce、27个长度组合由锁定 Final C/Python 交叉核对。
  MMIO 只跑其中21例（AD/消息各<=16字节），不宣称多块接口。
- Host Final 28,661 PASS/0 FAIL，production C raw failure 23,965 PASS/0 FAIL；
  独立 RTL 全源集 Final KAT/置换/认证与故障注入通过。MMIO 13,212、ISE 1,500项检查通过；
  baseline bypass/regfile/EX ALU 与新增 execute cancel/hold 单测通过。
- CPU 软件/MMIO/ISE 的最终 KAT、安全测试和周期结果由上述 JSON/原始日志定稿；
  明确使用 GCC13.2/仿真50MHz，不与队友 GCC15.2 的历史数值混算。
- Vivado2025.2可运行，原始三个IP未锁定且再生成成功。独立副本综合0 errors/0 critical warnings；
  实现结果、时序、资源、DRC在最终汇总中列明。原 baseline、XCI、XDC、COE不改，579项恢复资产hash通过。
- 真实板型未知、未烧录；FreeRTOS COE未换为Ascon固件，PS/PL/PYNQ尚未建立。
  ISE完整抢占上下文、全部ISA/异常/外设回归、板上测量仍未完成。清零不等于抗侧信道/物理提取。

最终补记：三套CPU原KAT全部PASS；新增安全检查软件132/132、MMIO123/123、ISE402/402，
ISE含下游hold跨完成和计算中reset重启。16B warm加密仿真周期：软件18348、MMIO完整往返664
（START→轮询完成100）、ISE2559；软件32B enc22817，dec16B18886/32B23388。
六个最终源码loadable binary与已测镜像逐字节一致，ISE反汇编有实际custom-0编码。
Vivado布线完成exit0，但100MHz WNS=-1.641ns、TNS=-607.794ns（1971失败端点），
LUT11683/FF15960/BRAM38.5/DSP4；DRC已报告95项Warning、无Error（部分规则达到报告上限），
存在PS7缺失、BRAM/复位与IO delay覆盖告警。故V06保留in_progress，上板门禁未通过。
已完成的安全修复与仿真可审查，时序收敛/实板功能不可标完成。

下一接收 B02/B03/V01/I08/Y01，owner TBD。历史与中间失败保留，不把综合或仿真冒充上板。


## 2026-10-15 — Ascon-AEAD128 软件版在自研 RV32IM CPU 上运行并测得软件性能

owner TBD；用户授权"调用已有 C 代码库完成软件版、测试保证处理器可用、测软件性能"。
未改任何现有 RTL/TB/KAT/脚本；新增固件与仿真平台，全部落在约定目录。

- 新增 src/firmware/ascon_rv32/：crt0.S、riscv.ld（ORIGIN=0x10000000 对齐复位 PC）、
  main.c（`#include` 锁定生产 ascon/ascon_c/aead/aead.c）、uart.c/h、libc_min.c、
  bin2vhex.py、build.sh。工具链 riscv-none-elf-gcc 15.2.0，
  `-march=rv32im_zicsr -mabi=ilp32 -O2 -ffreestanding -nostdlib -lgcc`；
  64 位软件基线因此需要 libgcc(__udivdi3/__lshrdi3 等)。镜像 code=38852 B、data=0、bss=0。
- 新增 sim/ascon/axi_slave_bram.v（AXI4 行为 BRAM：4 拍 WRAP 读 + 单拍写 + $readmemh）
  与 tb_ascon_sw.v（soc_top @50MHz + BRAM + UART monitor 解码 txd、检测 DONE/FAIL 标记）。
  入口 sim/ascon/run_ascon_sw.sh 一次完成 交叉编译→iverilog 编译→vvp 运行。
- 实测（Icarus 14.0 devel / vvp，退出码 0）：6 组官方 KAT（empty/1B/16B/16B+AD/17B/32B）
  加解密全 PASS，tag 篡改拒绝 PASS；CPU RTL(soc_top) 确实执行 ISE 无关的纯软件 Ascon。
- 软件性能（warm，模拟实测，非上板）：enc 16B=16840 cyc(1052.5 cpb)、enc 32B=21018(656.8)、
  dec 16B=17226(1076.6)、dec 32B=21461(670.7)；CPI≈3.9~4.0。mcycle 用 CSR 0xB00/0xB80
  high-low-high 读取；指令数用 cpi_cnt MMIO(0x60000000/04)。UART@115200 主导 cycle 量
  （每字节 4340 clk），故加密/解密各运行两遍取第二遍作为 warm 测量。
- 未验证/未测：上板(B02/B03)、Vivado 综合/实现/PPA、CPU ISE、完整 1,089 KAT 的目标运行
  （仅 host 全量 + 目标 6 组代表向量 + 篡改）。cycle 为仿真实测，不是 board 实测；未改任何 RTL。

C02 目标编译/运行与 C04 CPU 级软件 benchmark 已在仿真层达成；C03 目标 KAT 为 6 组代表向量
（全量仍在 host）。板级与 ISE 仍依赖 B02/B03/V01 后续接收。

## 2026-10-15 — Ascon MMIO 加速器接入 CPU（第一次硬件优化）

owner TBD；用户授权"结合 IO 接口代码把已写好的硬件接入、做第一次优化并测试"。
复用队友 IO/ 的 ascon_mmio.v（寄存器文件+FSM+缓冲，基址 0x30000000）与已 KAT 验证的
crypto_aead.v，新写 ascon_aead_core.v（32-bit 流式接口 → 128-bit 并行 crypto_aead 的适配器）。
改了 bus_interconnect.v（新增 ascon MMIO 译码 + read_sel_q 扩 6 位）与 soc_top.v（实例化
ascon_mmio、ireq_external 并入 ascon_irq），均为 README 记录的增量接线；未动 crypto_aead.v。

- 新增 src/rtl/ascon/ascon_mmio.v（队友 IO 原件字节一致复制）、ascon_aead_core.v
  （streaming 适配器，≤16B AD/msg，超长立即 done+success=0 拒绝）。
- 新增 src/firmware/ascon_hw_rv32/（MMIO 驱动固件，code=3936 B）与 sim/ascon/run_ascon_hw.sh。
- 关键 bug：crypto_aead 的 mode=0 加密/1 解密，而 ascon_aead_core 的 encrypt=1 加密/0 解密，
  初版直连导致所有加密请求按解密执行（空消息 tag 恰好仍对，非空全错）。修 .mode(!encrypt_r)。
- 实测（Icarus 14.0/vvp，exit 0）：4 组官方 KAT(empty/1B/16B/16B+AD) 加解密 PASS、
  解密往返 PASS、tag 篡改拒绝 PASS、17B 超长拒绝 PASS——CPU 通过 MMIO 驱动硬件 Ascon 正确。
- 性能（warm，仿真实测，非上板）：16B 加密 纯 crypto 延迟 99 cycles、完整 MMIO 往返 544 cycles；
  对比纯软件 16840 cycles → crypto 核心 ~170×、端到端(含寄存器读写+轮询) ~31×。这是 ISE 前
  的第一级硬件加速，MMIO 开销(寄存器写+轮询+读回)是下一步 ISE 要压缩的部分。
- 未验证/未测：上板、Vivado 综合/PPA、>16 字节消息、真正的 CPU ISE(I02~I07)。未改 crypto_aead.v。

## 2026-10-15 — Ascon 置换 custom instruction (ISE) 完成（最后的优化）

owner TBD；用户授权"继续完成 ISE 优化并测试，这是最后的优化"。在 RV32IM 软核里加入
Ascon 置换 custom instruction（custom-0 opcode 0x0B），复用已 KAT 验证的 p12/p8 模块，
CPU 用 inline asm 跑置换、其余 AEAD 逻辑仍用 C。改了 defines.v / id_stage.v / ex_stage.v
（新增 opcode/func_sel、译码、执行与多周期 stall，仿 divider 的 ex_stall_req 机制），
未动 crypto_aead.v/p12/p8。

- 新增 src/rtl/ascon/ascon_ise.v：CPU 内 320-bit 状态寄存器 + p12/p8 握手。
  4 条指令（.insn r 0x0B, funct3, funct7=0, rd, rs1, rs2）：
  `ascon.w`(f3=0, rs1=data, rs2=word idx) 写状态字；`ascon.rd`(f3=1, rs1=idx, rd=dest) 读状态字；
  `ascon.p12`(f3=2)、`ascon.p8`(f3=3) 跑置换（多周期，perm_start 电平 + ex_stall_req=~perm_done）。
  状态字 0..9 对应 s.x[0..4] 的 32-bit 小端切片。
- 新增 src/firmware/ascon_ise_rv32/（inline asm + 完整 AEAD，code=6216 B）与 run_ascon_ise.sh。
- 关键坑：GAS `.insn r` 格式是 `opcode,funct3,funct7,rd,rs1,rs2`（funct7 在 rd 之前），
  不是 `opcode,funct3,rd,rs1,rs2`；写错会报 "bad value for funct7 field"。
- 实测（Icarus/vvp exit 0）：4 组官方 KAT(empty/1B/16B/16B+AD) 加解密 PASS、解密往返 PASS、
  tag 篡改拒绝 PASS。反汇编确认 142 条 opcode 0x0B 的 custom 指令，非静默 fallback。
- 性能（warm，仿真实测）：16B 加密 **1880 cycles**（vs 纯软件 16840 → ~9.0×，~117.5 cpb）。
  剩余开销来自状态字 load/store（每置换 20 条）与 LOADBYTES/STOREBYTES 字节搬运（未加速）。
- 未验证/未测：随机/边界/复位/连续请求的定向单元测试（I04 仅跑了 KAT 定向）；baseline 回归
  重跑（I05 只跑了 ISE 回归，未重跑软件/MMIO 全回归）；ISE-disabled 模式、中断/异常/flush
  与 ISE 交互；Vivado 综合/PPA（I08，需上板前补）。这些是 I04/I05 验收的剩余项，未标完全达标。

三级加速对比（16B 加密，均为 warm 仿真实测）：纯软件 16840 → MMIO 全卸载 544(~31×) →
ISE 置换 1880(~9×)。ISE 是 custom instruction 路径（CPU 编排、置换硬件化），MMIO 是全卸载
协处理器路径；两者互补。ISE 的编码/semantics/stall/inline-asm 落位；I03/I06/I07 已达标，
I01/I02/I04/I05 主体完成、上述未测项待补。

## 2026-10-10 — Ascon 加解密合并为统一 crypto_aead 模块

owner TBD；用户授权新建独立文件，未改现有 RTL/TB/脚本/KAT。将原独立
crypto_aead_encrypt / crypto_aead_decrypt 合并为单一 crypto_aead 模块，
用 mode(0=encrypt/1=decrypt) 选方向、共用一条状态机。关键洞察：Ascon 加
解密吸收的是同一份"明文 pad 版本"——加密直接喂输入明文，解密由 s^c 恢复
明文后吸收，故尾块 mask+0x01 逻辑可完全统一，输出恒为 s^data_in。

- 新增 src/rtl/ascon/crypto_aead.v：统一接口 clk/rst_n/start/mode/data_in/
  ad/npub/k/adlen/datalen/tag_in → data_out/tag/correct/done/busy/error。
  encrypt 输出密文+tag；decrypt 输出明文，仅 tag_in 匹配才置 correct 发布。
  17..31 长度两方向均 error 拒绝，decrypt 另保持 correct=0。
- 新增 sim/ascon/tb_crypto_aead.v：同一冻结向量同时测加解密，含逐拍
  data_out=0/correct=0 隐藏检查、tag 篡改拒绝、长度拒绝、连续调用。
- 新增 sim/ascon/prepare_crypto_vectors.py：无需 C 编译器（WSL 不可用），
  直接从锁定官方 KAT 取 289 组(PT/AD 0..16)生成 784-bit aead.mem，布局与
  既有 aead.mem 一致。
- 实测 iverilog 编译 exit0、vvp 运行 errors=0：加密 289、解密 289、篡改
  拒绝 289、长度拒绝 1470(735×2) 全 PASS；latency 空消息 34 cyc、16B 58~70
  cyc。全源集(新旧模块共存)编译 exit0、无重复 module。
- 未动 ascon_aead_2.v 及原 encrypt/decrypt，旧接口回归不受影响。合并模块
  尚未接入 CPU/ISE；Vivado/PPA/hardware cycles 仍 not_measured。

随后按用户方案 B，把 ascon_aead_2.v 的 crypto_aead_encrypt / crypto_aead_decrypt
改为实例化 crypto_aead 的薄 wrapper：端口名/方向/宽度/顺序不变，两条重复
状态机移除，底层逻辑单一来源（get_bytes 保留）。资源上，SoC 只实例化一个
crypto_aead 即可加解密复用一份，wrapper 为纯连线、综合可优化。

- 回归复验（wrapper 后）：队友 peer TB ALL PASS；加密 300 组+735 长度、解密
  310 有效+2,579 篡改+735 长度均 errors=0，数字与原 V05 一致；全源集编译
  exit0、12 模块无重复。tb_rtl_aead/decrypt 用 peer(5)+官方KAT(289)+tails(6)
  共 300 组向量（build/local/ascon_crypto/aead_full.mem）；WSL 不可用，故 peer
  ct/tag 取队友 TB 字面量、matrix 取官方 KAT 自带 expected，不重算。

下一接收：SoC 集成(I03/I05)时顶层直接实例化 crypto_aead（一个实例、mode
切换，加解密复用一份资源）；B02/B03/B04/V01 仍为在自研 CPU 运行 Ascon 前置。

## 2026-10-10 — V05/C03 功能分支提交前审查

owner TBD；用户授权在E:/amd_fpga_2026_integration将已验整合成果commit/push并创建
PR，base main；最终合并由用户确认。fetch确认main仍为0a425f9，整合分支正确。
本条记录提交前审查，不把尚未执行的push/PR写成完成；实际SHA与PR见Git历史及交付。
本轮仅更新发布审查文档/日志，RTL、TB、脚本及KAT均未改；已有PASS的源码哈希
重新核验。Encrypt所有现有实例均具名连接，无现有位置调用受追加error端口影响。
原工作区及外部备份只读核验，队友两份dirty结果不纳入；无CPU/Vivado/PYNQ改动。
提交消息feat(ascon): integrate RTL decryption and KAT validation；明确文件列表暂存，
不用git add .，不force、不推送main、不合并PR。V05/C03任务状态沿用前次实测边界。

## 2026-10-09 — V05/C03 最新main隔离整合与重新验证

owner TBD；重新fetch确认origin/main=0a425f9，独立worktree
E:/amd_fpga_2026_integration，分支feat/ascon-decrypt-kat-integration。
原E:/amd_fpga_2026保持7139a80/cleanup/remove-legacy-ascon-aead及全部28个未提交
文件。仓库外备份89文件7,636,392 bytes逐一SHA-256核验；包含队友原dirty结果。
未commit/push/创建PR/合并main；新分支不跟踪origin/main。

- 以remote为基础逐处修复，没有整文件覆盖旧本地RTL。保留队友初始化/AD、
  整块ciphertext吸收、尾块64-bit state masking/padding、P8/P12/finalization、
  full tag diff与计算tag输出；P8/P12和原队友TB逐字节未改。
- Decrypt原15端口名字/方向/宽度/顺序保持不变，无mlen/error/result新端口。
  done && correct读取接受请求的clen；认证前/失败m=0、correct=0。
  修reset/start未撤销旧认证/候选、完成后清候选；超长用correct=0拒绝。
  Encrypt追加error，所有现有具名调用兼容；整个AEAD加include guard。
- 原remote首请求busy时m/correct为X实测vvp exit1；原TBinclude+显式source编译
  exit6。首轮guard漏get_bytes编译exit2，失败全部保留，修源后重新完整回归。
- 新worktree新vector/新source：官方KAT289/289加密和解密，补充11/11；
  Encrypt311有效/控制调用、Decrypt310、篡改拒绝2,579、每方向超长拒绝735，
  全部0 FAIL；round264、P8/P12各28state比较PASS。接口具名/位置调用逐拍一致。
- 所有四个production.v编译exit0，10module无重复，全源加解密仿真exit0，
  原队友TB5组PASS。故障注入4/4，三个功能故障vvp exit1、坏向量runner exit1。
  参考全1,089 KAT gate12,936/0；软件四backend本worktree重跑28,661/0。
- 新证据rtl_integration_regression.*、rtl_integration_harness.json、
  host_integration_validation.*，记录0a425f9+实际dirty source/TB/scripts hashes，
  不是旧7139a80结果复用。工具版本/命令/退出码及保护说明见最新解密整合报告。
- 最终integration_review.json核验当前源码/验证源哈希、原28dirty和89备份未变，
  远程main仍0a425f9、diff --check exit0；暂存/提交/推送/PR为0。

V05整合子项done；C03 target仍in_progress，I03/I04/I05不因独立AEAD提升验收。
当前可供用户审查后commit/push功能分支并申请PR。本轮无Ascon仿真功能阻塞；
多块RTL、CPU/板级、Vivado、cycles/PPA仍未验证或not_measured。
下一接收B02/B04/V01/TBD→target KAT/mcycle→C04/I01/I02。下节保留先前本地历史。

## 2026-10-09 — V05/C03 standalone Ascon RTL 解密与生产全源集收口

owner TBD；基点7139a80，复用cleanup/remove-legacy-ascon-aead分支。
初始未提交rtl_regression.json/.log保留，新增rtl_decrypt_regression.*作为默认输出。
未commit/push/merge；CPU/Vivado/PYNQ/软件/锁定参考均未修改。

- 源码事实：crypto_aead_decrypt仍为空壳；35acd6a是C软件修复。
  本轮补齐RTL独立解密、完整tag认证与失败输出保护。encrypt新增error，
  加解密均拒绝物理总线不能承载的17..31-byte长度。
- before：permutation/encrypt/full-source compile PASS；runner因已删除legacy
  源路径exit1，保存rtl_decrypt_before.*。原encrypt实测17-byte请求正常done，
  长度probe simulation exit1，rtl_length_before.json保留真实失败。
- Icarus/vvp12.0：round264基础state比较PASS；P8/P12各22基础+6控制比较PASS；
  四个production.v全root编译exit0，10个module无重复；全源加解密仿真exit0。
- 官方RTL KAT：PT/AD各0..16的全部289组加密/解密均PASS，0失败；11组peer/尾零
  补充输入亦PASS。独立decrypt使用锁定expected C||T，不以encrypt反向自证。
  其余800官方组超出接口未运行RTL；完整1,089组C/Python reference gate
  12,936 PASS，软件四backend重跑28,661 PASS / 0 FAIL，均exit0。
- encrypt311有效调用；decrypt310有效调用、2,579篡改拒绝；加解密各735超长
  参数组合拒绝。每拍检查解密认证前m/mlen/result为0，失败当拍及之后仍为0。
  空/短/8与16边界/尾零、连续调用、busy-start忽略、reset中断/重新调用通过。
- RTL故障注入4/4：错误tag接受、错误明文、提前发布分别触发vvp exit1；
  损坏向量触发runner exit1。host harness 5/5通过。最终各入口exit0。
- 接口：rst_n同步低有效；start一拍；key/nonce/tag保持至done；显式length。
  decrypt新增c/tag/ad/clen/adlen与128-bit m/mlen/result/done/busy/error。
  完整契约、命令/版本/退出码/哈希与未测边界见
  docs/ascon_rtl_decrypt_validation.md、src/rtl/ascon/readme.md与results JSON/log。

看板：C01 done，C03 in_progress（target待验），新增V05 done；I03/I04真正ISE
保持todo。独立AEAD可以交付算法验证基础，但I05前置B02/V01和I02/I03仍未满足。
下一接收B02/B04/V01/TBD：CPU baseline与目标软件KAT/mcycle sanity，再C04/I01/I02。
阻塞：baseline/Vivado/固件依赖/板卡核验与CPU ISE未完成；当前Ascon仿真无功能阻塞。
Vivado综合/实现、CPU/板上、硬件cycles/speedup/PPA仍not_measured，多块RTL不支持。

## 2026-10-07 — 独立 RTL regression 提交收口

owner TBD；用户授权在 feat/ascon-kat-validation 创建
`test(ascon): add independent RTL regression`，不 push/merge。
审计原待提交 11 文件合计 190,057 bytes，最大 85,773 bytes；无重复大文件、缓存、
编译物或硬编码运行路径。结果中的绝对路径仅为实际命令证据，正式入口动态定位。
生产源/验证源与结果 hash 匹配，锁定来源/许可证完整；ignored pycache/vvp/so 不纳入。
暂存检查发现 Windows 报告换行问题，已修 runner 源输出为 LF 并重新生成/复验，
生产 RTL 不变。isolated PASS、旧接口 exit 2/full source exit 6 的 FAIL 原样保留，
整体 gate 未关闭；下一接收 RTL owner/TBD。

## 2026-10-07 — 同步最新 RTL 与独立回归追加

- owner TBD；用户授权 checkpoint/rebase。原 cba792c checkpoint 已无冲突 rebase 到
  origin/main `13d954f0755c2ec09290443e341cd5fb910fbf21`，新 checkpoint 为
  `a1d19dd7cd26da7d036d9b5612fb27f3cbf25680`。未 push/merge main；本地 main 未移动。
- 独立 C/Python 完整 KAT gate 重跑 12,936 PASS，队友五组 expected CT/tag 5/5
  与锁定 Final reference 一致；原始向量出处未记录，不能从 TB PASS 推断来源。
- Icarus/vvp 12.0：round/P8/P12 PASS，308 冻结基础用例及连续调用/reset/restart；
  新 isolated encryption 60 固定输入+9 控制请求 PASS（69 次 CT/tag 比较）。
  覆盖 mlen/adlen={0,1,7,8,9,15,16} 矩阵与尾零，没有伪造17-byte运行。
- 旧 AEAD isolated compile FAIL exit 2（reset/rst_n）；全部生产 .v compile FAIL
  exit 6（三个重复 module）。runner 整体 exit 1；isolated PASS 不等于可集成。
- decrypt=not_implemented。新 m/ad 各128 bits，目前能力上限各16 bytes。
  key 未锁存，须稳定到完成；busy-start 策略不一致、无效 c 位/empty 旧数据等
  观察与建议见 docs/ascon_rtl_regression_audit.md。

证据 `data/ascon/results/rtl_regression.json/.log`；新增入口及自己的 TB 在 sim/ascon。
生产 RTL 与 origin/main 相同，队友 TB 未修改。新回归/日志保留未提交，除授权
checkpoint 无新增 commit。看板仍不改；交接 RTL owner/TBD 修重复/接口后 I04 复验。
未做 Vivado/CPU/板级/PUF/PYNQ；硬件 cycles/PPA not_measured。

## 2026-10-07 — C01/C03 Final 标准与 host KAT 证据追加

本段为当前证据；下方 2026-09-21 表格保留历史快照。owner TBD。
初始 clean，main 从 ab458e5 fast-forward 到
`8c8634f80f55cff50ae1ffcaf6fb79d67e5a7a93`，含当天 `01 << (8*n)` padding 恢复。
创建 `feat/ascon-kat-validation`，本轮未 commit/push。

- C01：Final PDF、C/Python 固定 commit、许可与 18 文件哈希、独立完整上游 KAT
  已锁定；对照见 `docs/ascon_standard_baseline.md`。建议 done，待用户确认；看板未改。
- C02：现有 host C/Python AEAD 与 Final KAT 一致，WSL GCC 13.3 编译 C 通过。
  仍 in_progress：目标固件未编译/运行；C bad-tag 返回 -1 但留下明文和 mlen，
  failure contract 实测 exit 1。测试 adapter 丢弃输出不等于生产 API 已修复。
- C03：1,089 完整上游 KAT、64 补充 AEAD、308 permutation golden、16 短 tag 长度。
  四 backend 共 28,661 PASS / 0 FAIL，exit 0；harness 5 tests PASS。
  框架/host 子项完成，整体建议 in_progress，待 C02 前置与失败输出契约收口。
- reference gate 12,936 PASS；冻结数据重生成 byte-identical。真实 FAIL 与一次
  runner 共享库冲突原日志保存 `data/ascon/results/`；冲突已隔离构建并复验通过。
- 当前 RTL 已含完整 round、P8/P12 和 AEAD 草稿，09-21 的“只有 ror”是历史状态。
  本轮只记录长度推断/start 未接/输出截断/packed 数据推进/decrypt 空壳等问题，
  没有修改或仿真现有软件/RTL/CPU/Vivado；不能据此提升 Ixx 完成度。

证据：`data/ascon/provenance.json`、`results/host_validation.*`、
`results/failure_contract.*`、`results/audit_snapshot.json`；入口 `sim/ascon/readme.md`。
新增接口仅为独立 golden JSON/656-bit memory/CLI，生产接口未改。
硬件 cycles/PPA/RTL 功能 not_measured；接收 C02/C03/TBD，再 C04→I01/I02。

截至：2026-09-21，含 ZIP 恢复及 repository foundation 收口。owner 全 TBD；原 rename/生成元数据清理已在 fe66fd8；恢复资产已在 fc9147785cc4490b1673a0b86e16f337f256f122 本地提交。本文件随独立 foundation 文档提交保存；本轮未 push、未 merge main。初始审计基点仍为 e35d42f，不能将其误作当前开发分支 HEAD。

| 任务 / 范围 | 实际结果 | 证据 | 状态 / 局限 |
|---|---|---|---|
| B01 / D00 | 初始仓库审计、协作骨架已完成；现补充归档审计与结论更正 | docs/repository_audit.md、docs/cicc1000023_recovery_audit.md | done；审计不是功能验收 |
| B02 | Rebuild and verify recovered XC7Z020 CICC baseline；原始 XC7Z020 XPR、31 RTL/header、3 XCI、XDC/COE 恢复；活动文件引用闭合；Kintex 保留 | board/vivado_zynq7000_xc7z020_baseline；manifest 双哈希 | in_progress；未运行 Vivado/IP 再生成/综合/实现 |
| B03 | 原始 target xc7z020clg400-1、PLL 50→100 MHz、128 KiB BRAM 配置已知 | 原 XPR/XCI/XDC 与恢复审计 | blocked；target part 已确认，physical board model pending；revision/引脚适用性/PYNQ image 未核验 |
| B04 | CoreMark RV32/RV64、FreeRTOS 应用、RISC-V tests 源与构建输入共 465 文件恢复 | src/firmware/cicc1000023；原名还原脚本 | blocked；准确 kernel/bootloader 源不在所供 ZIP；未编译/加载 |
| V01 | 原始 RTL top elaboration、tb_bypass 7 项与 tb_regfile 15 项通过 | build/metadata/cicc1000023_recovery_verification.json | in_progress；ISA/Cache/AXI/中断/counter 完整回归待做 |
| 历史硬件输出 | ZIP 有 bitstream、综合/实现成功日志；100 MHz 下 WNS 0.056 ns；placed LUT 4806 / FF 3129 / BRAM 38.5 / DSP 4 | 精选 6 个报告/日志与 archive_inventory | historical_archive_evidence；有未设 IO delay，非本轮重建或实测 |
| RTL 比较 | 31 共有文件：14 字节同、17 仅换行差异；repo-only 两个 Ascon helper | docs/cicc1000023_rtl_diff.md | 没有选择哪个更新；当前 src/rtl 未改 |
| C02 | 既有 Ascon C/Python 保留 | ascon/ | in_progress；未移植或运行最终标准 KAT |
| C01/C03/C04 | 无锁定的最终标准 KAT 及板上 benchmark | 尚无相关结果 | todo；Ascon cycles/code size 均 not_measured |
| Ixx | Ascon RTL 仍只有 ror/load_bytes/store_bytes | src/rtl/ascon/ | I01-I08 todo |
| D01 / Yxx / Sxx | 当前/目标架构与待定接口已记录；PS/PYNQ/Skill 实现未开始 | docs/architecture.md、docs/interfaces.md | D01 in_progress，其余按任务表 |
| Pxx | 未开展 PUF/启动认证 | tasks/task_board.md | gated |

## 验证边界与当前阻塞

579 个恢复资产的 SHA-256 核验通过；两套 XPR/XDC、当前 RTL 与 Ascon 保持原字节。Kintex 经 git mv 归并，旧生成元数据两项已清理。文件名还原脚本成功在 ignored build/local 生成隔离工作副本；不执行原包中的安装或清理脚本。

没有运行 Vivado/Vitis、固件编译、完整 ISA、JasperGold、软件 KAT、板上测试或 PYNQ。两个模块仿真与历史 Vivado 报告分开记录。PATH 未发现相关构建工具不等于全盘无安装。

下一步：B02 重建真实 baseline；B03 核板；B04 取得准确 kernel/bootloader 来源、核验入口并适配旧测试层次；C01 锁定标准 reference/KAT。Git HEAD 缺资料用 not_in_current_repo；ZIP 已提供的资料用 available_in_archive / recovered_uncommitted，不再写成 not_available。

首次审计曾复现 top_pl_bram 缺三个 IP module 的 Icarus 报错；该历史结果保留在 repository_audit。如今 XCI 已恢复，但 XCI 不是 Icarus 可直接编译的 Verilog 模型，仍需 Vivado 生成对应产物。

foundation 收口的 579 资产分类：A source 485、B build/config input 85、C test/reference data 3、D historical evidence 6。最终 board 仅两个工程，未改 RTL、未跑 Ascon。提交准备与 Git 检查见 [收口检查](../docs/repository_foundation_closeout.md)。

## 2026-10-07 — C02 production C 认证失败输出收口

owner TBD；基线 `origin/feat/ascon-kat-validation` 的
`c34728558469f0d4e4068730801dea59e0ca2100`；分支
`fix/ascon-c-auth-failure`。本节不修改任务看板。

| 项 | 本轮真实结果 | 状态建议 |
|---|---|---|
| 原问题 | bad tag 返回 -1，但 mlen=17、buffer=原明文；原门禁 1 PASS/1 FAIL/exit 1 | 失败证据保留 |
| 扩展 raw 门禁修复前 | 15,039 PASS / 8,926 FAIL / exit 1；包括短输入保留 stale mlen | 失败证据保留 |
| production C 最小修复 | 仅 decrypt：失败清零已知候选区域并设 mlen=0；短输入仅设 mlen=0；完整 tag XOR/OR 比较保留 | host 子项关闭 |
| 修复后 raw 门禁 | 23,965 PASS / 0 FAIL / exit 0；直接读完整 buffer，检查两侧 canary | C03 软件失败输出子项 PASS |
| 四 backend host validation | 修改前后均 28,661 PASS / 0 FAIL / exit 0 | Final 固定 KAT 无回归 |
| harness/golden | 5 tests PASS / exit 0 | 错输出/假接受/hash 故障确实非零退出 |
| 加密不变 | 1,153 固定 AEAD 输入输出拼接 SHA256 修改前后一致 | encryption 无改动 |
| C01 | 锁定来源、标准、许可、KAT/hash 与软件证据已可用 | 可评审 done |
| C02 | host API 安全契约已收口；target build/port 与 B04 仍未验 | 保持 in_progress，不能 done |
| C03 | 软件验证全部 PASS；target/整体前置未验收 | 不自行 done |

实际命令、编译器/源文件哈希、前后 raw 示例、原始日志与限制见
[C API 与修复记录](../ascon/ascon_c/aead/readme.md) 和 `data/ascon/results/`。
锁定 reference、固定 expected、Python、生产 RTL/CPU/Vivado 均未修改。
目标固件、上板、cycles/PPA、buffer overlap/异常指针/超大长度与全面 timing proof
未验证或 not_measured。下一接收：C02 target/B04 → C03 target KAT → C04 real
mcycle，owner TBD；RTL integration/decrypt blocker 仍由 RTL owner 处理。


## 2026-10-20 — 100 MHz 时序工作台站点（仓库外）+ 两处证据性发现

owner TBD。用户要求：不做 RTL 优化（由用户自己动手），改为把 CPU 逐块拆解、给出当前实测标定、
把已做过的时序优化步骤连同判定放到一个可复核的网站上。站点落在仓库外
`../html/`（`C:/wenjian/game/FPGA2026/ours/html/`），**未修改 src/rtl、未改 board 工程/XDC、
未 commit**。被用户确认的口径：以 control（HEAD 3c6f134，+0.007）为“当前”，
14164 条路径 CSV 标注为 −0.136 探针快照（偏悲观 0.143 ns）。

- 新增（仓库外）：8 个静态页面 + `assets/{style.css,data_static.js,data_probe.js,app.js}`
  + `trace/`（定向程序、TB、轨迹 CSV/JSON）+ `probe/`（只读探针脚本与输出）+ `check_pages.js`。
- 新增实测（只读）：`probe/per_module_paths_detail.tcl` 打开最终 routed DCP
  （`bce_timing_control/.../top_pl_bram_postroute_physopt.dcp`），对 26 个模块与 15 个路径族
  各取最差一条，输出 slack / DATAPATH_DELAY / DATAPATH_LOGIC_DELAY / DATAPATH_NET_DELAY /
  LOGIC_LEVELS / 单元构成 → `probe/module_paths_detail.csv`。未 launch run、未改工程。
- 新增实测（仿真）：`trace/tb_trace.v` 在 soc_top @50 MHz 上跑 41 条定向指令，
  每拍采样 41 个信号（pc/有效位/stall/flush/两个 cache 状态机/多周期握手/isE）
  → `trace/trace.csv`（231 拍）。据此把逐拍流水做成可点选的 10 个场景。
- 站点数据交叉核对：模块级族条数与 `paths_lt_2p0.csv` 重算一致（id_ex 内部 315 / →dcache 289 /
  →if_id 165 / →icache 148 / pc→ise 647 / dcache→mmio 8858）。
- 发现 1（文档错误，已写入站点）：`docs/cpu_timing_architecture_plan.md` §5.0 表把
  “−0.643 / 649” 标成 B+E-v2；实测那是 `rtl_E2` 单独结果，B+E（rtl_patched）是
  −0.723 / TNS −93.442 / 502 端点。不影响“B/E 均回滚”的结论。
- 发现 2（功能/计数口径，未修）：多周期指令（mul/div）执行期间 `id_ex_inst_valid = 0`
  （trace cycle 61–63、64–97），原因是此前 icache miss 的 `flush[2]` 清零 `inst_valid`，
  而 `id_ex` 的 flush 分支不清 `pc_o/rs1_o/rs2_o`，随后 stall 分支把 0 保持。
  `cpi_cnt` 与 `probe_inst_valid` 依赖它 → 指令计数偏小、CPI 偏大，影响既有 cpb 数字口径。
  未改 RTL，仅记录；建议单独立项核（接收：RTL owner / TBD）。
- 验证：`node html/check_pages.js` 8 页脚本全部无异常；Chrome headless 渲染 8 页人工核对布局；
  轨迹与探针均在本机重跑通过（Vivado 2025.2 / Icarus 14.0 devel）。
- 未验证 / not_measured：板级 XDC（IO delay/PS7）后的时序；80 MHz 改频后的实现结果；
  上板 cycles；每类 stall 占比；p12 单独实测周期（现为按 p8 折算，站点已标注）。
- 下一接收：用户按站点 `next.html` 自选路线（A/D/C/F/R）；站点不改 RTL，只提供标定与判定依据。

## 2026-10-21 — 后端战役：控制锥复制 + 依赖驱动 floorplan + 疏松布局（夜间 33 臂）

owner TBD；起点网表 `acb_remap/top_pl_bram_opt.dcp`（HEAD `3c6f134` 生产策略 +0.007 的
post-opt 快照）。**未修改 `src/rtl`、`board/`、baseline XDC 与工程；未 commit**
（`git status` 仅新增 `build/backend_opt_20261021/`、`build/reports/backend_opt_20261021/`
与 `docs/backend_placement_campaign.md`）。用户要求：复制同义寄存器本地化控制锥、
按依赖强度摆模块、布局尽量疏松、从后端而非 RTL 找余量。

| 项 | 本轮真实结果 | 状态 |
|---|---|---|
| 实验装置 | `run_variant.tcl` + `run_wave.sh`（每臂独占目录）+ `floorplan.py` + `dep_analysis.py` + `summarize.py` + `fanout_compare.py` + `probe_*.tcl` | 可用，可复现 |
| 臂数 | 35（8 个波次，含 2 个重复对照臂） | 覆盖复制/floorplan/疏松/放置与布线 cost model |
| 最好一档 | `pl_ndh_crit200_ntr`：WNS **+0.138** / TNS 0 / 失败 0 / WHS **+0.017** / Slice LUT 11690 / Slice Reg 16042（生产参考 11752/16040）/ 0 布线错误 | 重复臂逐位相同 |
| 生产指令锚点 | `prod_place`（opt Explore/place Explore/phys_opt Explore/prout ExploreWithHoldFix）= **+0.016**，与既有 +0.007/+0.016 同级 | 说明本 harness 与生产可比 |
| 全局复制 | `rep128/256/512` = −0.074 / −0.188 / −0.295；`rep256_nofrn` 与 `ctl` **逐位相同**；`rep256_noeq` = −0.398 | 复制确实发生（9650/3989/1280/661/457 pin 网络全部跌破 256 pin），但**不推动时序墙** |
| 定向复制 | 只复制最差 N 条路径的 CE 锥（Slice Reg 仅 +9）：N=20/60/120/200 → +0.030/+0.068/−0.039/+0.074（加 NoTimingRelaxation 后 −0.154/+0.117/+0.138/+0.003） | 非单调，量级与一次布局重抽同阶 |
| floorplan | fp2 +0.007、fp3 +0.017、fpc −0.065、fp3_prod −0.061、fp3_ndh −0.228；pblock 确实被遵守（pb_cpu 仅 275/10404 单元被 phys_opt 溢出到区间外） | 生效但无稳定收益 |
| 疏松 | `place_design` 无 `-place_density`；pblock `PLACE_DENSITY` 在 2025.2 不存在（`fp3_loose` 因此失效，脚本已改 catch 保护）；`AltSpreadLogic_medium/low` = +0.002 / −0.027 | 器件 22% 占用本来就松，人为散开无益 |
| 时序墙分布 | `ctl` <0.2=179 / <0.3=319；`prod_place` 127/278；**冠军 7/44** | 唯一真实收益：接近临界端点数量下降 10 倍 |
| 最差路径构成 | `ctl` dp 9.979 / logic 2.882 / net 7.097 / lv 11 → 冠军 9.502 / 3.193 / 6.309 / lv 11 | 累计走线 −0.79 ns，逻辑 +0.31 ns |
| 未验证 / not_measured | 功能回归（`src/rtl` 未改，变换为 Vivado 等价实现变换，但未跑 KAT）；板级 XDC + PS7 在场后的时序；bitstream 与上板；80/90 MHz 改频后的实现 | 不宣称 |

结论：**纯后端手段无法把这道墙抬到 +1.0 ns**。35 个臂的 WNS 区间 −0.514 ~ +0.138，
最好一档已达 0 失败端点、0 布线错误，但只有周期的 1.4%；真正改善的是脆弱性
（<0.2 ns 端点 127→7）。要余量仍是降频（90 MHz 折算 ≈ +1.11 ns）或 RTL 深度削减。
完整表格、机制证据与复现命令见
[backend_placement_campaign.md](../docs/backend_placement_campaign.md)。
下一接收：决定是否把 `pl_ndh_crit200_ntr` 做成 baseline 工程的独立 impl 入口并跑全套回归，
或按 80/90 MHz 收口；owner TBD。


## 2026-10-21 — 布局布线可视化（真实 SITE 坐标 + 逐跳延迟）

owner TBD。用户要求：在站点里加一张能看出"当前布局布线是什么情况"的图，每个模块有对应的线，
并把每一条最坏路径画出来。站点仍在仓库外 `../html/`，**未改 src/rtl、未改工程/XDC、未 commit**。

- 新增只读探针 `html/probe/floorplan_probe.tcl`：打开 `bce_timing_control/.../top_pl_bram_postroute_physopt.dcp`，
  输出 ① 器件栅格（max_x=113 / max_y=149，BRAM 列 X0–X5、DSP 列 X0–X4）
  ② 22 个模块的 placed bbox + 质心 + 模块内 BRAM/DSP 数（`fp_modules.csv`）
  ③ 12 条最差路径 + 15 个路径族的 `full_clock_expanded` 报告（`fp_paths/*.rpt`）。
  新增 `parse_floorplan.py` 把报告里的 Location 列解析成 (x, y, 本跳 ns, 累计 ns) 的折线 → `assets/data_layout.js`。
- 新增页面 `html/layout.html`：楼层图（SVG）+ 单路径/模块分布/模块互联三种模式 + 跳数表。
- 实测发现（新）：
  1. dcache 的 8 个数据 BRAM 在 **RAMB18_X4Y0…X5Y5**（芯片最左 BRAM 列），而 dcache 逻辑在 X35–X106；
     最差路径 #1/#2/#3 的终点就是 `RAMB18_X5Y4`，最后一跳从 `SLICE_X98Y16` 横跨 93 列。
  2. `dcache.bus_addr_r → ascon_mmio MSG_BUF` 那族有一跳 **跨 90 格 / 3.09 ns**（Y22 → Y104）：
     MMIO 缓冲被放在芯片下半部，与数据通路相距 80+ 行。这条解释了 8858 条路径为何都在 7.7 ns 走线上。
  3. 最差 #1 的 11 跳全在 X64–X98 / Y4–Y20 的局部区域内绕（曼哈顿 166 格），
     说明"先在局部绕一圈、最后再横跨整块芯片"是本设计的典型形状。
- 修正一处探针自身缺陷：`LOC` 正则原先写成 `^[A-Z]+_X…`，会把 `RAMB18_X4Y2`/`DSP48_X1Y3` 全部漏掉，
  导致模块 bbox 不含 BRAM（dcache 被算成 X35..106 而不是 X4..106）。已改为 `[A-Z]+[0-9]*`。
- 验证：`node html/check_pages.js` 9 页全通过；Chrome headless 渲染 9 页人工核对；
  三种模式各截图核对（`preview_layout*.png`）。
- 未验证：路径折线是按 report_timing 的元素顺序连线，**不是布线资源的逐段走线**（Vivado 文本报告不含 PIP 级路径）；
  因此图中线段表示"逻辑单元之间的顺序与距离"，真实走线拓扑仍是 not_measured。


### 追加（同日）— 布局图支持图层开关与自动聚焦

用户要求：图不能只是"全部画出来"，要能取消一部分，让剩下的部分居中放大显示。已改为三栏：
左侧模块图层（22 个勾选框 + 只看 CPU / 只看 Ascon / 全关 预设）、中间楼层图（滚轮缩放、拖动平移、
点模块框压到该 bbox、「全屏看图」收起两侧栏）、右侧路径信息与逐跳表。
`fitView()` 按「可见模块 bbox ∪ 可见路径 bbox」计算 viewBox 并保持器件比例，所以取消图层后视图自动
缩放到剩余部分；路径图层支持多选叠加（非当前路径画虚线）。URL 参数 `?p=` / `?preset=` / `?hide=`
可复现任意视图。文件：`../html/layout.html`（未改 RTL/工程，未 commit）。

### 2026-10-21 补测 — WHS 侧 5 个 post-route 修复臂（全部空操作）

从冠军 `pl_ndh_crit200_ntr_routed.dcp` 起，只做布线后修复、不重布局（`run_holdfix.tcl`）：

| 臂 | 动作 | WNS | WHS | Δ |
|---|---|---|---|---|
| hf_explore | `-directive ExploreWithHoldFix` | +0.138 | +0.017 | 0.000 / 0.000 |
| hf_aggr | `-directive ExploreWithAggressiveHoldFix` | +0.138 | +0.017 | 0.000 / 0.000 |
| hf_aggr_both | 上 + `-aggressive_hold_fix` | +0.138 | +0.017 | 0.000 / 0.000 |
| hf_clock | `-clock_opt` | +0.138 | +0.017 | 0.000 / 0.000 |
| hf_clock_hold | `-clock_opt` + `-aggressive_hold_fix` | +0.138 | +0.017 | 0.000 / 0.000 |

结论：WHS 为正时 hold 修复指令无事可做（help 只对 "hold violators" 生效），LUT 数也不变。
hold 薄的结构原因是 Ascon 核内 0~1 级逻辑的相邻寄存器对（数据 0.30~0.44 ns，最差
`p12_inst/s_out_reg[315] → u_crypto_aead/s4_reg[59]`，靠 +0.271 ns 时钟偏斜撑到 +0.017）。
35 臂统计 `corr(WNS,WHS) = −0.516`，WHS ≥ +0.05 的 7 个臂 WNS 全部 ≤ −0.102（setup 违例），
官方生产也只有 +0.023/+0.031 → 建议把 hold 门限改为 "hold 失败端点 = 0 且 WHS > 0"。
证据：`build/reports/backend_opt_20261021/hf_*/`，说明见 `docs/backend_placement_campaign.md` §4.7。


### 追加（同日）— 新 run 的自动接入管线（等 campaign 结束后生效）

用户要求"等完成后接入数据"。已建成并**用同一网表自测过**（Δ 全为 ±0）：
`intake_run.sh <dcp> <tag>` = 只读探针（探针已参数化，可对任意 routed DCP 取模块 bbox + 27 条路径的逐跳 SITE）
→ `parse_floorplan.py --tag` → `assets/data_layout_<tag>.js` → `update_manifest.py`（从 campaign 的 `RESULT` 行取 WNS）。
`layout.html` 新增「对比基准」下拉：base 画灰虚线、新布局画彩线，右侧给出 slack/data/logic/route/hops/
曼哈顿/峰值单跳的 Δ 表；`experiments.html` 增加「后端 campaign（自动接入）」表。
并发保护：`intake_run.sh` 检测到 `vivado.exe` 在跑即拒绝执行（`--force` 才跳过）。
已挂后台等待器 `watch_campaign.sh 6`：等 `vivado.exe` 全部退出 + 90 s 冷却后，自动接入
`build/local/backend_opt_20261021/` 下新建的 checkpoint（日志 `html/probe/watcher.log`），最多 6 个。
当前 campaign 仍在跑（`vivado.exe` PID 40068，最新 checkpoint 11:16），故站点数字仍为 10-20 21:37 的基线。

### 2026-10-21 补测 2 — 用 pblock 把 hold 关键寄存器对拉开（2 臂）

`floorplan_hold.py`：把 `u_crypto_aead/p12_inst`（1628 cells / 646 FF）从
`u_ascon_mmio` 切出去单独一块，其余沿用冠军指令（place ExtraNetDelay_high、
crep 200、route NoTimingRelaxation）。

| 臂 | WNS | WHS | 失败端点 | 结论 |
|---|---|---|---|---|
| `hfp_split_near` | **−0.110** | **+0.032** | 73 | hold +0.015，setup −0.248 → 净亏 |
| `hfp_split`（远） | 未完成 | — | — | placer 卡在 Phase 4.1.1.2 超 30 min，已终止 |

切分后最差 hold 路径从 `p12_inst/s_out → s4`（0.381 ns）换成
`p8_inst/s_reg_reg[109]`（0.389 ns）、`nonce_r_reg[47]`（0.375 ns）等 ——
WHS 由一整群 0~1 级逻辑的寄存器对决定，不是单点。**结论：WHS 是结构量，
不建议再花时间；把 hold 门限改为"失败端点 = 0 且 WHS > 0"。**


### 追加（同日）— campaign 结束，接入两版并与基线逐跳对比

等 `vivado.exe` 全部退出后，等待器自动接入 `hfp_split_near`（12:07），随后按 `results.tsv` 的最优行补接
`pl_ndh_crit200_ntr_dup`（12:1x）。站点现有 3 个数据集（base + 2 个 run），`experiments.html` 增加 campaign 表
（58 次运行 / 36 个有 RESULT）。

- 实测对比（同类路径按「起点寄存器 + 终点模块/引脚」匹配）：
  - `pl_ndh_crit200_ntr_dup` WNS +0.138：原 #1（`w_reg_waddr_o_reg → dcache DIADI`）从 +0.007 → **+0.538**，
    逻辑级数 10→8、route 8.01→7.73、曼哈顿 166→141；`multiplier → dcache` +0.088→+0.934（级数 19→17）；
    `pc → ex_mem/CE` +0.101→+0.916。唯一倒退是 `dcache.bus_addr_r → mmio/CE` +0.525→+0.345，
    原因是**时钟偏斜**从 −0.024 恶化到 −0.252（数据路径本身 9.152→9.103 是变好的）。
  - `hfp_split_near` WNS −0.110：`sel_ex_mem_rs2 → dcache DIADI` 逻辑级数 16→7（logic 3.24→1.32），
    但 route 6.17→8.30、沙盘曼哈顿 174→53 → 净 −0.29。**曼哈顿↓ ≠ route↓**：pblock `pb_hf_rest`
    把 239 个 hop 收进一块，距离短了但绕线/拥塞变重。
- 修复两处会产出假数据的问题：① `worstN` 名次不可跨网表对比 → 改身份匹配；② 带 PBlock 列的
  `report_timing` 使旧列解析整行失败 → 改 token 解析并记录 pblock。
- 未验证：这些数字仍是芯片级 STA（无板级 XDC/PS7）；campaign 里 22 次 EXIT=1 未接入；pblock 的拥塞结论是
  由 route vs 曼哈顿的背离推出的，未用 `report_design_analysis` 的拥塞指标交叉验证。

### 2026-10-21 12:30 · 时序工作台：campaign 数据全站刷新

- 对象：`C:\wenjian\game\FPGA2026\ours\html`（仓库外，纯静态）；未改 `src/rtl`、`board/`、XDC，未 commit。
- 新跑只读探针：`probe/per_module_paths_detail.tcl -tclargs <dcp> pl_ndh_crit200_ntr_dup`（最优版 +0.138），得到 21 个模块的进来/出去最差路径；与 control 版逐模块配对（`assets/data_probe2.js`）。
- 15 个路径族按**起点寄存器 + 终点模块/引脚**身份匹配（不是 worst1/2 名次），生成 `assets/data_families_cmp.js`：**14 族变好，1 族变差**。
- 关键归因：
  - 变好：`id_ex internal` +0.285、`waddr→dcache` +0.531（级数 10→8）、`mult→dcache` +0.846、`pc→ex_mem` +0.815。
  - 变差：`dcache bus_addr_r → ascon_mmio/CE` +0.525→+0.345。数据路径 9.152→9.103（更快 0.049），**clock skew −0.024→−0.252**（DCD −1.675→−2.146）；同时 `u_crypto_aead` 进来 slack 也正好 −0.180 → 同一时钟路径改动带下两个端点。
  - `hfp_split_near`(−0.110)：`sel_ex_mem_rs2→dcache` 曼哈顿 174→53 格，route 6.17→8.30 ns → 距离↓不代表延迟↓（pblock 拥塞，未用 congestion 报告交叉验证）。
- campaign `results.tsv` 58 行重解析：**36 RESULT / 5 SMOKE(place-only，非失败) / 17 EXIT=1**（此前误报 22 次）。
- 17 次 EXIT=1 归因：**15 次为 Tcl 脚本错误**（`vspec` 的 `array set` 收到奇数元素，`run_variant.tcl:57`，启动 4 s 即退，5 份 backup 日志有相同 trace；另 10 次日志被后续成功 run 覆盖，只能判同类）；1 次 `fp3_loose` PLACE_DENSITY 非 pblock 属性（Netlist 29-177）；1 次 `hfp_split` 在 phys_opt Phase 4.1.1.2 被外部终止（无 ERROR/无 COMPLETE/无产物）。证据见 `html/probe/campaign_failures.md`。
- 站点：新增每页「数据版本条」+ `?v=20261021c` 缓存戳（解决"改动看不到"）；index/modules/paths/history/experiments/next 数据全部重算；`check_pages.js` 改为按页面真实 `<script src>` 加载（此前漏了 campaign.js/version.js，导致误报）。
- 验证：`node check_pages.js` → `ALL PAGES OK`（9 页）；截图核对 index/modules/paths/experiments/next。
- 未做：campaign 最优版的 WHS 未进 `results.tsv`（记 `not_measured`）；拥塞交叉验证未做；`src/rtl` 未动（用户自己改）。

### 2026-10-21 13:06 — 冠军网表出 bitstream（xc7z020clg400-1）

- `build/local/backend_opt_20261021/pl_ndh_crit200_ntr/pl_ndh_crit200_ntr.bit`
  （4,045,687 B，sha256 `6cff4f2f7443e68c38549ed8db2b8aed13259ba60c2d1b5adcff66c8614e4baa`），
  `.bin` 同时产出；Bitgen 自带 DRC 仅 warning，无 error。
- 出 bit 前复测 WNS +0.138 / WHS +0.017；引脚沿用 baseline `const.xdc`
  （clk=U18 假设 50 MHz、reset=N16、uart T19/J15、led H15/L15、button L14/K16）。
- **未验证**：板上任何现象（未烧录）；板型/时钟引脚未核实（`xc7z020` 是器件不是板型）；
  IO 无 delay 约束；BRAM 内是 baseline 的 `freertos_demo.coe`（8333 字），**不是 Ascon 固件**。
- 下一步（T0.2/T0.3）：`ascon_ise.hex` 32768 行 = 板级 BRAM 深度 32768 字（32×ramloop，
  32-bit 宽），可 1:1 转 COE → 换 `blk_mem_gen_0` → 重新 synth+impl → 新网表重测时序
  （+0.138 不保留）→ 再出 bit；另需板级自检固件与串口回归框架。

### 2026-10-24 16:40 · 布局布线双页 + 复制寄存器 + 时钟偏斜归因（站点）

- 起因：用户指出「布局图里看不到复制寄存器」。核查确认：`layout.html` 的 27 条路径全部来自 base run，ndh 只在对比模式里叠色；而**复制寄存器从来没有被画过**。
- 新页 `html/layout_ndh.html`：主图 = `pl_ndh_crit200_ntr_dup`，默认叠加 base 灰虚线；与 `layout.html` 双向跳转（导航栏「布局(最优版)」+ 页内按钮）。
- 新探针 `probe/replica_probe.tcl`（只读 DCP）：导出 replica 单元的 `REF_NAME/LOC/CLOCK_REGION` 与原单元坐标。结果：**base 5 个副本 / ndh 52 个副本**（ndh 的副本集中在 `*_BUF[*][31]_i_1` 这类使能译码 LUT，每个复制 2 份，覆盖 4 个 clock region）。
- base 的 5 个副本里包含 `clkout1_buf_replica` —— 即 **clk_out1 上串了两个 BUFG**（`clkout1_buf_replica → clkout1_buf`）；ndh 只剩一级。
- 时钟偏斜归因（回答用户提问，数据来自 `probe/fp_paths*/dcache_to_mmio.rpt` 的 Clock Path 段）：
  | 项 | base | ndh |
  |---|---|---|
  | BUFG(clk_out1) | 2 | 1 |
  | dcache `bus_addr_r` FF | SLICE_X81Y20 · X1Y0 | SLICE_X65Y21 · X1Y0 |
  | MMIO `MSG_BUF`（2048 FF） | SLICE_X45Y114 · **X0Y2** | SLICE_X36Y85 · **X0Y1** |
  | 全局时钟 net 到 dcache / MMIO | 1.723 / 1.699 | 1.718 / 1.466 |
  | SCD / DCD / CPR | −2.156 / −1.675 / −0.504 | −2.423 / −2.146 / −0.528 |
  | **skew** | **−0.024** | **−0.252** |
  | data path | 9.152 | 9.103 |
  → 结论：唯一倒退不是数据路径变差（快 0.049），而是 **MMIO 那 2048 个 FF 从 clock region X0Y2 搬到 X0Y1**，捕获时钟提前 0.233 ns，skew 由 −0.024 变 −0.252。同一搬动也解释了 `u_crypto_aead` 的 −0.180。
- 全站 16 条路径的 skew 分布：base −0.225…+0.052，ndh −0.252…+0.054 —— **离散步长几乎不变（0.28 vs 0.31 ns）**，变的是「哪条路径抽到下签」。所以设计的时钟树本来就带 ~0.25 ns 的落地差，WNS 只有 0.1 ns 余量时等于听天由命。
- 站点修正：Δ 列改为「本页 − 对比」；彩线恒为本页网表；路径列表标题与 Δ 表头改为动态 tag；`next.html` 的 ndh WHS 由 `not_measured` 更正为 **+0.017**（比基线 +0.023 更差）。
- 验证：`node check_pages.js` → 10 页 `ALL PAGES OK`；截图核对 layout / layout_ndh（含 ?preset=ascon）。
- 未做：`mult_to_dcache` 仍无直接探针值；拥塞交叉验证未做；RTL 未动。


### 2026-10-24 17:25 · next.html 路线实测：F（MMIO 写译码寄存化）+ R（80 MHz）

- 起因：用户要求按 `html/next.html` 的建议顺序（先 R 后 F）真跑一遍看效果。基线 `3c6f134`，
  `src/rtl/dcache.v`/`ascon_ise.v` sha256 与 2026-10-20 control 记录一致；`src/rtl`、`board/`、
  XDC 全部未改，变体都在 `build/local/tests_20261024/` 副本里。工具 Vivado 2025.2，
  part `xc7z020clg400-1`，top `top_pl_bram`。
- **F（补丁 `build/patches/timing_F_mmio_wdecode.patch`，只改 `ascon_mmio.v` +35 行，把写请求打一拍）**：
  - 100 MHz，ExploreWithRemap：WNS **+0.007 → −0.072**（TNS −1.289、**35 失败端点**），WHS +0.030，LUT +1.8%；
  - 100 MHz，ExplorePostRoutePhysOpt：WNS **+0.005 / 0 失败端点 / WHS +0.051**（对照第二策略 +0.001/2 端点）；
  - 目标族 `dcache/bus_addr_r → ascon_mmio`：**8858 → 60 条**（worst +0.525 → **+1.233**），
    MMIO 终点 <1.0 ns **1667 → 701**，全设计 slack<2.0 ns **14161 → 10245**；
  - 新墙 = A 族 `id_ex_u/sel_ex_mem_rs1_o_reg → u_dcache/valid_way*/D`（11 级 / logic 3.004 ns），
    与 next.html 预测一致 → **F 是清场，不是提余量；必须配 A**。
  - 仿真 6 场景（`build/local/tests_20261024/check_F.sh`）：7 项硬件 KAT 全 PASS、crypto latency 99 不变、
    软件 4 workload cycles 完全相同；**硬件 MMIO 全卸载 670 → 675 拍（+5）**，
    按 next.html 给 F 的"拍数不许变"门禁**不合格**。
- **R（80 MHz）关键纠正**：同一份未改 RTL，把核心约束改 12.5 ns **重跑综合+实现**只有
  **WNS +0.483**（0 失败端点、WHS +0.018）；原因是 P&R 按松约束松手——最差路径 route 9.167 ns
  （100 MHz 网表同类 ~7.6 ns），物理质量损失约 1.9 ns。站点"80 MHz +2.340 / 折算 +2.483"
  只对**已按 10 ns 布线**的网表成立。→ 正确做法：实现仍按 10 ns 过度约束，只改 MMCM 输出；
  验收用 post-route `reset_timing` + 12.5 ns 重算（`build/probe_freq_headroom.tcl`）。
  F 在 12.5 ns 下为 +0.456（比 control 的 +0.483 低 0.027，噪声带内）。
- WHS 在两种频率下都 <+0.05 门禁（+0.018~+0.051，只有 F+pr @100 MHz 的 +0.051 刚过）。
- 证据：`docs/timing_route_tests_20261024.md`、`build/reports/tests_20261024/{f_100,f_100_pr,ctl_80,f_80}/`、
  `build/local/tests_20261024/{paths_ctl.csv,paths_f100.csv,sim/*.log}`。
- 未做：C（store buffer）、A、D；板级 XDC/PS7 在场时序；MMCM 80 MHz 重生成网表 A/B；拥塞交叉验证。


### 2026-10-24 20:45 · 第二波：F+A（A 已在 RTL 里）+ F×后端配方

- 用户选定"F+A 合并测"。核实：**路线 A 描述改动已在 RTL 里**——旁路选择在 ID 段算
  （`cpu_core.v:373-386`，注释"在 ID 阶段提前计算旁路选择信号"）、ID/EX 边界寄存
  （`id_ex.v:183-186`）、EX 只用寄存位做 3 输入 mux（`bypass.v:25-40`）。
  → **F+A = F**，本波不新增 RTL 改动。
- F 之后真正的墙：`sel_*_o` 起点 1072 条 slack<2.0 路径，其中**只有 192 条压时序**
  （`dcache/valid_way0|1_reg` D 64+64 worst −0.072、`lru_reg` D 64 worst −0.063）；
  其余是 MMIO 缓冲区（worst +1.44~+1.87）。这 192 条来自 `dcache.v:471-505`
  「store 命中清另一路 / load miss 清 victim / hit 更新 LRU」必须同拍做 tag 比较，
  与 store 同拍写 BRAM 同源 → **只有 C（store buffer）或 tag 读打一拍能摘，A 摘不掉**。
- F + campaign 冠军配方（起点 F 的 post-opt dcp，脚本 `run_backend_F.tcl`）：
  - `F_pl_ndh_crit200_ntr`：WNS **−0.226** / TNS −9.028 / 102 端点 / WHS +0.015；
  - `F_pl_ndh_crit200_prod`：WNS **−0.225** / TNS −21.172 / 228 端点；
  - 对照：同配方打在未改 RTL 上是 +0.138。→ **campaign 收益不能迁移到 F**；
    可查原因：F 网表上 `crit_ce_nets` 只 13 条（最差 200 端点里 CE 网很少），
    而 F 的墙在 D 端，CE 复制打不到。
- 定向扇出复制臂（`run_selrep.tcl`，4 条 `sel_*_o` fo=172/141/172/140 + 309 条 forward 位网，
  MAX_FANOUT=8 + EQREG NO）与不做复制的 placeonly 臂**逐位相同**（−0.175 / 81 端点 / LUT 13799）；
  `probe_mf.tcl` 确认 `MAX_FANOUT=8` 写进去了但扇出仍 172、**没生成副本**——
  post-opt checkpoint 流程里 `MAX_FANOUT` 不触发复制，要复制得走
  `phys_opt_design -force_replication_on_nets`。**该臂是空实验，不作结论**。
- 顺手清理：这两臂因脚本 root 少了一层，把 `build/build/` 建进了仓库；报告已移到
  `build/reports/tests_20261024/F_pl_ndh_crit200_*`，DCP 移到 `build/local/tests_20261024/backend/`，
  仓库内无残留（`git status` 只剩新增 docs/与既有 untracked）。
- 净结论：F 不值得单独上（100 MHz 与 control 同级、80 MHz +0.456 vs +0.483、还要 +5 拍 MMIO）；
  F 的价值是暴露 C 要摘的那一族。要 100 MHz 余量只能做 C 或 tag 打拍；要立刻可交付
  用「control RTL + 10 ns 过度约束 + MMCM 80 MHz」。
- 证据：`docs/timing_route_tests_20261024.md` §7。


### 2026-10-24 21:25 · 路线 C（dcache store buffer）实测通过，0 周期

- 补丁 `build/patches/timing_C_dcache_store_buffer.patch`（只改 `src/rtl/dcache.v`，`git apply -p1` 干净）：
  ① store 当拍只进 1 项 buffer，下一拍提交；`data_way0/1` 改成真正的 SDP（Port A 只读，
  Port B 由 fill 与 buffer 提公共用，fill 优先）② valid/LRU 更新寄存一拍（`upd_*` 记录）
  ③ store→load 定向转发（`sb_valid && sb_addr == rd_addr` 按字节掩码覆盖）。
- **实现结果（Vivado 2025.2，xc7z020clg400-1，Performance_ExploreWithRemap，10 ns）**：
  | 变体 | WNS | TNS | 失败端点 | WHS | LUT | FF | BRAM |
  |---|---|---|---|---|---|---|---|
  | control（10-20 记录） | +0.007 | 0 | 0 | +0.023 | 11509 | 16040 | 38.5 |
  | **c_100（C）** | **+0.057** | 0 | **0** | +0.019 | 11476 | 16146 | **34.5** |
  | fc_100（F+C） | +0.005 | 0 | 0 | +0.013 | 11784 | 16189 | 34.5 |
  → C 是第一个既把目标族打穿、又在 100 MHz 上正收益的 RTL 改动；**F+C 不如 C 单独**（F 的 +202 LUT 纯负担）。
- **等价性两道**：① 全 SoC 6 场景（`check_C.sh`）KAT 全 PASS，cycles 与 control 完全相同
  （ise/ise_stall/ise_reset 2496、hw full MMIO **670** 与 latency 99 不变、sw 17353/21515/17847/22094 不变）；
  ② 新增 dcache 逐拍差分激励 `tb_dcache_trace.v`（伪随机 + 定向 store→load / store→store→load 同地址），
  4 个种子逐字节相同（含末尾存储器校验和）。
- **路径族证据**（`paths_c100.csv`）：`dcache/valid_way*|lru` 终点 192（control）→224（F）→**12（C）**，
  worst −0.072 → **+1.752**；`->u_dcache` 489→343（worst +0.249）；起点 `sel_*` 1218→505。
  C 之后最差单条变成 `pc_reg[5] → u_ex_mem/ex_rd_data_o_reg[0]/CE`（+0.057，9 级 logic 2.0 route 7.59），
  第二大族 `pc_reg[5] → u_ascon_ise` 649 条 worst +0.224 → **下一刀是 D（取指/stall 环），A 仍无事可做**。
- 未验证：板级；WHS +0.019 仍 <+0.05 门禁；C+campaign 冠军配方的叠加测试（21:07 启动，phy_opt 阶段长时间无输出，
  报告时未出结果 → not_measured）。
- 证据：`docs/timing_route_tests_20261024.md` §8、`build/reports/tests_20261024/{c_100,fc_100}/`、
  `build/local/tests_20261024/{rtl_C,rtl_FC,tb_dcache_trace.v,diff/}`。


### 2026-10-24 22:05 · 路线 C 落地到 src/rtl + 修掉队友 include 导致的 elaboration 失败

- `src/rtl/dcache.v` 应用 `build/patches/timing_C_dcache_store_buffer.patch`（1 项 store buffer +
  valid/LRU 更新寄存一拍 + store→load 定向转发）。落地后 sha256
  `79af461cf53545e79c294814e7f4869c341dbb745527885c0ee1755c1b5c1113`，与 `c_100` 实测那版**逐位相同**
  → WNS +0.057 / TNS 0 / 0 失败端点 / WHS +0.019 / LUT 11476 / FF 16146 / BRAM 34.5 这组数字对入库代码直接成立。
- 撤掉 `fb852b5` 在 `ascon/{ascon_mmio,ascon_ise,ascon_aead_core}.v` 顶部加的 `` `include ``：
  这三个文件无 include guard（同目录 `crypto_aead.v`/`ascon_permutation.v`/`ascon_round.v`/`ascon_word.v`
  都有），而它们同时作为独立源文件编译 → `'ascon_aead_core' has already been declared`，
  整库 elaboration 失败、回归跑不起来。撤掉后全 RTL elaboration 通过。
- 落地后回归：`build/local/tests_20261024/check_final.sh`（control = HEAD 的 dcache.v + 当前其余源
  vs 当前 `src/rtl`）6 场景，KAT 与 cycles 需逐条相同。
- 同步：main 上先提交了实测报告/补丁/报告归档（`431695b`），与 origin/main 的 `fb852b5` 做增量合并
  （`38e96fb`），已验证 5 个补丁合并后仍 `git apply --check` 干净。
- 未验证：板级 STA；C 之后 100 MHz 仍只有 +0.057 ns 芯片级余量（自定门禁 +1.0 未达），
  WHS +0.019 < +0.05 门禁。


### 2026-10-24 22:45 · 路线 D（中断可接受判决拆拍）实测 +0.087 ns 并落地

- 目标路径（C 之后整机最差 +0.057，9 级 / logic 2.0 / route 7.59）：
  `pc_reg → u_icache tag RAM → hit_way0 → icache_stall → csr_file/inter_req → flush[1] → u_ex_mem/CE`。
  根因在 `cpu_core.v` 的 `inter_accept_ready` 把 pc 衍生的 `!icache_stall` 和当拍快条件放同一个与门。
- 改法（补丁 `build/patches/timing_D_interrupt_guard_register.patch`，只改 `cpu_core.v`）：
  `inter_slow_ok = id_ex_inst_valid && !icache_stall` 只驱动一个触发器 `inter_slow_ok_q`，
  `inter_accept_ready` 当拍再与 `inter_slow_ok_q` + 全部快项（id_ex_inst_valid /
  dcache_stall / dmem_axi_stall_req / ex_stall_req / fence_i_stall）相与。`csr_file` 的一次脉冲语义未改。
- 实测（ExploreWithRemap / 10 ns）：WNS **+0.057 → +0.087**、TNS 0、0 失败端点、WHS +0.021、
  LUT 11483（+7）、FF 16156（+10）。
- **机制证据**（`paths_c100.csv` vs `paths_d100.csv`）：起点含 `pc` 的路径 **1389 → 1 条**
  （worst +0.057 → **+1.491**）；终点 `u_ascon_ise` +0.224 → +0.794；终点 `ex_rd_data_o_reg` +0.057 → +0.648。
- **D 之后新墙不再是 CPU**：`u_crypto_aead/FSM_sequential_state_reg[3] → u_crypto_aead/p12_in_reg[215]/D`
  （+0.087，**1 级逻辑**、route 9.290 = 94%）——Ascon 核心 p12_in 状态搬运的物理跨度问题。
- 等价性：全 SoC 6 场景（control = C 落地后 src/rtl，patched = C+D）KAT 全 PASS，
  cycles 逐条不变（2496 ×3、hw 99/670、sw 17353/21515/17847/22094）。
- **风险**：全部固件/单元/ISA TB 都没开中断（无 mtvec/mret/mie），所以本改动在功能上等价空操作；
  一旦启用中断必须先补定向 TB 验证"晚一拍接受"不会让 trap_pc 指向气泡。
- 落地：`src/rtl/cpu_core.v` 已应用补丁，与 `d_100` 实测所用 RTL 逐位相同。
- 当前 100 MHz 芯片级余量：**+0.087 ns**（基线 +0.007 → C +0.057 → C+D +0.087），WHS +0.021。
