# 扇出复制第二轮：单根/双根定点复制实测（2026-10-25）

> 2026-11-01：10-25独立对照实验记录，不是当前PUF3的复现凭据或新修改授权。
> 原成败与快照保留；当前候选见 version_entrypoints.md。

工具 Vivado 2025.2，part `xc7z020clg400-1`，top `top_pl_bram`，策略
`Performance_ExploreWithRemap`，核心约束 10.000 ns（`clk` 输入 20.000 ns，`clk_wiz_0` ×2）。
RTL 为当前 `src/rtl`（C + D 已落地，`dcache.v`/`cpu_core.v`/`crypto_aead.v` 的 sha256 见各臂
`build_context.txt`）。**实验期间 `src/rtl`、`board/`、XDC 一律未改动**，全部变体都是
`build/local/tests_20261025/<tag>/` 下的副本。owner TBD。

本轮回答的是 `html_v2/rtl.html` R1 节留下的那个问题：**上一轮对 4 根 `sel_*` 网的
`-force_replication_on_nets` 一个副本都没生成，那么"只拆 1~2 根"能不能生成副本？**

---

## 1. 结论先行

1. **一根都拆不出来，而且与选几根、选谁、属性写在哪、MAX_FANOUT 取多少、用哪个 directive 全都无关。**
   8 个臂里凡调用了 `-force_replication_on_nets` 的 6 个，副本数一律 **51 → 51**，FF 一律
   **17187 → 17187**，LUT 一律 13478；日志一字不差是
   `Identified N candidate nets for fanout optimization` → `Optimized 0 net. Created 0 new instance.`
   （N = 1 / 2 / 4）。**单根（页面建议的那个实验）同样被拒。**
2. **上一轮那个 +0.184 与复制毫无关系，它是一个"开关"效应**：只要在 `PHYS_OPT_DESIGN.TCL.POST`
   里调一次 `phys_opt_design -force_replication_on_nets` 并**点到那几根 sel 网**，WNS 就从
   **+0.087 → +0.184**（本轮 6 个臂 + R2C 2 个臂，共 8 次逐位相同）；而**裸 `phys_opt_design`
   （不带 -force 选项）仍是 +0.087**，**把同一句调用点到一根 fo=3 的无关小网上只有 +0.073**。
   收益 0.097 ns，代价 0 副本 / 0 FF / 0 LUT / 0 周期。
3. **机制定位：布局没变，变的是布线。** 两臂的 post-place 检查点里 32579 个原语的 `NAME→LOC`
   **逐行 diff 为空**；布线后只有 35 个单元不同 → +0.097 全部来自**布线解**（同一张布局、同一张净表）。
   属性（`MAX_FANOUT`/`EQREG`）经 `r2_noprop` 证明是空动作；连调两次（`r2_x2`）也不叠加。
4. **sel_\* 不是"复制能解"的墙**。+0.184 网表里新最差是
   `id_ex_u/sel_ex_mem_rs1_o_reg → u_if_id/pred_target_o_reg[12]/D`：
   **13 级逻辑、logic 3.520 ns、net 5.808 ns（62%）**，其中 8 级是 CARRY4 串起来的
   32 位地址增量链（`u_mem_wb/captured_addr_reg[*]_i_1/CO` 竖向 X57Y33→Y39），
   单根网的走线只占 0.955 ns。**复制一根 172 扇出的使能位解决不了 8 级进位链。**
5. `-force_replication_on_nets` **不允许在 post-route 阶段使用**（本轮 preflight 实测报
   `ERROR: [Vivado_Tcl 4-265] Option -force_replication_on_nets is specified but not supported yet
   for post-route physical synthesis`），所以这个杠杆只能在 `PHYS_OPT_DESIGN.TCL.POST`（放置后、布线前）用。

---

## 2. 实现矩阵（8 臂，同一轮、同一台机、全部 10 ns）

| tag | 钩子做什么 | WNS | 失败端点 | WHS | 副本 | 最差路径 |
|---|---|---|---|---|---|---|
| `r2_ctl` | 无（生产策略对照） | **+0.087** | 0 | +0.021 | 51 | `state[3] → p12_in_reg[215]/D`，9.870 / net 9.290 / 1 级 |
| `r2_popt` | 裸 `phys_opt_design`，不写属性、不指定网 | **+0.087** | 0 | +0.021 | 51 | 同上（逐位相同） |
| `r2_net1` | **只 1 根** `sel_ex_mem_rs1_o`（fo=172），`MAX_FANOUT 128` 写在**网**上 + force | **+0.184** | 0 | +0.021 | 51 | `sel_ex_mem_rs1_o_reg → pred_target[12]/D`，9.328 / 13 级 |
| `r2_net2` | 2 根（rs1/rs2），属性写在网上 + force | **+0.184** | 0 | +0.021 | 51 | 同上 |
| `r2_net1_cell` | 只 1 根，`MAX_FANOUT 128` 写在**驱动单元**上 + force | **+0.184** | 0 | +0.021 | 51 | 同上 |
| `r2_all4_cell` | 4 根（去别名后 4 个 parent net），属性写在单元上 + force | **+0.184** | 0 | +0.021 | 51 | 同上 |
| `r2_net1_aggr` | 1 根，单元属性 + 先 `-directive AggressiveExplore` 再 force | **+0.184** | 0 | +0.021 | 51 | 同上 |
| `r2_net1_mf16` | 1 根，单元 `MAX_FANOUT 16`（172 负载 → 要求 ≈11 份）+ AggressiveExplore + force | **+0.184** | 0 | +0.021 | 51 | 同上 |

