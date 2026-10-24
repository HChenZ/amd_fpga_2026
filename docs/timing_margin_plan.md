# 100 MHz 时序余量：根因、实验与提余量路线

2026-10-20；owner TBD。基线 commit `3c6f134`（工作区 clean）。证据：
`build/reports/timing_acb_20261018/{postroute,remap}/`（当前生产策略）、
`build/reports/margin_20261020/*/`（本轮 4 个 P&R 变体）、
`build/local/margin_20261020/wall_stdout.txt`（时序墙分布，探测自 `acb_remap_routed.dcp`）。
本文不改 RTL、不改 baseline XDC。

## 1. 当前实测状态

| 项 | ExplorePostRoutePhysOpt | ExploreWithRemap（生产） |
|---|---|---|
| WNS (ns) | +0.001 | +0.007 |
| TNS (ns) / 失败端点 | 0.000 / 0 | 0.000 / 0 |
| WHS (ns) | +0.031 | +0.023 |
| LUT / FF / BRAM / DSP | 11752 (22.09%) / 16040 (15.08%) / 38.5 / 4 | 同（同 netlist） |
| 时钟 | `clk` 50 MHz @U18 → `clk_wiz_0/clk_out1` 100 MHz（10 ns），抖动 0.094 ns | 同 |
| IO delay 约束 | **无**（仅 `reset_btn` false_path） | 同 |
| PS7 | **无**（top 端口只有 clk/reset/uart/button/led） | 同 |

Vivado 2025.2，`xc7z020clg400-1`，top `top_pl_bram`，speed file -1。

## 2. 为什么 +1~7 ps 不能算“有余量”

1. 占周期 0.01%~0.07%，等于 0；同一 RTL 换布局实测摆动 −0.05~−0.128 ns（V08/V09），
   比现存余量大一个数量级。
2. 这一版**没有任何板级约束**：没有 IO delay、没有 PS7 硬块、时钟来自 MMCM 而非板上
   真实时钟源。上板必然重排重约束，这个数字不会保留。
3. 合理目标应写成：**在“板级 XDC + PS7 在场”的网表上 WNS ≥ +1.0 ns**（Fmax ≥ 111 MHz）。
   下面第 3 节说明为什么这条目标在不改架构的前提下达不到。

## 3. 根因：不是一条坏路径，是一道整体 Fmax 墙

### 3.1 关键路径不是一个家族

当前 +0.007 ns 的产生，是因为**大量路径同时挤在 9.5~10.0 ns**，谁的布局稍差谁就是
报出来的“WNS”。本轮 4 个变体各自的最差路径来源不同：

| 变体 | 该变体最差路径 | slack |
|---|---|---|
| nopb_et | `pc_reg[5]` → `id_ex_u/sel_ex_mem_rs1_o_reg/D`（旁路选择网） | +0.008 |
| pb2_et / pb2_alt | `id_ex_u/sel_ex_mem_rs1_o_reg/C` → `dcache/valid_way0_reg[51]/D` | +0.001 |
| pb3_epp | `ex_mem/ex_rd_data_o_reg[0]` → `dcache/lru_reg[50]/D` | +0.020 |
| 生产 remap（原报） | `pc_reg[4]` → `icache tag RAM → csr_file 控制锥 → ascon_ise/state_reg CE` | +0.007 |

原始 +0.007 那条路径的构成（供参考）：Data 9.505 ns，**logic 1.963 ns（20.7%）/
route 7.542 ns（79.3%）**，10 级逻辑，物理跨度 `SLICE_X83Y34` → `X57Y53`。
链尾挂的是 320 位 ISE 状态寄存器的 CE —— `cancel`（flush/trap 清零）被并进了 CE 锥，
把 icache→csr→flush 的全局控制链直接拽到 ISE 数据通路上（`src/rtl/ascon/ascon_ise.v:80`）。

### 3.2 时序墙分布（量化）

在 `acb_remap_routed.dcp`（含 post-route phys_opt 前）实测端点数量：

| slack 阈值 | 端点总数 |
|---|---|
| < 0.0 ns | 4 |
| < 0.05 ns | 20 |
| < 0.1 ns | 55 |
| < 0.2 ns | 152 |
| < 0.3 ns | 334 |
| < 0.5 ns | 1058 |
| < 1.0 ns | 3731 |
| < 2.0 ns | 14164 |

含义：**要拿到 +1.0 ns 余量，等于把 3731 条路径整体提前 1 ns（周期的 10%）**；
砍掉单条路径只是让它从榜单上消失，后面还有 334 条 <0.3 ns、1058 条 <0.5 ns 的排队。
最差路径终点集中在三类：`id_ex_u/sel_*_o` 旁路选择寄存器 → `if_id` 的 `CE`/`if_pc_o`、
→ `dcache` 的 `DIADI/WEA/lru/valid` 写口、以及 `pc → icache tag → 控制锥`。

