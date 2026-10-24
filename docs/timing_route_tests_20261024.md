# next.html 路线实测：F（MMIO 写译码寄存化）与 R（80 MHz）

2026-10-24；owner TBD。基线 `3c6f134`（`src/rtl/dcache.v`、`ascon_ise.v` 的 sha256 与
2026-10-20 control run 记录一致，见 `build/reports/tests_20261024/*/build_context.txt`）。
工具 Vivado 2025.2，part `xc7z020clg400-1`，top `top_pl_bram`，策略
`Performance_ExploreWithRemap`（第二策略另跑，见 §4）。**实验期间 `src/rtl`、`board/`、XDC 均未改动**，
所有变体都是 `build/local/tests_20261024/` 下的副本；实验结束后**只有路线 C 落地到
`src/rtl/dcache.v`**（见 §8.6，sha256 与 `c_100` 实测网表逐位一致），其余补丁仍未应用。

本文回答一件事：按 `html/next.html` 的建议顺序（先 R 后 F）真跑一遍，效果到底是多少。

---

## 1. 结论先行（六条，全部实测）

1. **F 按设计生效，但不给 100 MHz 加余量。** 目标族 `dcache/bus_addr_r → ascon_mmio`
   从 **8858 条降到 60 条**（worst +0.525 → **+1.233**），MMIO 终点 <1.0 ns 从 1667 降到 701，
   全设计 slack<2.0 ns 条数 **14161 → 10245（−27.7%）**；但 100 MHz WNS 从 **+0.007 掉到 −0.072**
   （35 个失败端点）。新墙正好是 next.html 预测的 A 族：
   `id_ex_u/sel_ex_mem_rs1_o_reg → u_dcache/valid_way*/D`，11 级 / logic 3.004 ns。
   → **F 是"清场"，不是"提余量"；F 必须与 A 一起做才有 WNS 收益。**
2. **R（80 MHz）"重跑实现"拿不到 +2.3 ns，只有 +0.483 ns。** 同一份未改 RTL，把核心约束改成
   12.5 ns 重做综合+实现：WNS **+0.483**（失败端点 0）。原因不是设计变差，而是
   **P&R 按松约束干活**：最差路径 route 9.167 ns（100 MHz 网表同类路径 ~7.6 ns），
   物理质量掉了约 1.9 ns。站点上"80 MHz → +2.340 ns"是**同一张已按 10 ns 布线的网表**
   `reset_timing` 重算出来的，两者不是同一个东西。
   → **降频正确做法：实现仍按 10 ns 过度约束，只把 MMCM 输出改成 80 MHz。** 这样网表是
   100 MHz 军规的，上板时序就是 +2.3~+2.5 ns 量级，再用 `report_timing` 在 12.5 ns 下复核。
3. **WHS 在两种频率下都过不了站点自己写的门禁（≥+0.05）**：100 MHz +0.023 / +0.030，
   80 MHz +0.018 / +0.020。降频不改善 hold，这条门禁必须单独处理。
4. **（2026-10-24 晚追加）路线 C（store buffer）实测有效且 0 周期**：WNS **+0.007 → +0.057**、
   0 失败端点、6 场景与 4 个差分种子的周期/数据完全不变、目标族 192→12 条（worst +1.752），
   BRAM 还少 4 个 tile。F+C 反而只有 +0.005 → **要上就只上 C**。详见 §8。
5. **（2026-10-24 深夜追加）路线 D（中断可接受判决拆拍）同样有效且 0 周期**：在 C 之上
   WNS **+0.057 → +0.087**、0 失败端点、6 场景 cycles 一字不变；**起点为 pc 的路径族 1389 → 1 条**
   （worst +0.057 → +1.491）。D 之后的新墙不再是 CPU，而是 Ascon 核心内部
   `u_crypto_aead/FSM → p12_in_reg`（1 级逻辑、route 9.29 ns 占 94%）。详见 §9。
6. **（2026-10-24 深夜追加）把 `u_crypto_aead/state[3]`（fo=628、单根 9.29 ns）放置后复制**：
   同流程对照 +0.003 → **+0.130**（+0.127 ns，是 D 的 4 倍），复制 24 根反而只 +0.124；
   **在 RTL 里写 `max_fanout` 由综合期复制是错的（−0.008、1 个失败端点）** ——
   扇出复制必须在放置之后做。**但接进生产策略后重测只有 +0.039（对照 +0.087）**：
   那 +0.127 ns 是自定义流程上的收益，不能迁移（§10.6）。详见 §10。

---

## 2. 实验矩阵（4 次实现 + 6 组仿真）

| tag | RTL | 核心周期 | 策略 | WNS | TNS | 失败端点 | WHS | LUT |
|---|---|---|---|---|---|---|---|---|
| control（2026-10-20 记录） | `src/rtl` | 10.000 ns | ExploreWithRemap | **+0.007** | 0.000 | 0 | +0.023 | 11509 |
| `f_100` | F 补丁 | 10.000 ns | ExploreWithRemap | **−0.072** | −1.289 | **35** | +0.030 | 11711 |
| `f_100_pr` | F 补丁 | 10.000 ns | ExplorePostRoutePhysOpt | **+0.005** | 0.000 | 0 | **+0.051** | 11665 |
| `ctl_80` | `src/rtl` | 12.500 ns | ExploreWithRemap | **+0.483** | 0.000 | 0 | +0.018 | 11298 |
| `f_80` | F 补丁 | 12.500 ns | ExploreWithRemap | **+0.456** | 0.000 | 0 | +0.020 | 11575 |

对照的第二策略记录（`docs/cpu_timing_architecture_plan.md` §5.2）：未改 RTL 的
ExplorePostRoutePhysOpt 是 **+0.001 / 2 端点**。所以 F 的第二策略 **+0.005 / 0 端点 / WHS +0.051**
是"贴着 10 ns 墙、但第一次同时满足 0 失败端点与 WHS ≥ +0.05"。第一策略仍是 −0.072，
**双策略门禁（两策略都要 ≥ +0.7 或至少都 ≥ 0）不满足**。
注意两个策略的名次在 F 之后翻转了（control：Explore > pr；F：pr > Explore），
说明这些数字仍在 ±0.08 ns 的网表扰动带里，不能当"F 提升了 0.005"来读。