- **两极化、无中间值**：0.087 组的最差路径是 `state[3]`，0.184 组的最差路径是 `sel_*`；
  每组内部逐位相同（`route_paths.rpt` 前 5 条的 slack、起点、终点完全一致）。
- 资源三方一致：都是 LUT **13478** / FF **17187** / 副本 **51** → **没有生成任何新单元**；
  布线后四根 `sel_*` 网的扇出仍是 **172 / 141 / 172 / 140**（各臂 `result.txt` 的 `NET fo=` 行），
  **一根网都没有被拆开** —— 这是"复制根本没发生"最直接的一条读数。
- 0.184 组里 `state[3] → p12_in` 那条从 +0.087 抬到 **+0.284**，`sel_*` 那族也在 +0.184~+0.289 ——
  也就是说**整张网表的布线解都变好了一档**，不是单条路径被修好。

---

## 3. 为什么一根副本都生成不出来（日志原文）

以 `r2_net1` 为例（`build/local/tests_20261025/logs/r2_net1.log`）：

```
Command: phys_opt_design -force_replication_on_nets .../id_ex_u/sel_ex_mem_rs1_o
INFO: [Vivado_Tcl 4-166] ...                       <- 网络别名折叠（仅 R1 的 12 别名臂会打）
Phase 1 Physical Synthesis Initialization
INFO: [Physopt 32-619] Estimated Timing Summary | WNS=0.000 | TNS=0.000
Phase 2 Fanout Optimization
INFO: [Physopt 32-76] Pass 1. Identified 1 candidate net for fanout optimization.
INFO: [Physopt 32-232] Optimized 0 net. Created 0 new instance.
INFO: [Physopt 32-775] End 1 Pass. Optimized 0 net or cell. Created 0 new cell, deleted 0 existing cell and moved 0 existing cell
```

`-force_replication_on_nets` 的作用只是**把那几根网塞进候选清单**（"Identified N candidate nets"），
真正决定要不要实例化副本的是 Phase 2 的扇出优化判据。这个判据在 128 与 16 两个 MAX_FANOUT 提示下、
在 `AggressiveExplore` 下、在 1 根与 4 根两种规模下**一致地判"不值得"**。

两条对照事实说明这不是我们选错了对象：
- 同一个钩子位置，对 `u_crypto_aead/state[3]`（fo=628）做同样的事，扇出会真的从 628 掉到 25
  （`prod_rep1`：fo 628 → 25，单根 9.29 ns 的走线从关键路径上消失）。
- 所以差别不在"调用方式"，而在**这两类网的负载几何**：`sel_*` 的 172 个负载基本落在同一片区域里，
  复制副本省下的走线还不够补偿新增负载的布局扰动。
  <span>（**推算，未验证**：没有导出 172 个负载的坐标分布去量化"集中度"。）</span>

### 3.1 R1 那 12 个对象 = 4 根网

`pr_rep2_sel` 的日志里 Vivado 自己打了 8 行：

```
INFO: [Vivado_Tcl 4-166] Using parent net '.../id_ex_u/sel_ex_mem_rs1_o' of the net '.../ex_sel_ex_mem_rs1'
INFO: [Vivado_Tcl 4-166] Using parent net '.../id_ex_u/sel_ex_mem_rs1_o' of the net '.../u_mem_wb/sel_ex_mem_rs1_o'
（rs2 / mem_wb_rs1 / mem_wb_rs2 同样各 2 行）
```

所以上一轮的 `candidates=12` 只是 4 根网的 3 层别名。本轮 `r2_all4_cell` 用 4 个 parent net
重跑，`candidates=4`、结果与 12 别名臂**逐位相同**（+0.184）——**别名不是原因，可以正式排除**。

### 3.2 属性写在哪也没关系

`MAX_FANOUT` 写在网上（`r2_net1`）、写在驱动单元上（`r2_net1_cell`）、取 128 或 16，
`route_paths.rpt` 与 `result.txt` 全部逐位相同。**"属性对象写错"这个假设也被排除。**

