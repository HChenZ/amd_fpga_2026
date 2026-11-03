# 100 MHz 架构改动方案（含“砍掉 dcache”的定量评估）

> 2026-11-01：历史架构/改动评估，非当前PUF3修改授权。保留估算与实测区分，不把计划方案当已集成。
> 当前源选择与冻结工件见 version_entrypoints.md。

2026-10-20；owner TBD。基线 `3c6f134`。数据来源：`build/local/margin_20261020/paths_lt_2p0.csv`
（14164 条 slack<2.0 ns 的 setup 路径，导出自 `acb_remap_routed.dcp`，探针
`build/probe_path_classes.tcl`）。本文只给方案与数据，不改 RTL。

---

## 1. 先回答：砍掉 dcache 能得到什么

**时序收益 = 0；性能收益 = 负。不建议。**

1. **最差路径根本不在 dcache**：−0.140 ns 那条是
   `id_ex_u/sel_mem_wb_rs1_o_reg/C → id_ex_u/rs2_o_reg[4]/CE`，整条在 `id_ex_u` 内部。
   把**所有**与 dcache 相关的路径当作消失后重算，剩余 WNS 仍是 **−0.140**（4585 条路径仍<2 ns）。
2. dcache 只占 slack<0.5 ns 路径的 29%（308/1057）、<0.1 ns 的 24%（13/55）；
   它在榜上的是 #2 `pc_reg → u_dcache/bus_addr_r/CE`（−0.071）和 #3/#4
   `id_ex → u_dcache/data_way*/DIADI`（−0.047/−0.019）。砍掉这四条，下一条（id_ex 内部）立刻顶上。
3. **性能一定变差**：现在 load 命中是 1 拍（BRAM 寄存输出，`cpu_stall_o` 在 IDLE+hit 时为 0）。
   砍掉后每次 load 都要走 `bus_interconnect → axi_bram_ctrl` 的 AXI 读（≥4 拍，且要等
   `bus_rdata_valid_i`），in-order 五级流水没有乱序容忍 → 每次 load 都停顿。
   软件版 16840 拍里 load 密度远高于 ISE 版 2496 拍，于是**软件基线掉得比 ISE 多**，
   加速比会被“基线变慢”抬高 —— 这属于自欺，材料里站不住。
4. 结论：dcache 的问题不是“存在”，而是**它的输入直接来自 id_ex 的旁路选择网**。
   要修的是旁路网（§3A），不是把 cache 拆掉。

---

## 2. 时序墙的真实归属（实测，14164 条路径分类）

| 模块 | 最差 slack | <0.5 ns 条数 | <1.0 ns 条数 |
|---|---|---|---|
| `id_ex_u` | **−0.140** | 647 | 1165 |
| `u_if_stage` | −0.071 | 358 | 932 |
| `u_dcache` | −0.071 | 308 | 1208 |
| `u_icache` | +0.074 | 124 | 222 |
| `u_if_id` | +0.003 | 73 | 138 |
| `u_ex_stage` | +0.133 | 206 | 626 |
| `u_ascon_ise` | +0.133 | 198 | 606 |
| `u_ascon_mmio` | +0.108 | 71 | 1670 |
| `u_ex_mem` | +0.089 | 48 | 87 |
| `u_csr_file` | +0.497 | 1 | 85 |
| `u_mem_wb` | +0.406 | 1 | 19 |

最差 10 条路径里有 9 条**从 `id_ex_u` 出发**（`sel_ex_mem_rs1_o/rs2_o`、`sel_mem_wb_rs1_o`、
`w_reg_waddr_o` 这些旁路/回写选择寄存器），去向是：`id_ex_u` 自己的 `rs1_o/rs2_o/imm_o` 的 CE、
`u_if_id` 的 `CE`/`if_pc_o`、`u_dcache` 的 `DIADI/WEA/lru/valid`。

也就是说：**“选哪一路数据”这个决策，是组合产生后再跨模块去驱动别处的使能/数据**，
而它自己又是下一级的输入 → 一圈长链。

### 2.1 收益模型（假设某模块所有路径各获得 g ns 缓解）