资源代价：F 的 LUT 11509 → 11711（**+1.8%**，在"劣化 <5%"门禁内），BRAM 38.5 / DSP 4 不变。
WHS 反而略有改善（+0.023 → +0.030），说明 F 的寄存器插入对 hold 无害。

复现（每次 ~25 min，可并行）：

```bash
vivado -mode batch -source build/local/tests_20261024/run_variantF.tcl -notrace \
       -tclargs <tag> <rtl_tree> <clk_in_period_ns> [strategy]
# 例：vivado -mode batch -source build/local/tests_20261024/run_variantF.tcl \
#        -tclargs f_100 build/local/tests_20261024/rtl_F 20.000
#     vivado -mode batch -source build/local/tests_20261024/run_variantF.tcl \
#        -tclargs f_100_pr build/local/tests_20261024/rtl_F 20.000 Performance_ExplorePostRoutePhysOpt
#     vivado -mode batch -source build/local/tests_20261024/run_variantF.tcl \
#        -tclargs ctl_80 C:/.../src/rtl 25.000      # 注意：本机 Tcl 不认 /c/... 的 MSYS 路径
```

`clk_in` 与核心周期的关系：`clk_wiz_0` 是 `CLKFBOUT_MULT_F=18 / CLKOUT0_DIVIDE_F=9`
（×2），所以输入 20.000 → 核心 10.000，输入 25.000 → 核心 12.500。报告里
`core_period` 由 `get_clocks clk_out1_clk_wiz_0` 实测回读，不是假设值。

---

## 3. F 补丁：MMIO 写译码寄存化

补丁文件：`build/patches/timing_F_mmio_wdecode.patch`（只改 `src/rtl/ascon/ascon_mmio.v`，+35 行）。

- 现状：`ascon_we / ascon_addr_sel / ascon_wdata` 由 `bus_interconnect` 用
  `hit_ascon & addr_high` 组合译码直传（源头是 `u_dcache` 的 `bus_addr_r`），
  它同时驱动 `AD_BUF`/`MSG_BUF` 全部 512 个字的写使能、全部配置寄存器、
  以及 START/ZEROIZE 条件锥 —— 这就是 control 里 6176 条 `→CE` + 2820 条 `→D` 的路径。
- 改法：把写请求打一拍（`we_req/wsel_req/wdat_req`），CE 锥改由本地寄存器驱动；
  生效条件用执行当拍的 `!busy_r`（与原来"忙时丢弃"语义一致）。**读路径 `ascon_re`
  保持当拍不变**，所以总线读时序、`rdata_reg` 采样点都不动。
- 代价：写操作晚一拍生效。MMIO 软件是轮询式的，所以

### 3.1 仿真等价（`build/local/tests_20261024/check_F.sh`，Icarus 14.0）

| 场景 | control | F | 结果 |
|---|---|---|---|
| `ise` | PASS，ISE cycles 2496 | PASS，2496 | 一致（$finish 时间逐 ps 相同） |
| `ise_stall` (+HOLD_ISE) | PASS，2496 | PASS，2496 | 一致 |
| `ise_reset` (+RESET_ISE) | PASS，2496 | PASS，2496 | 一致 |
| `ise_security` | PASS | PASS | 一致（$finish 时间相同） |
| `hw`（MMIO 全卸载，7 项 KAT） | PASS，crypto latency 99 / full MMIO **670** | PASS，99 / **675** | **+5 拍** |
| `sw`（软件 AScon，4 workload） | 17353 / 21515 / 17847 / 22094 cycles | 完全相同 | 一致 |

→ 软件路径 **0 周期代价**；硬件 MMIO 路径 **+5 拍（670→675，+0.75%）**。
next.html 给 F 定的门禁是"MMIO 全卸载路径拍数不许变"，按这条 **F 不合格**（差 5 拍），
但这 5 拍是写晚一拍的必然结果，且 `crypto latency`（99）与 cycles/cpb 无关指标不变。

### 3.2 路径族证据（`build/local/tests_20261024/paths_{ctl,f100}.csv`，探针 `probe_classes.tcl`）

| 族 | control | F | Δ |
|---|---|---|---|
| `bus_addr_r → ascon_mmio`（F 的目标） | 8858 条，worst +0.525 | **60 条，worst +1.233** | −8798 条，+0.708 ns |
| `wsel_req_reg → MMIO D`（新增本地族） | — | 487 条，worst +1.436 | 局部、快 |
| `wsel_req_reg → MMIO CE`（新增本地族） | — | 162 条，worst +1.649 | 局部、快 |
| MMIO 终点 <2.0 ns | 11149 | 6694 | −40% |
| MMIO 终点 <1.0 ns | 1667 | **701** | −58% |
| 全设计 <2.0 ns | 14161 | 10245 | −27.7% |
| `run_mlen_reg → u_ascon_core/data_shf`（MMIO 内部，未动） | 1526 条，+0.286 | 1521 条，+0.230 | 基本不变 |

归因很清楚：**跨模块长线消失，代价转移到 A 族**（`id_ex` 旁路选择网 → dcache/if_id/icache），
这一族在 control 里就已经是最差类（`sel_mem_wb_rs1_o_reg → CE` 80 条 +0.557，
`sel_ex_mem_rs2_o_reg → u_divider` 73 条 +0.596），F 只是把它顶到了第一位。
**这正好实测验证了 next.html "F 之后新墙是 CPU 侧"的排序逻辑。**

---

## 4. 80 MHz：为什么重跑实现只有 +0.483 ns

`ctl_80` 的最差路径（`build/reports/tests_20261024/ctl_80/route_paths.rpt`）：