### 3.3 布局是“症状”，不是“解”

实测布局（`acb_remap_routed.dcp`）：

| 模块 | cells | X span | Y span |
|---|---|---|---|
| `u_cpu_core` | 10420 | 32..106（75 列） | 0..113（114 行） |
| `u_dcache` | 1565 | 35..106（72） | 3..113（111） |
| `u_ex_stage`(含 ISE) | 3909 | 34..99（66） | 4..32（29） |
| `u_icache` | 641 | 32..90（59） | 0..18（19） |

确实很散（全设计只用 22% LUT 却拉成 7.5 ns 走线），但**把核压进 pblock 并没有变好**：
见 §4.1，`X50Y0:X113Y99` 紧约束后 WNS 反而只有 +0.001，说明这些路径的长度主要来自
“id_ex ↔ if_id ↔ dcache 之间的真实功能连接”，不是可以靠挪位置消掉的。

## 4. 提余量路线与实测结果

### 4.1 L0 只动 P&R（已做完，空间关闭）

同一 netlist（`acb_remap/top_pl_bram_opt.dcp`），只变 floorplan 与 directive，
4 个变体并行（脚本 `build/sweep_margin_phys.tcl`，结果 `build/reports/margin_20261020/`）：

| 变体 | pblock | place | 路由后 phys_opt | WNS | TNS | 失败 | WHS |
|---|---|---|---|---|---|---|---|
| `nopb_et` | 无 | ExtraTimingOpt | AggressiveExplore | **+0.008** | 0 | 0 | +0.019 |
| `pb3_epp` | X50Y0:X113Y149 | ExtraPostPlacementOpt | AggressiveExplore | **+0.020** | 0 | 0 | +0.051 |
| `pb2_et` | X50Y0:X113Y99 | ExtraTimingOpt | AggressiveExplore | +0.001 | 0 | 0 | +0.024 |
| `pb2_alt` | X50Y0:X113Y99 | ExtraTimingOpt | AlternateFlowWithRetiming | +0.001 | 0 | 0 | +0.024 |
| 生产 remap（参考） | 无 | Explore | Explore/Remap | +0.007 | 0 | 0 | +0.023 |

**结论**：pblock 与 directive 组合只能把 WNS 在 +0.001 ~ +0.020 ns 之间挪动。
加上此前 33 个内置策略扫掠（最优 −0.177 → 修 RTL 后才到 +0.007），
**P&R 侧的余量空间已关闭，不再投入**。最佳变体 `pb3_epp` 的 +0.020 ns 不构成可用余量。

### 4.2 L1 单点 RTL 断链（只能防翻负，不能加余量）

仍值得做，因为它把“最容易翻负的那条”从榜单上拿掉，降低回归风险：

1. `src/rtl/ascon/ascon_ise.v:80` —— `cancel` 并进了 320 位 state 的 CE 锥。
   加 `state_valid`（cancel 当拍清），`rd_data` 改为 `state_valid ? state[..] : 0`，
   物理清零延后一拍；CE 只剩 `wr_en`/`p_done` 两个本地条件。
   **安全语义要复核**：`ise --reset` / `--security` 必须证明清零期间读不出旧状态。
2. `src/rtl/icache.v:163` —— `cpu_stall_o = !(hit && hit_r)` 里的 `hit` 是分布式 RAM
   异步读 + 比较器的组合输出。改成寄存器版（`hit_r`/`hit_d`）前必须先核对 `if_stage`
   的 miss/flush 时序能否容忍一拍，否则引入取指错误。
3. `csr_file`：`icache_stall → inter_req → flush → jump_trap_out` 三级串行 LUT，
   把“flush/trap 触发 ISE cancel”单独提前一拍算成 `cancel_r`。

预期收益：让原报出的 +0.007 路径有 +0.5~1.5 ns 的余量，但**整体 WNS 仍由其它路径
（`id_ex sel_*_o → if_id CE` / `→ dcache 写口`）决定**，所以 WNS 不会明显上升。

### 4.3 L2 架构流水化（唯一能真正加余量的 RTL 路线）

完整方案、每模块最差 slack、收益模型与实施顺序见
**[cpu_timing_architecture_plan.md](cpu_timing_architecture_plan.md)**。要点：

- 砍 dcache **没有时序收益**（最差路径在 `id_ex_u` 内部，去掉 dcache 后剩余 WNS 仍 −0.140），
  性能还要掉，不做；