| 改动 | g=1.5 ns 后 WNS |
|---|---|
| 只动 dcache | −0.140（**无变化**） |
| 只动 id_ex | −0.071 |
| 只动 icache / if_stage / ISE / mmio / csr | −0.140（都无变化） |
| dcache + id_ex | +0.089 |
| ＋if_stage | +0.108 |
| 全部模块 | +1.281 |

**要点：没有任何单点改动能把 100 MHz 抬到正余量；要拿到 +1.0 ns，必须多模块协同。**

---

## 3. 具体改法（按性价比排序）

### B. `pc → dcache/bus_addr_r/CE` 断链（最便宜，0 周期代价）

- 现状：`bus_addr_r` 的 CE 是 `in_capture || store_now || mmio_read_now || mmio_write_now`，
  这些条件含 hit 判定（`hit = valid && tag==req_tag`，tag 来自分布式 RAM 异步读）。
- 改法：IDLE 拍**无条件**锁存地址（地址本来就每拍有效），或把 `cache_access_fire` 打一拍当 CE。
- 预期：消掉 #2 与 32 条 `bus_addr_r_reg` 路径。

### C. dcache 写口加 1 项 store buffer（0 周期代价）

- 现状：store 直接写 `data_way*[rd_addr]` 的字节使能，数据来自 id_ex 旁路 mux
  （#3/#4 与 32 条 `bus_wdata_r`、28 条 `captured_wdata`）。
- 改法：本拍只把 `{addr, wdata, wmask, valid}` 打进 1 项 buffer，下一拍写 BRAM；
  store→load 转发从 buffer 比较（比现在“读 BRAM 后比较”更快）。
- 预期：消掉写入端口整族（约 100 条 <0.5 ns），且写穿总线本来就晚一拍，无周期代价。
- 风险：同地址紧邻 `store→load` 的可见性必须定向 TB 覆盖。

### E. `ascon_ise` 的 cancel 移出 320-bit CE 锥（0 周期）

`src/rtl/ascon/ascon_ise.v:80` 的 `else if (cancel) state <= 0` 把 flush/trap 长锥并进了
CE。加 `state_valid`（cancel 当拍清），`rd_data = state_valid ? state[..] : 0`，物理清零延后
一拍。**安全语义必须用 `ise --reset/--security` 证明清零期间读不出旧状态。**

### A. id_ex 旁路选择网（收益最大，风险最高）

- 目标：把 `sel_ex_mem_*` / `sel_mem_wb_*` 从“id_ex 组合产生”改成**id 段末寄存**：
  hazard/forward 决策只用 id 段信息（rs1/rs2 地址、各级目的寄存器号与 valid），EX 段直接用
  寄存好的选择位，6 选 1 mux 降成 1 级 LUT6。
- 同时把 `rs1_o/rs2_o/imm_o` 的 CE 从“选择网”改为 hazard 寄存版驱动。
- 预期：把 #1 抬到 +0.5 以上，并连带缓解 #3~#8、`if_id` CE。
- 风险：旁路优先级、load-use、flush 打断三处最容易改错；改错直接破坏 KAT。

### D. if_stage / if_id（与 A 同源）

`if_pc_o_reg`、`stall_inst_reg_reg` 的 CE 由 id_ex 选择网 + icache stall 组合驱动；
`u_icache` 的 `valid_way0/1_reg` 有 53+39 条 <0.5 ns 路径（64 位向量的写使能由 index 译码）。
把 stall/flush 决策早一拍寄存，valid 写使能用寄存版译码。

### F. ascon_mmio（CPU 侧修好后的新瓶颈）

`u_ascon_mmio` 现在最差 +0.108 ns，但 <1.0 ns 有 1670 条（占 44.8%）——
一旦 CPU 侧被抬上去，它立刻成为新墙。`ad_shf_reg` 那 44 条 <0.5 ns 是 AD 吸收的 64-bit
旋转/字节搬运组合环，拆成两拍即可（MMIO 往返本来就是 100 拍量级，代价可忽略）。

---

## 4. 周期代价

| 改动 | 周期代价 | 需重测 |
|---|---|---|
| B / C / E / F | 0 | 只需确认 KAT 与 MMIO 往返拍数不变 |
| A / D | 目标是 0（不改流水级数）；若拆不出纯组合方案则需要 +1 拍 | 所有 cycle benchmark |

---

## 5. 实施顺序与门禁