```
Slack (MET): 0.483 ns   Requirement 12.500 ns
pc_reg[5] → u_dcache/data_way0_reg_0/WEA[0]
Data Path Delay 11.156 ns  (logic 1.989 / route 9.167, 82% route)  10 级
```

同一类路径在 100 MHz 生产网表里 route ≈ 7.6 ns → 数据路径 ~9.6 ns，
12.5 − 9.6 ≈ **+2.9**，这就是站点上 +2.340（同一网表重算）/ 折算 +2.483 的来源。
`ctl_80` 里 P&R 看到 12.5 ns 的需求就松手了，route 多走 1.5 ns，
于是只剩 +0.483。**结论：降频不能靠"改约束重跑实现"，要靠"保留 10 ns 过度约束 + 改 MMCM 输出"。**

于是 next.html 步骤 1 的验收条件要改写为：

- 实现：XDC 保持 `create_clock -period 20.000`（核心 10 ns，过度约束 25%）；
  `clk_wiz_0` 的 `CLKOUT1_REQUESTED_OUT_FREQ` = 80（IP 独立入口，重新生成）。
  MMCM 只改配置位，时钟树（BUFG/CCU）与数据通路网表不变，所以物理质量等同 100 MHz build。
- 验收：对最终 `*_routed.dcp` 做一次 `reset_timing` + 12.5 ns 重算（`build/probe_freq_headroom.tcl`
  的做法），要求 **WNS ≥ +2.0 ns**；同时 10 ns 下仍需 ≥ 0（防网表扰动）。
- 若按 12.5 ns 重跑实现来验收，只会得到 +0.48，**等于把 2 ns 余量送给工具**。

未验证：MMCM 实际改成 80 MHz 后（IP 重生成）的网表与本文 100 MHz-IP 网表的差异，
未做 A/B（预期只有 MMCM 配置位与 VCO 频率差别，BSP/CCU 不变）；板上未测。

---

## 5. 与 next.html 结论的差异（要改的表述）

| next.html 现在的说法 | 实测 | 处理 |
|---|---|---|
| R："80 MHz 实测 +2.340 ns（折算 +2.483）" | 那只对**已按 10 ns 布线的网表**成立；按 12.5 ns 重跑实现只有 **+0.483** | 改成"过度约束实现 + MMCM 降频"，并注明两种测法的差 ~1.9 ns |
| R："改 MMCM 输出 → 独立入口 → 重跑实现 → 确认 +2.3 ns" | 重跑实现确认不到 +2.3 | 验收步骤改为"实现约束不变，post-route 用 12.5 ns 重算" |
| F："0 周期（MMIO 本来就是百拍）" | 软件 0 周期；**硬件 MMIO 全卸载 +5 拍**（670→675） | 补一句"写晚一拍，全卸载路径 +5 拍" |
| F："做完再测一次，确认 dcache→mmio 那 8858 条不再压在 7.7 ns 走线上" | 确认：8858 → 60，worst +0.525 → +1.233 | 可写死为已实测 |
| 优先级："F 从顺手做升为下一件该做的事" | F 单独做在 100 MHz 上是 **−0.079 ns / 35 失败端点** | 应写成"F 是 A 的前置清场，不能单独作为提余量手段" |

---

## 6. 未做 / 下一步

- **C（store buffer）**：**已做并已落地**（见 §8.6）。原判断记录如下（当时结论是"不是顺手做"，
  实际做了之后确认工作量约半天、收益 +0.050 ns、0 周期）：写口在
  `store_cache_write` 当拍直接写 `data_way*`，数据来自 `cpu_wdata_i`（旁路 mux 输出）；
  加 1 拍缓冲后**同地址 store→load 会读到旧值**（现在是靠"同拍写 BRAM"侥幸正确，
  流水线里没有 memory RAW 转发），必须补 buffer→load 数据旁路 + 定向 TB，属于 0.5~1 天工作量。
- **A（旁路决策提前）/ D（if 控制早一拍）**：A **已经在 RTL 里**（见 §7.1）；
  D 未做。
- 未验证：板级 XDC/PS7 在场的时序（本文全部为芯片级 STA）；MMCM 80 MHz 重生成网表；
  `report_design_analysis -congestion`（拥塞）仍未做。

---

## 7. 第二波（2026-10-24 晚）：F+A 与 F+后端配方

### 7.1 结论：路线 A 描述的改动已经在 RTL 里，F+A = F

`docs/cpu_timing_architecture_plan.md` §3A 写的是"把 `sel_ex_mem_*`/`sel_mem_wb_*` 从
'id_ex 组合产生'改成 id 段末寄存"。核实代码：

| 证据 | 位置 |
|---|---|
| 旁路选择在 **ID 段**用 `if_id` + `id_ex`/`ex_mem` 现成信息算出 | `src/rtl/cpu_core.v:373-386`（注释即"在 ID 阶段提前计算旁路选择信号"） |
| 4 个选择位在 ID/EX 边界**寄存** | `src/rtl/id_ex.v:183-186`（flush/stall 分支同表，`id_ex.v:133-136,157-160`） |
| EX 段只用寄存后的选择位做 3 输入 mux | `src/rtl/bypass.v:25-40` |

所以"提前决策 + 段末寄存"已经完成，没有剩余改动可做。F 之后真正的第一墙不是决策时机，
而是**这个已经寄存好的 1 位选择位的扇出与物理跨度**：实测 `sel_*_o` 四条网 fo=172/141/172/140，
从 `id_ex` 出发经 bypass mux → rs1 → `+imm` 32 位加法器 → dcache tag RAM 地址 → tag 比较
→ hit → 写回锥，路径 9.95 ns 里 **route 占 6.94 ns（70%）**、logic 只有 3.00 ns。

F 之后 `sel_*` 起点共 **1072 条** slack<2.0 ns 路径，按终点分类：