- 墙按模块分：`id_ex_u` 647 条 <0.5 ns（最差 −0.140）、`u_if_stage` 358、`u_dcache` 308、
  `u_icache` 124、`u_ex_stage`/`u_ascon_ise` 各 206/198、`u_ascon_mmio` 1670 条 <1.0 ns；
- 没有任何单点改动能抬到正余量；+1.0 ns 需要 B+C+E（0 周期）→ A+D（旁路网）→ F（mmio）
  三步协同，约 2.5 天 + 全套回归，**与 10-27 冻结冲突**。


### 4.4 R3 降频（零 RTL 风险，立刻可用）★推荐

同 netlist、同布局，只改 MMCM 输出频率，intra-clock 路径的 slack 精确平移
`ΔT = T_new − T_old`。实测方式：打开 `acb_remap_routed.dcp`（post-route phys_opt 前，
该快照 WNS = −0.136），`reset_timing` 后只改输入时钟周期重算，不重做布局布线
（`build/probe_freq_headroom.tcl`）：

| 目标频率 | 核心周期 | 实测 WNS（同一已布线网表） | 折算到最终 +0.007 网表 | 相对余量 |
|---|---|---|---|---|
| 100 MHz（现状） | 10.0 ns | −0.136 | +0.007 | 0.07% |
| 90 MHz | 11.111 ns | **+0.965** | ≈ +1.11 | 11% |
| 80 MHz | 12.5 ns | **+2.340** | ≈ +2.48 | 20% |
| 75 MHz | 13.333 ns | **+3.165** | ≈ +3.31 | 25% |

（WHS 在各频率下均为 +0.023，保持余量。改频只需把 `clk_wiz_0` 输出改成目标频率，
但那是 baseline IP 变更 → 独立入口 + 重新生成 IP + 全套回归。）
**关键点：cycles、cpb、加速比与频率无关**，降频只影响绝对耗时，不影响比赛材料里的
性能对比数字；反过来“100 MHz 只余 7 ps”在评审眼里不如“80 MHz 稳定运行、余量 2.3 ns”。

## 5. 建议（结论先行）

1. **上板频率定为 80 MHz**（或至少 90 MHz），把 100 MHz +0.007 ns 作为
   “芯片级已收敛、余量不足”的存档证据，不再花时间追 100 MHz 的余量。
   `clk_wiz_0` 输出改频属于 baseline IP 变更 → 独立入口 + 重新生成 IP + 全回归。
2. 若必须保 100 MHz 演示：先做 §4.2 的 L1 断链（防翻负，0.5 天），再评估 §4.3 是否
   在冻结前做得完；做不完就按 1 执行。
3. 上板后无论选哪个频率，**都必须重新 STA**（PS7 + 板级 IO + 时钟源全变），
   现有 +0.007 不能作为板上结论。

## 6. 复现

```bash
# P&R 变体（隔离目录，不动 baseline 工程/RTL/XDC）
for v in pb2_et pb3_epp nopb_et pb2_alt; do
  /c/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch \
    -source build/sweep_margin_phys.tcl -notrace -tclargs $v \
    -log build/local/margin_20261020/$v.log &
done; wait
# 时序墙分布
/c/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch -source build/probe_timing_wall.tcl -notrace
# 布局 bbox
/c/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch -source build/probe_geometry2.tcl -notrace
# 降频后的余量（同一已布线网表只改时钟周期，不重做布局布线）
/c/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch -source build/probe_freq_headroom.tcl -notrace
```

注：首轮 4 变体的脚本在用 `-pulse_width` 取 WPWS 时抛错（该选项在 2025.2 的
`get_timing_paths` 不存在），发生在写 `result.txt` 之前；`route_*.rpt` 均已正常生成，
上表数字取自 `route_timing.rpt`。脚本已修正，重跑不会再触发。

## 7. 不要做的事

- 不用 `set_multicycle_path`、降低 `clock uncertainty`、把同步路径设 `false_path`
  来把 WNS 刷成正数；真正异步的只有 UART、按键、LED、复位。
- 不在补 IO delay 之前宣称“板上时序达标”。
- 不把 +0.007 ns 写成“100 MHz 收敛、有余量”。

## 8. 接受标准

任何替换当前生产策略的变体必须同时满足：WNS ≥ +1.0 ns、TNS = 0、失败端点 = 0、
WHS ≥ +0.05 ns、`report_route_status` 0 routing error、资源劣化 <5%，并且跑完
`docs/freeze_checkpoint_20261018.md` §2 全套（8 项整机 + 5 单元 + ISA + 双策略复测）。