### 5.0 先看一个实测事实：这个设计的 WNS 有 ±0.7 ns 的“网表扰动敏感度”

同一脚本、同一策略（Performance_ExploreWithRemap）、同一 part，一次跑完的对照结果：

| 版本 | LUT | WNS | 失败端点 |
|---|---|---|---|
| control（未改 RTL） | 11818 | **+0.007** | 0 |
| 只改 `ascon_ise` 的 cancel（E-v1） | 12138 | −0.273 | 137 |
| dcache CE（B）+ E-v2 | 11930 | −0.643 | 649 |

LUT 多的版本反而比 LUT 少的版本好 → 损伤与改动大小无关。路径级证据：e2 的最差路径
**13 级逻辑 / 8 个 CARRY4 / logic 3.564 ns**（control 是 10 级 / logic 1.696 ns），
终点是 `id_ex/*_reg/CE`；锥里串着 **32 位地址加法器 → 非对齐 trap → `id_ex/flush`（fanout 94）→ CE**。

结论：
- 当前 +0.007 是“布局刚好合适”的结果，任何 RTL 改动都会重排，把这条锥推到 −0.3~−0.7；
- 因此**验收不能只看 WNS**，要看绑定路径类的逻辑级数/logic delay，且每步必须重跑 STA；
- **A1（下面的第 0 步）是前置条件**：这条锥不修，任何改动都无法在 100 MHz 下验收。

### 5.1 A1：把 32 位地址加法器摘出 trap→flush→CE 锥（0 周期，改动 3 行）

`src/rtl/ex_stage.v:433,446`：

```verilog
wire [XLEN-1:0] mem_addr = id_rs1_reg + id_imm_reg;   // 完整 32 位加法器
non_aligned_word = (ex_mem_addr[1:0] != 2'b00);       // 只用到低 2 位
```

对齐判定只需低 2~3 位，而低位和不受进位链影响：`(a+b)[2:0] == (a[2:0]+b[2:0])[2:0]`。
补丁见 `build/local/patches/ex_stage.v.a1`（3 位部分和），语义完全不变，
但 trap 判定不再等待 32 位进位链。<br>预期：该路径类从 13 级 / 3.56 ns 降到 7 级 / ~2 ns 量级。

| 步 | 内容 | 工期 | STA 门禁 | 失败处置 |
|---|---|---|---|---|
| 1 | A1（对齐判定用 3 位部分和） | 0.5 天 | 绑定类 logic ≤2.2 ns、WNS ≥ +0.3 | 直接转 80 MHz |
| 2 | B + C + E（dcache CE / store buffer / ISE cancel） | 0.5 天 | WNS 不劣化 | 单项回退 |
| 3 | A + D（旁路网 / if 控制） | 1~1.5 天 | WNS ≥ +0.7 | 回到步 1 结果 + 80 MHz |
| 4 | F（mmio 内部拆拍） | 0.5 天 | WNS ≥ +1.0 | 回到步 3 结果 + 80 MHz |

### 5.2 A1 实测结果（2026-10-20）

同一脚本、同一策略、同一 part，A1 单独落地：

| 版本 | LUT | WNS | TNS | 失败端点 | WHS |
|---|---|---|---|---|---|
| control（未改） | 11818 | +0.007 | 0.000 | 0 | +0.023 |
| **A1（ExploreWithRemap，生产策略）** | **11821** | **+0.016** | **0.000** | **0** | +0.012 |
| A1（ExplorePostRoutePhysOpt，第二策略） | — | **−0.003** | −0.004 | **2** | +0.020 |
| A1 + pblock X50Y0:X113Y99（ExtraTimingOpt/Aggressive） | — | **+0.022** | 0.000 | 0 | +0.012 |
| A1 + pblock X50Y0:X113Y149（ExtraPostPlacementOpt） | — | −0.041 | −0.164 | 4 | +0.016 |
| A1 + route MoreGlobalIterations | — | −0.297 | −7.793 | 105 | +0.027 |
| E-v1（只改 ISE cancel） | 12138 | −0.273 | −11.548 | 137 | +0.017 |
| B + E-v2 | 11930 | −0.643 | −127.381 | 649 | +0.021 |