| 终点 | 条数 | worst |
|---|---|---|
| `dcache/valid_way0_reg`、`valid_way1_reg` D | 64 + 64 | **−0.072** |
| `dcache/lru_reg` D | 64 | −0.063 |
| `dcache/captured_addr/…/CE`、`captured_wdata` D | 29 | +0.382 |
| `ascon_mmio/MSG_BUF_reg` D、`AD_BUF_reg` D | 367 + 120 | +1.436 / +1.553 |
| `ascon_mmio/MSG_BUF_reg` CE、`OUT_BUF_reg` CE | 153 + 31 | +1.649 / +1.867 |

即：**真正压着时序的只有 192 条**（valid_way + lru）。它们的源头是
`dcache.v:471-505` 的"store 命中时清掉另一路 / load miss 清 victim / hit 更新 LRU"——
这些更新必须在**同拍**完成 tag 比较，因为 store 数据也是在同拍写进 BRAM。
**这条链只有 C（store buffer）或 tag 读打一拍（+1 拍）能摘掉，A 摘不掉。**

### 7.2 F + campaign 冠军后端配方：不叠加，反而更差

起点 `build/local/tests_20261024/f_100/riscv_vivado_project.runs/impl_m/top_pl_bram_opt.dcp`
（F 的 post-opt 快照），复用 `build/backend_opt_20261021/run_variant.tcl` 的配方表
（脚本副本 `build/local/tests_20261024/run_backend_F.tcl`）：

| 臂 | 配方 | WNS | TNS | 失败端点 | WHS |
|---|---|---|---|---|---|
| `F_pl_ndh_crit200_ntr` | place ExtraNetDelay_high + crep200 + route NoTimingRelaxation | **−0.226** | −9.028 | 102 | +0.015 |
| `F_pl_ndh_crit200_prod` | 同上 + popt Explore / prout ExploreWithHoldFix | **−0.225** | −21.172 | 228 | +0.015 |
| 对照：同一配方打在 **未改 RTL** 上（10-21 记录） | — | **+0.138** | 0 | 0 | +0.017 |

**campaign 的 +0.138 不能迁移到 F 网表上**。原因可查：该配方的杠杆是"复制最差 200 个端点的
CE 锥"，但在 F 网表上 `crit_ce_nets` 只找到 **13 条** CE 网（fanout 13..129）——
因为 F 之后最差的那批路径终点是 **D 端**（valid_way/lru），不是 CE 端；
复制 CE 打不到它，只会扰动一张已经比原来紧的网表。两条臂的最差路径分别是
`sel_mem_wb_rs1_o_reg → dcache/captured_wdata_reg/CE`（9.950 ns）和
`ex_mem/ex_rd_data_o_reg → dcache/lru_reg/D`（10.032 ns）。

### 7.3 定向扇出复制：本臂无效（实验设计缺陷，不能当结论）

`build/local/tests_20261024/run_selrep.tcl` 想做的：对 4 条 `sel_*_o` 网（fo=172/141/172/140）
和 309 条 `rs1_forward/rs2_forward` 位网（fo≈32）设 `MAX_FANOUT=8` + 驱动寄存器
`EQUIVALENT_REGISTER_REMOVAL=NO`，再用 campaign 的放置/布线指令。

结果：`F_selrep` 与同一流程不做复制的 `F_placeonly` **逐位相同**（WNS −0.175 / TNS −5.355 /
81 端点 / LUT 13799 / replica 46）。probe 确认属性确实写进去了（`MAX_FANOUT=8` 在 4 条网上），
但**扇出仍是 172、没有生成任何副本**——`MAX_FANOUT` 在 post-opt checkpoint 流程里不会触发复制，
要复制必须走 `phys_opt_design -force_replication_on_nets`（campaign 的 `frn` 臂就是这么做的）。
所以这一臂是**空实验**，只能说"campaign 指令集打在 F 上比生产策略差 0.10 ns"（−0.175 vs −0.072），
不能用来判断扇出复制有没有用。

（副产物：这两臂误把 `build/build/` 建在了仓库里，已把报告移到
`build/reports/tests_20261024/F_pl_ndh_crit200_*`、DCP 移到 `build/local/tests_20261024/backend/`，
仓库里不留多余目录。）

### 7.4 第二波的净结论

1. **F 不值得单独上**：100 MHz 与 control 同级（−0.072 / +0.005 对 +0.007 / +0.001），
   80 MHz 也同级（+0.456 对 +0.483），还要付 MMIO 全卸载 +5 拍 + LUT +1.8%。
   F 的价值只在于**它把 C 要摘的那一族提前暴露出来**。
2. 想要 100 MHz 余量，只剩两条路：**C（store buffer，摘掉 valid_way/lru/store 同拍链）**
   或 **tag 读打一拍（+1 拍取数，换 2~3 ns）**；后端已无空间（campaign 最好 +0.138，
   且不能与 F 叠加）。
3. 想马上可交付：**control RTL + 过度约束实现 + MMCM 80 MHz**（§4），
   WNS 折算 +2.3~2.5 ns，不动 RTL、不动 F。

## 8. 路线 C（store buffer）实测：第一个真正有效、且 0 周期的 RTL 改动

### 8.1 改法（补丁 `build/patches/timing_C_dcache_store_buffer.patch`，只改 `src/rtl/dcache.v`）

1. **store 不再当拍写 BRAM**：本拍只把 `{地址, 数据, 字节掩码}` 打进 1 项 buffer，
   下一拍提交。`data_way0/1` 因此改成真正的 SDP：Port A 只读（`rd_addr`），
   Port B 由 fill 与 buffer 提公共用（fill 优先；二者不可能同拍——store 只在 IDLE 发起、
   提交在下一拍，而 FILL 期间 CPU 被 stall，中间至少隔一个 MISS_CAPTURE）。
2. **valid / LRU 更新寄存一拍**：请求当拍把 `{load_miss, victim, store, hit0, hit1, acc, idx, woof}`
   算好寄存，下一拍再作用。于是 `valid_way*/lru` 的 D 端只由本地寄存器驱动，
   同拍 tag 比较 → hit → 元数据的链被切断。