---

## 4. +0.097 到底是什么

### 4.1 事实：二值开关，与复制无关

| 动作 | 臂 | 结果 |
|---|---|---|
| 什么都不做 | `r2_ctl` / `prod_ctl` / `pr_ctl` / `pr_ctl2` / `d_100`（5 次） | +0.087，逐位相同 |
| 只写属性、不调用 | `pr_selprops` | +0.087，逐位相同 |
| 只调用裸 `phys_opt_design` | `pr_physopt_only` / `pr_physopt_b` / `r2_popt`（3 次） | +0.087，逐位相同 |
| `phys_opt_design -force_replication_on_nets <sel_* 网>`（写不写属性都行） | R1 的 2 次 + R2 的 6 次 | **+0.184**，逐位相同 |

**8 次逐位复现**，且副本 0 / FF 0 / LUT 0 —— 净表没变，收益不可能来自"复制"。

### 4.2 布局没变，变的是布线

`build/timing_tests/probe_place_cmp.tcl` 把两臂的 **post-place** 与 **post-route** 检查点的
每个原语 `NAME → LOC` 全部导出（各 32579 个原语）后逐行 diff：

- **`ctl_placed.txt` vs `net1_placed.txt`：diff 为空** —— 放置后布局逐单元完全相同；
- `ctl_routed.txt` vs `net1_routed.txt`：只有 **35 个单元** 不同（`diff` 70 行 = 35 进 35 出），
  分散在 `u_ascon_ise` / `u_dcache` / `u_csr_file` / `u_if_id` / `u_mem_wb`，是布线后 phys_opt 挪的。

→ **+0.097 完全来自布线解**：同一张布局、同一张净表，布线器落进了另一个（更好的）解。
物理上自洽的解释是那次 `phys_opt_design` 重算了 post-place 的时序/负载估计
（日志里 `Estimated WNS 0.247 → 0.000` 就是这个重算），布线器的关键性排序随之改变；
**但这是解释，不是证据** —— 我们没导出布线器的 net criticality 列表。

### 4.3 R2C：谁必需、谁无关（4 臂）

| tag | 钩子做什么 | WNS | 副本 | 判定 |
|---|---|---|---|---|
| `r2_noprop` | 4 根 sel 网 + `-force` 调用，**一个属性都不写** | **+0.184** | 51 | **属性不是必需**（`MAX_FANOUT`/`EQREG` 全是空动作） |
| `r2_tiny` | 只对一根 **fo=3** 的无关小网 `-force` 调用 | **+0.073** | 51 | **选点有关**：点错网不会得到 +0.184，甚至比对照差 0.014；新墙换成 `pc_reg[6] → inst_o_reg[6]/D`（10 级），是另一个更差的盆 |
| `r2_x2` | 1 根 + 属性 + **连调两次** | **+0.184** | 51 | **不叠加**：一次就到顶，第二次是空动作 |
| `r2_tight` | 不写属性不复制，把 `clk` 临时收紧到 18 ns（核心 9 ns）跑一次 `AggressiveExplore`，再恢复 20 ns | **+0.057** | 52 | 真给压力也没赢：phys_opt 确实动手了（Fanout 相位 TNS +57.529、新增 13 单元、optimized 7），恢复 10 ns 后估计 WNS +0.247 → **+0.709**，但**布线后只有 +0.057**，且 LUT 13478 → **13565（+87）**、FF 17187 → **17235（+48）**；新墙换成 `rs1_o_reg[7] → stall_inst_reg_reg[11]/CE`（13 级） |

三条合并起来的结论：
- 开关是「**`phys_opt_design -force_replication_on_nets` + 点到那几根宽且靠近关键路径的网**」，
  两个条件缺一不可；属性、次数、directive、MAX_FANOUT 值都无关。
- 它**不是**"复制带来的收益"，也**不是**"随便多跑一次 pass 带来的收益"（`r2_popt` = +0.087，
  `r2_tiny` = +0.073）—— 它是一次**定向扰动**，把布线解推到更好的盆地里。
- 因为净表不变、布局不变，**功能与周期上没有任何代价**（网表等价变换，不触及 RTL）。
- **给 phys_opt 真实压力（`r2_tight`）不如这个开关**：+0.057 且多 87 LUT / 48 FF。
  顺带一个警告：phys_opt 恢复约束后自报的"估计 WNS"是 **+0.709**，而布线后实测只有 **+0.057** ——
  **估计值不能当结论用**（这也解释了为什么生产策略里它自报 +0.247 时直接跳过了整段优化）。


---

## 5. 结论与遗留问题

本轮四个问题全部有答案：**单根拆不出来（0 副本）/ +0.184 与复制无关（是布线解换盆）/
属性与次数无关 / 给压力只会 +0.057 且多花 87 LUT**。