对照基线（未改）双策略是 +0.001 / +0.007 —— **A1 让生产策略变好（+0.016）、
但第二策略掉到 −0.003（2 端点）**。也就是说：A1 修掉了深逻辑类，但**没有**带来
可交付的 WNS 余量；两策略都仍然贴在 10 ns 墙上，差异全在 ±0.02 ns 噪声带内。
`docs/freeze_checkpoint_20261018.md` 的“双策略均 ≥0”门禁因此**不满足**（差 3 ps）。


A1 的路径级效果：最差类从 `sel_*_o → id_ex/CE`（13 级 / 8 CARRY4 / logic 3.564 ns）
变成 `pc → if/ex_mem 或 dcache CE`（9\~10 级 / 1\~2 CARRY4 / logic \~1.93\~2.11 ns），
**深逻辑类整条消失**，LUT 只多 3 个，六种场景功能/周期完全一致。

A1 的真正价值不是那 +0.009 ns，而是**把“最容易被网表扰动放大成 −0.6 ns 的那一类”删掉了**。
上板接 PS7+AXI 必然重排布局，这一刀是给上板买的保险。

### 5.3 100 MHz 的天花板（实测结论）

A1 之后，四个 floorplan/directive 变体分别 +0.003 / +0.022 / −0.041 / −0.297，
最差路径始终是 `pc → icache tag → … → CE` 这一类（logic ~2 ns、**route ~7.6 ns 占 78%**）。
即：**在不改流水结构的前提下，100 MHz 的余量天花板就是 +0.02 ns 量级**，
再加 IO delay / PS7 后必然翻负。要真正拿到余量只剩两条：

1. `icache` tag 读打一拍（+1 拍取指，换 2~3 ns）—— 所有 cycle benchmark 需重测，与 10-27 冻结冲突；
2. 降频：90 MHz +0.965 / 80 MHz +2.340 / 75 MHz +3.165（同网表实测，cycles/cpb/加速比不变）。

**建议：A1 落地，B/E 不上；100 MHz 只作芯片级存档（A1 + pb2_et = +0.022），
演示与上板频率用 80 MHz。**



每一步都必须跑 `docs/freeze_checkpoint_20261018.md` §2 全套（8 项整机 + 5 单元 + ISA +
双策略时序），加定向 TB：store buffer 转发、load-use、flush 打断 ISE、MMIO 握手。
总工期约 2.5 天 + 回归，**与 10-27 功能冻结冲突**：要做得先决定砍 P1（PYNQ 演示）或 P2(PUF)。

### 并行中的免费尝试（无需改 RTL）——已跑完

`build/synth_margin_variants.tcl`：同一 RTL，改综合选项，实现统一用当前生产策略
（Performance_ExploreWithRemap），结果 `build/reports/synth_margin_20261020/<tag>/`：

| 变体 | 综合设置 | WNS | TNS | 失败端点 | WHS |
|---|---|---|---|---|---|
| `flat_perf` | `FLATTEN_HIERARCHY=full` + `PerformanceOptimized` | **+0.034** | 0.000 | 0 | +0.032 |
| `flat_alt` | `full` + `AlternateRoutability` | −0.470 | −76.011 | 561 | +0.050 |
| `rebuilt_alt` | `rebuilt` + `AlternateRoutability` | 见 `result.txt` | | | |
| 基线 | `rebuilt` + 默认（现生产） | +0.007 | 0.000 | 0 | +0.023 |

`flatten=full + PerformanceOptimized` 把 WNS 从 +0.007 抬到 **+0.034**（约 5 倍），
方向对但量级仍不够；`AlternateRoutability` 是明显劣化。结论：综合选项不是解，
但 `flatten=full` 可以在做 A 的时候一起带上（无功能风险，只是层次被摊平）。


---

## 6. 若不动架构 → 80 MHz

同网表实测：90 MHz +0.965、80 MHz +2.340、75 MHz +3.165 ns，WHS +0.023
（见 [timing_margin_plan](timing_margin_plan.md) §4.4）。cycles/cpb/加速比与频率无关。

## 7. 风险

- store buffer 改变 store→load 可见性时序；必须定向 TB + 全 KAT。
- 旁路决策提前到 id 段，load-use 需要额外的独立性判断；改错会静默破坏 AEAD 结果。
- 任何一步不达标就落到 80 MHz，不带着“余量 7 ps”上板。