3. **store→load 定向转发**：`sb_valid && sb_addr == rd_addr` 时，把 buffer 的字节按掩码
   覆盖到读出的数据上（在 `data_out` 之后、`cpu_rdata_o` 之前，用一级寄存的比较结果）。

### 8.2 实测

| 变体 | 核心周期 | 策略 | WNS | TNS | 失败端点 | WHS | LUT | FF | BRAM |
|---|---|---|---|---|---|---|---|---|---|
| control | 10.000 ns | ExploreWithRemap | +0.007 | 0 | 0 | +0.023 | 11509 | 16040 | 38.5 |
| **`c_100`（C）** | 10.000 ns | ExploreWithRemap | **+0.057** | 0 | **0** | +0.019 | 11476 | 16146 | **34.5** |
| `fc_100`（F+C） | 10.000 ns | ExploreWithRemap | +0.005 | 0 | 0 | +0.013 | 11784 | 16189 | 34.5 |
| **`d_100`（C+D）** | 10.000 ns | ExploreWithRemap | **+0.087** | 0 | 0 | +0.021 | 11483 | 16156 | 34.5 |
| `C_pl_ndh_crit200_ntr`（C+campaign 冠军配方） | 10.000 ns | crep200 + ntr 布线 | +0.017 | 0 | 0 | +0.035 | — | — | — |
| （对照）`f_100`（F） | 10.000 ns | ExploreWithRemap | −0.072 | −1.289 | 35 | +0.030 | 11711 | — | 38.5 |

- **WNS +0.007 → +0.057（+0.050 ns，7 倍余量），0 失败端点，TNS 0**；LUT −33、FF +106、
  **BRAM −4 个 tile（38.5→34.5，SDP 重排的副产品）**。
- **周期完全不变**：见 8.3。
- F+C 反而只有 +0.005（F 的 +202 LUT 与 MMIO 那套寄存器在这里是纯负担）→ **要上就只上 C，不要 F**。
- **C + campaign 冠军后端配方 = +0.017，也不叠加**（该配方只管 CE 锥复制：在 C 网表上
  `crit_ce_nets` 只有 9 条，fanout 13..366）。C 之后 100 MHz 的最好成绩就是 **C 单独 +0.057**。
- 注意 +0.050 仍在 ±0.08 ns 的网表扰动带里，所以**真正的证据是 8.4 的路径族塌缩**，不是这个数字本身。

### 8.3 等价性证据（两道）

**(a) 全 SoC 6 场景**（`build/local/tests_20261024/check_C.sh`，Icarus 14.0）：

| 场景 | control | C |
|---|---|---|
| `ise` / `ise_stall` / `ise_reset` | PASS，2496 拍 | PASS，2496 拍 |
| `ise_security` | PASS | PASS |
| `hw`（MMIO 全卸载，7 项 KAT） | PASS，latency 99 / full MMIO **670** | PASS，99 / **670** |
| `sw`（4 个 workload） | 17353 / 21515 / 17847 / 22094 cycles | **完全相同** |

→ 与 F 不同，C **连硬件 MMIO 的 670 拍都不变**，是真正的 0 周期。

**(b) dcache 差分轨迹**（`build/local/tests_20261024/tb_dcache_trace.v`）：同一份确定性激励
（伪随机 + 定向 back-to-back `store→load` / `store→store→load` 同地址）分别驱动 control 与 C，
逐拍记录 `cpu_re/we/addr/stall/rdata` + 全部总线信号 + 末尾存储器校验和，然后 diff。
**4 个种子（默认 4000 ops、另 3 个各 1500 ops）全部逐字节相同**，说明 store 可见性、
字节掩码、miss/fill 时序、LRU/valid 更新顺序都没变。

### 8.4 路径族证据（`paths_c100.csv` vs `paths_ctl.csv`）

| 指标 | control | F | **C** |
|---|---|---|---|
| `dcache` 里 `valid_way*/lru` 终点的路径（<2.0 ns） | 192 条，worst +0.143 | 224 条，worst **−0.072** | **12 条，worst +1.752** |
| `-> u_dcache` 全部 | 489 条，worst +0.007 | 555 条，worst −0.072 | 343 条，worst **+0.249** |
| 起点为 `sel_*` 的路径 | 1218 条 | 1072 条 | **505 条** |

**目标族被打穿**：同拍 tag→hit→valid/lru 的链从 192/224 条降到 12 条，余量从 −0.072 抬到 **+1.752 ns**。
C 之后的最差单条变成 `pc_reg[5] → u_ex_mem/ex_rd_data_o_reg[0]/CE`（9 级、logic 1.998、route 7.592，+0.057），
以及 `pc_reg[5] → u_ascon_ise`（649 条，worst +0.224）——**这正是 next.html 里 D 路线要处理的
"取指 → 判 stall → 回头使能"那条环**。所以顺序应该是 **C 之后接 D**，A 依然无事可做。

### 8.5 C 的风险与未验证

- 1 项 buffer 的**同拍冲突**已按"fill 优先"处理，并论证二者不可能同拍；但这依赖
  "store 只在 IDLE 发起、FILL 期间 CPU 被 stall" 这两个前提，若以后改流水（例如放开
  store 在 stall 期间发射）必须重验。
- 未做板级；未做拥塞交叉验证；`c_100` 的 WHS +0.019 仍低于 +0.05 门禁。
- 若要把 WNS 抬到 +1.0，还差 D（取指/stall 环）与 80 MHz 过度约束的组合。

### 8.6 落地记录（2026-10-24 22:0x）

- `src/rtl/dcache.v` = 本补丁版本，sha256 `79af461cf53545e79c294814e7f4869c341dbb745527885c0ee1755c1b5c1113`，
  **与 `c_100` 那次实现所用的 RTL 逐位相同**（`build/reports/tests_20261024/c_100/build_context.txt`），
  所以 +0.057 / 0 失败端点 / BRAM 34.5 这一组数字对入库代码直接成立，不需要重跑实现。