仍然没解决、留给下一轮的：

1. **+0.184 的机制只有排除法证据**（布局逐单元相同、净表相同 → 只能是布线解），
   没有布线器 net criticality 的直接证据。要拿直接证据得导出 `route_design -directive` 前的
   criticality 列表或对比 `report_design_analysis` 的 congestion 变化。
2. **换 RTL 必须重测**：`r2_tiny`（+0.073）已经证明这不是"必然变好"，它依赖点到哪几根网。
   F 补丁那版、以及将来任何 RTL 改动后，这 0.097 都要重新确认。
3. **新墙是 13 级里的 8 级 CARRY4 增量链**（`captured_addr_reg[*]_i_1`），
   这是 RTL/综合层的加法器结构问题，不是复制问题。谁改、怎么改（`owner TBD`）还没定。
4. 全套功能回归（`docs/freeze_checkpoint_20261018.md` §2）未跑。理论上净表逐位相同 + 副本 0，
   风险为 0，但**没跑就是没跑**。

---

## 6. 落地建议（按证据强度排序）

1. **"放置后加一次焦点 phys_opt"值得作为独立实现入口固化**：0 副本、0 面积、0 周期、
   同一流程 8 次逐位复现 +0.184。但它把 `sel_*` 顶成了新墙（13 级 / 8 级进位链），
   所以它是"把余量从 0.087 抬到 0.184"，不是"解决 sel"。
2. **不要再去拆 sel_\***：单根、双根、四根、写网上、写单元上、MF=16/128、AggressiveExplore，
   全部 0 副本。这条路线到此为止。
3. **也不要用"临时过约束逼 phys_opt"这条路**（`r2_tight`：+0.057、+87 LUT、+48 FF），
   它的自报估计（+0.709）与实测差 0.65 ns，不可信。
4. **下一步该看的是 13 级路径里的 8 级 CARRY4**（`u_mem_wb/captured_addr_reg[*]_i_1` 的 32 位增量链，
   0.114 ns × 8 + 末端 0.988 ns 的 `dcache_cpu_addr[29]` 走线）。这是结构问题（RTL/综合的加法器拆法），
   不是复制问题 —— 属于 R1 页面"如果复制无效，RTL 侧只有这一条真办法"的同一类，但落点不同。
5. 冻结版取舍：+0.087 是 5 次逐位复现的稳定值；+0.184 的**数字**同样稳定（8 次），但**机制**未定论。
   建议按 `docs/freeze_checkpoint_20261018.md` §2 的回归流程决定是否进冻结版。

---

## 7. 复现

```bash
# 8 臂主矩阵（约 22 min，8 个并发）
bash build/timing_tests/run_batchR2.sh
# 4 臂机制隔离
bash build/timing_tests/run_batchR2C.sh
# 汇总（直接读 result.txt 与日志）
python build/timing_tests/collect_r2.py
```

- 入口脚本：`build/timing_tests/run_rep2.tcl`（`-tclargs <tag> <clk_in_ns> <ctl|hook> <hook.tcl>`）
- 钩子：`build/timing_tests/hooks/r2_*.tcl`（R2 波次）、`hooks/r2c_*.tcl`（R2C 波次）；
  共用 `build/timing_tests/r2_lib.tcl`。**钩子文件必须纯 ASCII** —— Vivado 用平台编码读
  TCL.PRE/POST 文件，非 ASCII 注释会把包围的 braced string 撑坏（2026-10-25 教训）。
- 钩子必须**原地挂**（`STEPS.PHYS_OPT_DESIGN.TCL.POST` 指向 `build/timing_tests/hooks/` 里的文件），
  不要拷进 run 目录：钩子用 `[file dirname [info script]] .. r2_lib.tcl` 找库里，拷走就断链。

## 8. 证据路径

```
build/local/tests_20261025/<tag>/            # 工程副本、development_rtl、*_routed.dcp
build/local/tests_20261025/logs/<tag>.log    # phys_opt 判据原文、R2 钩子打印
build/reports/tests_20261025/<tag>/          # result.txt / route_paths.rpt / route_timing.rpt / high_fanout.rpt
build/timing_tests/logs/preflight.log        # -force_replication_on_nets 在 post-route 被拒的证据
build/timing_tests/{run_rep2.tcl,r2_lib.tcl,run_batchR2.sh,run_batchR2C.sh,collect_r2.py}
build/timing_tests/hooks/{r2_popt,r2_net1,r2_net2,r2_net1_cell,r2_net4_cell,r2_net1_aggr,r2_net1_mf16}.tcl
build/timing_tests/hooks/{r2c_noprop,r2c_tiny,r2c_x2,r2c_tight}.tcl
```