- 同一提交撤掉了 `fb852b5` 在 `ascon/{ascon_mmio,ascon_ise,ascon_aead_core}.v` 里加的
  `` `include ``：这三个文件没有 include guard（同目录 `crypto_aead.v`/`ascon_permutation.v`/
  `ascon_round.v`/`ascon_word.v` 都有），而它们同时又作为独立源文件编译，导致
  `Synth/Elab: 'ascon_aead_core' has already been declared`，整库 elaboration 失败。
- 入库后回归：`build/local/tests_20261024/check_final.sh`（control = HEAD 的 dcache.v + 当前其余源，
  patched = 当前 `src/rtl`）跑 6 场景，KAT 与 cycles 必须逐条相同。

## 9. 路线 D（中断可接受判决拆拍）实测与落地

### 9.1 目标路径

C 之后整机最差路径（+0.057 ns，9 级 / logic 2.0 / route 7.59）是一条跨模块控制锥：

```
pc_reg → u_icache tag RAM(RAMD64E) → hit_way0 → icache_stall
      → csr_file/inter_req → (stall_ctrl 优先级链) → flush[1] → u_ex_mem/CE
```

即 `cpu_core.v` 里的中断接受判决把 pc 衍生的 `!icache_stall` 和当拍快条件放在同一个与门里：

```verilog
wire inter_accept_ready = id_ex_inst_valid && !dcache_stall && !dmem_axi_stall_req
                       && !ex_stall_req && !icache_stall && !fence_i_stall;   // 改前
```

### 9.2 改法（补丁 `build/patches/timing_D_interrupt_guard_register.patch
build/timing_tests/rep_fanout.tcl, probe_fanout.tcl   # 定点扇出复制 + 大扇出网探针
build/timing_tests/run_prod_rep.tcl                   # 把复制接进生产策略的 run 钩子（结论：不进流程）
build/reports/tests_20261024/{prod_ctl,prod_rep,prod_rep1}/   # 接入后的重测结果
build/reports/timing_tests/{rep_ctl,rep_ff400,rep_any150}/   # 三个复制臂的结果
build/reports/tests_20261024/e_100/                   # RTL max_fanout 反例（−0.008）`，只改 `cpu_core.v`）

把 pc 长链那一项拆出来只驱动一个触发器，当拍再与全部快项（都是寄存器输出）相与：

```verilog
wire inter_slow_ok = id_ex_inst_valid && !icache_stall;   // 慢项：只进寄存器
always @(posedge clk or negedge rst_n) inter_slow_ok_q <= inter_slow_ok;
wire inter_accept_ready = inter_slow_ok_q && id_ex_inst_valid
                       && !dcache_stall && !dmem_axi_stall_req
                       && !ex_stall_req && !fence_i_stall;               // 改后
```

`inter_req` 本身仍是「一次脉冲 + `inter_req_reg` 锁存」（`csr_file.v:99-111` 未改），
所以只在「中断挂起且门槛满足」的那一拍动作；**唯一语义变化**是 icache 那一项变成上一拍的判决
（最坏晚一拍接受中断，取指数据通路与 icache 填充不受影响，填充由 `icache_flush` 中止）。

### 9.3 实测（Vivado 2025.2 / xc7z020clg400-1 / ExploreWithRemap / 10 ns）

| 变体 | WNS | TNS | 失败端点 | WHS | LUT | FF |
|---|---|---|---|---|---|---|
| control（未改） | +0.007 | 0 | 0 | +0.023 | 11509 | 16040 |
| `c_100`（C） | +0.057 | 0 | 0 | +0.019 | 11476 | 16146 |
| **`d_100`（C+D）** | **+0.087** | 0 | 0 | +0.021 | 11483 | 16156 |

资源几乎不变（LUT +7、FF +10，就是那个 `inter_slow_ok_q`）。

### 9.4 机制证据（这才是关键，+0.030 本身在噪声带里）

`paths_c100.csv` vs `paths_d100.csv`（slack<2.0 的逐路径族）：

| 族 | C | **C+D** |
|---|---|---|
| 起点含 `pc` | **1389 条**，worst +0.057 | **1 条**，worst **+1.491** |
| 终点 `u_ascon_ise` | 693 条，worst +0.224 | 640 条，worst **+0.794** |
| 终点 `ex_rd_data_o_reg` | 52 条，worst +0.057 | 63 条，worst **+0.648** |

**C 里由 pc 出发的 1389 条路径被一次全部清掉**（只剩 1 条、余量 +1.491），
下游 `u_ascon_ise` / `ex_mem` 相关锥也分别抬高 0.57 / 0.59 ns。

D 之后的新墙（`build/reports/tests_20261024/d_100/route_paths.rpt`）：

```
Slack (MET): 0.087 ns
u_ascon_mmio/u_ascon_core/u_crypto_aead/FSM_sequential_state_reg[3]
  → u_ascon_core/u_crypto_aead/p12_in_reg[215]/D
Data Path Delay 9.870 ns (logic 0.580 / route 9.290)   逻辑级数 1
```

**只剩 1 级逻辑、route 占 94%** —— 已经不是逻辑深度问题，而是 Ascon 核心 `p12_in` 状态搬运
寄存器的物理跨度（对应 next.html 里"ad_shf/p12 拆拍"或 floorplan）。CPU 侧已经没有 pc 起点的墙了。

### 9.5 等价性与风险

- 全 SoC 6 场景（`check_D.sh`：control = C 落地后的 src/rtl，patched = C+D）：KAT 全 PASS，
  cycles **逐条不变**（ise/ise_stall/ise_reset 2496、hw latency 99 / full MMIO 670、
  sw 17353 / 21515 / 17847 / 22094）。
- **风险（必须记住）**：现有 6 个固件与全部单元/ISA TB **没有任何一个开启中断**
  （无 `mtvec` / `mret` / `mie` 写入），所以这条改动在功能上等价于空操作（`interrupt_en=0` 时
  `inter_req` 恒 0）。**一旦以后固件启用中断，必须先补定向 TB**（clint 定时器中断 →
  `mie/mtvec` → 进 trap → `mret` 回原指令）确认"晚一拍接受"不会把 `trap_pc` 指到气泡上。
- 落地：`src/rtl/cpu_core.v` = 补丁版本，与 `d_100` 实测所用 RTL 逐位相同。

## 10. 大扇出节点本地化复制（2026-10-24 深夜）

### 10.1 定位：压死时序的是一根 9.29 ns 的网

C+D 之后最差路径（`build/reports/tests_20261024/d_100/route_paths.rpt`）：

```
u_ascon_mmio/u_ascon_core/u_crypto_aead/FSM_sequential_state_reg[3]/Q   (SLICE_X35Y87)
  → net u_crypto_aead/state[3]   fo=627   route 9.290 ns        ← 唯一的元凶
  → LUT5 (SLICE_X102Y90)  0.124 ns
  → u_crypto_aead/p12_in_reg[215]/D
Data Path Delay 9.870 ns (logic 0.580 / route 9.290)，逻辑级数 1
```

`state[3]` 是 `crypto_aead.v:99` 的 FSM 状态位（`reg [3:0] state`），它扇出到整条 datapath
的全部使能/选择锥（628 个负载），一根网从 SLICE_X35Y87 横跨到 SLICE_X102Y90。
全局最大扇出是复位分发网 `u_ascon_mmio/rst_sync_reg[2]`（fo=9757），但它不在最差路径上。

### 10.2 做法：放置后定点复制 + 防折叠约束

脚本 `build/timing_tests/rep_fanout.tcl`（参数化：tag / post-opt.dcp / probe|ctl|rep /
minfo / with_rst / seed.routed.dcp / drv_kind）：

1. **选点**从**布线后** DCP 取（post-opt 的时序视图只有逻辑延迟，看不出 70~90% 的走线）：
   最差 200 条 setup 路径的「起点寄存器输出网」+ 终点 2 级扇入里的宽网，fo ≥ minfo；
   排除时钟网络、常量、进位链、MUX、RAM、输入端口。
2. **防折叠**：`opt_design` 之前给候选网驱动单元设 `EQUIVALENT_REGISTER_REMOVAL NO`
   （否则 opt/phys_opt 会把复制出的等价寄存器合并回去 —— campaign 记过这个坑）。
3. **复制**：`place_design` → `phys_opt_design -directive AggressiveExplore` →
   `phys_opt_design -force_replication_on_nets <候选>`（2025.2 唯一入口）+ `MAX_FANOUT 128` 提示。
4. 复制后对新建的 `*_rep*` 单元再设一次 `EQUIVALENT_REGISTER_REMOVAL NO`。
   **不用 `DONT_TOUCH`** —— 它同时冻结放置，副本就搬不到负载附近了。

### 10.3 结果（同一流程：opt Explore + place Default + phys_opt Aggressive + route Aggressive）

| 臂 | 复制对象 | WNS | TNS | 失败端点 | WHS | replica 单元 |
|---|---|---|---|---|---|---|
| `rep_ctl` | 不复制（流程对照） | +0.003 | 0 | 0 | +0.024 | 51 |
| **`rep_ff400`** | **只复制 `state[3]`（fo=628）** | **+0.130** | 0 | 0 | +0.013 | 60 |
| `rep_any150` | 24 根宽网（含 rst_sync fo=9757、p_0_in fo=3990） | +0.124 | 0 | 0 | +0.013 | 93 |
| `rep2_sel` | 在 `rep_ff400` 基础上再复制 9 根（`pc_o[5/6]`、`func_sel_o[0]` 等 fo 137~218） | **+0.055** | 0 | 0 | +0.013 | 52 |
| `e_100` | RTL `(* max_fanout = 64 *)` + 生产策略 | **−0.008** | −0.008 | **1** | +0.028 | — |
| （参考）`d_100` | 不复制，生产策略 | +0.087 | 0 | 0 | +0.021 | — |

- **只复制一根网就拿到 +0.127 ns（同流程对照 +0.003 → +0.130）**，是 D 那一步（+0.030）的 4 倍；
  复制 24 根反而略差（+0.124）且多 33 个副本 —— **越外科越有效**。
- **合成期复制（RTL `max_fanout`）是错的**：`e_100` 掉到 −0.008 / 1 个失败端点。
  原因是放置后才复制时，Vivado 在**已知的物理位置**上把 628 个负载分给就近的副本；
  合成期复制出来的副本还要跟整张网表一起被重新摆放，等于没有利用"本地化"。
- 复制后 `state[*]` 从「fo ≥ 128 的网」清单里彻底消失；
  新最差变成 `id_ex/sel_ex_mem_rs1_o_reg → u_ascon_ise/state_reg[182]/CE`（+0.130）
  和 `→ u_dcache/captured_wdata_reg[31]/CE`（+0.130）。
- **第二轮复制要停手**：以 `rep_ff400` 网表为种子再复制 9 根（`pc_o[5/6]` fo=218/215、
  `func_sel_o[0]` 137、`ascon_mmio/Q[0]`、`p12_inst/Q[0]`）结果掉到 **+0.055** ——
  那些是数据/地址位而不是使能锥，复制只会多出副本并扰动布局。
  结论：**一次外科手术式复制就够，继续加反而变差**（与 campaign 全局复制臂的结论一致）。

### 10.4 怎么用

这条收益**不是 RTL 改动**（`src/rtl` 未动），而是实现流程里的一步：

```bash
# 以生产网表的 post-opt 快照为起点，复制最差路径上的宽网（只复制 1 根就够）
vivado -mode batch -source build/timing_tests/rep_fanout.tcl -notrace \
       -tclargs rep_ff400 <impl_runs/impl_m/top_pl_bram_opt.dcp> rep 400 0 <routed.dcp> ff
# 输出：build/reports/timing_tests/rep_ff400/result.txt + *_routed.dcp
```

要在正式流程里固化，就把 `rep_fanout.tcl` 的第 3~4 步（EQREG NO → place → phys_opt →
`-force_replication_on_nets` → 副本 EQREG NO）接进团队的实现脚本；不要写进 RTL。

### 10.5 未验证

- 只做了 3 个复制臂；`minfo`/副本数量没有扫（128/64/32 未比）。
- 该流程与生产策略（ExploreWithRemap）不是同一个 directive 组合：
  `rep_ctl` +0.003 说明这套流程本身比生产策略差 0.08，所以 **+0.130 不能直接当作
  "生产流程上的最终余量"**；要把复制步骤接进生产策略后重测才知道叠加后的绝对值。
- WHS 从 +0.024 降到 +0.013（复制改变了 hold 关系），仍 < +0.05 门禁。
- 仿真不受影响（复制是网表操作，`e_100` 的 6 场景 cycles 与对照完全相同），无功能风险。

### 10.6 接入生产策略后的重测（2026-10-25 01:10）：**收益不复现**

把复制步骤用 `STEPS.PHYS_OPT_DESIGN.TCL.POST` 钩子接进 **Performance_ExploreWithRemap**
全流程（脚本 `build/timing_tests/run_prod_rep.tcl`，策略与 directive 一字不改），
起点是当前 `src/rtl`（C+D 已落地）：

| 臂 | 钩子内容 | WNS | 失败端点 | WHS | replica | 最差路径 |
|---|---|---|---|---|---|---|
| `prod_ctl` | 无（策略对照） | **+0.087** | 0 | +0.021 | 51 | `state[3] → p12_in_reg[215]/D`，9.870 / net 9.290 / 1 级 |
| `prod_rep1` | 只复制 `state[3]`（fo 628） | **+0.039** | 0 | +0.020 | 60 | `ex_mem/ex_rd_data_o_reg[11] → if_id/pred_target_o_reg[13]/CE`，9.595 / logic 3.183 / 11 级 |
| `prod_rep` | 复制 2 根（`state[3]` + `p8_inst/s2_reg[0]_0[2]`） | +0.039 | 0 | +0.020 | 60 | 同上 |

- `prod_ctl` **逐位复现了 `d_100`（+0.087）**，最差路径同一条（9.870 / net 9.290 / 1 级），
  说明这套 run 流程与 `run_variantF.tcl` 等价，对照可信。
- 钩子确实执行了：`PRODREP candidates=1 fo=628 → after fo=25`，那根 9.29 ns 的网
  **被拆成 25 份、从关键路径上消失**（新最差已经不是它）。
- 但**整机 WNS 从 +0.087 掉到 +0.039**：新最差换成一条 11 级、logic 3.183 ns 的
  `ex_mem → if_id/pred_target/CE` 路径。也就是说：
  **省下来的 9.29 ns 走线，被新增 ~50 个副本 FF 带来的布局扰动吃掉了**（−0.048）。
- 结论：**§10.3 里那 +0.127 ns 是该自定义流程上的收益，不能迁移到生产策略。**
  那套流程的对照只有 +0.003（比生产策略差 0.08），所以复制只是把一张本身就很差的网表
  补到及格；生产策略本来就把这根网放得还算合理，再复制就是纯扰动。
- 因此**当前 100 MHz 的最好成绩仍是生产策略 + C + D 的 +0.087 ns**（`prod_ctl` / `d_100` 相互印证）。
  复制步骤**不进流程**，脚本保留作为工具与证据。

## 11. 证据路径
```
build/local/tests_20261024/
├── check_F.sh                     # 6 场景等价（iverilog）
├── sim/run_<case>_<control|f>.log # 仿真原始日志
├── rtl_F/                         # F 的 RTL 副本（ascon/ascon_mmio.v 已改）
├── run_variantF.tcl               # 4 次实现的唯一入口
├── probe_classes.tcl              # 导出 slack<2.0 路径 CSV
├── classify.py                    # 按族配对
└── paths_ctl.csv / paths_f100.csv # 路径族原始数据
build/patches/timing_F_mmio_wdecode.patch
build/reports/tests_20261024/{f_100,f_100_pr,ctl_80,f_80}/   # result.txt + route_*.rpt
build/reports/tests_20261024/{F_pl_ndh_crit200_ntr,F_pl_ndh_crit200_prod}/  # F + campaign 配方
build/reports/tests_20261024/second/{F_selrep,F_placeonly}/                 # 空实验（见 §7.3）
build/local/tests_20261024/run_backend_F.tcl   # campaign 配方表跑在 F 网表上
build/local/tests_20261024/run_selrep.tcl      # 定向扇出复制（MAX_FANOUT 无效）
build/local/tests_20261024/probe_mf.tcl        # 确认 MAX_FANOUT 写进去了但没复制
build/local/tests_20261024/check_C.sh          # C 的全 SoC 6 场景等价
build/local/tests_20261024/tb_dcache_trace.v   # dcache 逐拍差分激励（4 个种子全相同）
build/local/tests_20261024/rtl_C/, rtl_FC/     # C / F+C 的 RTL 副本
build/reports/tests_20261024/{c_100,fc_100,d_100}/   # C / F+C / C+D 的实现结果
build/local/tests_20261024/check_D.sh, check_D_landed.sh
build/local/tests_20261024/paths_c100.csv, paths_d100.csv
build/patches/timing_C_dcache_store_buffer.patch
build/patches/timing_D_interrupt_guard_register.patch
build/timing_tests/rep_fanout.tcl, probe_fanout.tcl   # 定点扇出复制 + 大扇出网探针
build/timing_tests/run_prod_rep.tcl                   # 把复制接进生产策略的 run 钩子（结论：不进流程）
build/reports/tests_20261024/{prod_ctl,prod_rep,prod_rep1}/   # 接入后的重测结果
build/reports/timing_tests/{rep_ctl,rep_ff400,rep_any150}/   # 三个复制臂的结果
build/reports/tests_20261024/e_100/                   # RTL max_fanout 反例（−0.008）
```
