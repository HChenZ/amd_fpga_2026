# 板级 IO 时序签核（XC7Z020 上板工程）

> 2026-11-01 范围：本页是10-27 top_pl_bram/keys 源快照的 IO 约束变体，不是 PUF3 当前签核报告。
> no_input_delay/no_output_delay归零不等于真实板级延迟已测；当前 PUF3 的RO未签核边界仍保留。
> 本页数值/例外不自动转用到 PUF3；版本选择见 version_entrypoints.md，原证据字节不改。

owner TBD。任务：B03（板级 sanity）/ I08（PPA 诚实性）的 IO 门禁补充 —— 给
`board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project` 的板级端口补时序约束，
并做一次**不替换冻结镜像**的签核变体。

本文是证据索引：每个数字都能追到本仓库内的报告文件或命令；估算与实测分开，
未做的一律写 `not_measured`。

---

## 0. 结论（先说清楚能签什么、不能签什么）

| 项 | 结论 | 证据 |
|---|---|---|
| IO 覆盖（`no_input_delay` / `no_output_delay`） | **已归零**（0 / 0） | `build/reports/io_sta_20261027/io/check_timing_summary.txt` |
| 时序收敛（本轮变体） | **WNS 0.152 ns，TNS 0.000，失败端点 0/59513** | 同上目录 `result.txt` |
| DRC | **0 Error**（825 checks，仅 12 条 Warning 类别） | `route_drc.rpt` |
| 与无约束对照组相比的代价 | **0.000 ns**：WNS/TNS/失败端点数/最差路径与对照组逐项相同（+0.152 / 0.000 / 0 / 同一路径） | §6 |
| 板级真实 IO 延迟（CH340C→PL / PL→CH340C） | **not_measured**（无示波器/眼图/环回抖动测量） | §8 |
| 冻结的 3 份 bitstream | **未改动、未重建**（哈希与 `docs/freeze_checkpoint_20261027.md` §3 一致） | sha256 见 §2 |
| 是否可用来替换 P0 镜像 | **不可以**。这是签核变体，布线不同、未上板验证 | §7、§8 |

一句话：**IO 覆盖门禁闭合，芯片内部时序未受影响；板级真实延迟仍是未测项，
不得据此宣称"板级时序已签核通过"。**

---

## 1. 环境与身份

| 项 | 值 | 来源 |
|---|---|---|
| 工具 | Vivado v2025.2（SW Build 6299465 / IP Build 6300035） | 各 run 的 `build_context.txt` |
| part / top | `xc7z020clg400-1` / `top_pl_bram` | 同上 |
| 综合策略 | `Vivado Synthesis Defaults` | 同上 |
| 实现策略 | `Performance_ExploreWithRemap` | 同上 |
| 源文件数 | 50 条 = 45 个 `.v`（`src/rtl` 31 + `src/rtl/ascon` 9 + `src/rtl/keys` 5）+ 5 个 COE 初值文件 | `n_src=50` |
| 约束集 | `const.xdc` + `build/keys_ro_pblock.xdc` + `const_io.xdc`（仅 io 变体） | `constrset_files` |
| opt_design 前置 Tcl | `build/keys_ro_allow_loops.tcl`（承认 256 条 RO 环） | `impl_opt_pre_tcl` |
| BRAM 初值 | `ascon_hw.coe`（P0 的 MMIO 口径） | `coe=…/ascon_hw.coe` |

**源集快照（关键）**：本轮期间并发的 PYNQ/DFX 工作线在 20:04 提交了 `8623ea3`
（改了 `src/rtl/keys/ro_puf_core.v`、`key_mmio.v`）。为保证"变体 vs 对照"是同一套
源，本轮两个最终 run 都跑在**钉住的源快照**上：

- 快照：`build/local/io_sta_20261027/pin_root/src/rtl/`（对照组）与 `build/local/ist_i/src/rtl/`（io 变体），两者同为 `8623ea3` 字节
- 哈希清单：`build/reports/io_sta_20261027/source_hashes_pinned.txt`
- 与首轮快照（19:44，`bd10697`）的差异 = 恰好那 2 个文件（`source_hashes_prebuild.txt` 对比）
- 工程副本：`build/local/io_sta_20261027/pin_root/board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/`
  （对照组）、`build/local/ist_i/board/x/rvp/`（IO 变体，路径短以避开 Windows 260 字符限制）

---

## 2. 输入与产物哈希（sha256）

| 文件 | sha256 |
|---|---|
| `const.xdc`（**未改动**） | `01f639212f00fce073b373a470b559772797842fee9dcd394076499f5fcd42bf` |
| `const_io.xdc`（本轮新增） | `17a41221860473efdcaadf3b74c2e1152723cf3675ab85cf9154e715501b9972` |
| `ascon_hw.coe` | `3e464c482c1da37487371580c977ad1510a745a52010d00b57d9ac504a7d0f61` |
| `build/keys_ro_pblock.xdc` | `12fa358310797d19c80797806cedc0c90a9f01d8116d16598090172810e1dafc` |
| `build/local/board_bitstream/top_pl_bram_sw.bit` | `f4233827e3005e115bb30e31e64a75a4487f9dfdd9efe2946d9c924b8ffb5c2e` |
| `build/local/board_bitstream/top_pl_bram_ise.bit` | `f85eb1a63284059f5dbc785aa791d81c9a6f558a27843c2767d2414909144392` |
| `build/local/board_bitstream/top_pl_bram_hw.bit` | `2f6f24692533941f902deb812cd7a61192a722b20d3f8536e466e46e4579c544` |

镜像口径自检：`blk_mem_gen_0.mif` 第 3 字 `00000000000000000010000110010111` = `0x0000_2197`、
第 4 字 `10000001000000011000000110010011` = `0x8101_8193`，与
`docs/freeze_checkpoint_20261027.md` §7 步骤 4 记录的 `ascon_hw` 指纹一致。

> 说明：并发工作线在本轮期间重建过原工程 `impl_1`（其 `top_pl_bram.bit` 现为
> `87ea8836…`，不是冻结的 `2f6f2469…`），并新增了 `dfx_runtime.txt`。本轮
> **所有构建都在 `build/local/` 下的独立副本里**，与原工程和 PUF 线的 `impl_1` 隔离；
> 归档的三份冻结镜像哈希上表可核对，未被覆盖。

---

## 3. 约束清单与数值来源

文件：`board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/riscv_vivado_project.srcs/constrs_1/new/const_io.xdc`
（新文件，**不改 `const.xdc`**；`const.xdc` 保持 1 个时钟 + 7 个引脚 + reset false_path 原样）

| 端口 | 引脚 | 绑定语义（真正管用的那条） | 形式数值（不参与判定，只为闭合覆盖） | 数值来源 |
|---|---|---|---|---|
| `clk` | U18 | `create_clock -period 20.000`（在 `const.xdc`，未动） | — | 核心板 50 MHz 有源晶振 |
| `uart_rxd` | T19 | `set_false_path -from`（异步输入，2 级同步 + 中点采样） | `set_input_delay -clock uart_bit -max 20.000 -min 0.000` | 见 §3.1 |
| `uart_txd` | J15 | `set_false_path -to`（异步输出） | `set_output_delay -clock uart_bit -max 20.000 -min -20.000` | §3.1，共用同一预算 |
| `led[1:0]` | H15 / L15 | `set_false_path -to`（仅指示灯，无任何要求） | `set_output_delay -clock io_slow -max 20.000 -min -20.000` | 人眼阈值 ~10 ms，比时钟周期宽 6 个数量级 |
| `button[1:0]` | L14 / K16 | `set_false_path -from`（机械按键，2 级同步 + 21 位消抖） | `set_input_delay -clock uart_bit ±(20/0)` | `src/rtl/gpio.v:146-163` |
| `reset_btn` | N16 | `set_false_path -from`（在 `const.xdc`，未动，未重复声明） | `set_input_delay -clock io_slow ±(20/0)` | 异步置位/同步释放，`top_pl_bram.v:24,36-43` |

**为什么每个端口都要两条**：`false_path` 才是与 RTL 一致的语义；`delay` 只是让
`check_timing` 的 `no_input_delay`/`no_output_delay` 归零（Vivado 不因 `false_path`
而豁免这两个计数，实测见 §4.3）。把 delay 全部注释掉，功能与时序结果不变，
只是计数回到 4/3。

### 3.1 uart_rxd / uart_txd 的 20 ns 外部预算怎么来的

| 分项 | 值 | 类型 | 依据 |
|---|---|---|---|
| CH340C TxD 输出/边沿 | ≤ 10.000 ns | **假定** | CH340C 手册无 Tco 指标，按 USB-UART 桥 ns 级边沿取上界 |
| 74LVC1G125 缓冲器 `tpd` | ≤ 4.500 ns | **手册** | Nexperia 74LVC1G125 Rev.17.1（2024-09-03）Table 8：VCC 3.0–3.6 V、−40…+85 °C，max 4.5 ns（−40…+125 °C 为 max 6 ns） |
| 底板走线 ≤ 30 cm × 6.7 ps/mm | ≈ 2.010 ns | **估算** | FR4 εr≈4.2 → ~6.7 ps/mm；底板**没有**走线长度表（核心板才有 `核心板信号走线长度.csv`） |
| 22R/33R 串阻 | 0（只让边沿变缓） | 假定 | 底板原理图 V3.9 |
| **合计（取整上界）** | **20.000 ns** | modeled | 16.51 ns 向上取整 |

链路：`CH340C ─ P5 跳线 ─ 74LVC1G125(U11/U12) ─ PL 引脚`（底板原理图 V3.9）。

### 3.2 位周期算术

```
T_bit    = 1 / 115200 Bd        = 8680.5556 ns   (src/rtl/top.v:10 UART_BPS=115200)
T_bit/2  = 中点采样容差          = 4340.2778 ns
CLK_FREQ = 100 MHz               (src/rtl/top.v:9 UART_CLK_FREQ=100000000；top_pl_bram 不覆盖)
           → 波特计数上限 = 100e6/115200 = 868
T_bit / 20 ns(端口时钟) = 434 倍；T_bit / 10 ns(内部时钟) = 868 倍（约三个数量级）
```

### 3.3 为什么多了两个"虚拟时钟"

`uart_bit = 8680.000 ns`（真实位周期 8680.5556，差 0.556 ns = 0.006%）、
`io_slow = 10 µs`。它们没有源端口（Vivado 报 `Constraints 18-483` INFO，属预期），
只是给"外部器件"一个参考框架，让 IO delay 有物理含义的落点。

> 为什么要取整到 10 ns 的整数倍：**实测**用真实位周期 8680.556 时 Vivado 报
> `TIMING-8 Critical Warning: No common period between related clocks`
> （`build/reports/io_sta_20261027/io_clkframe/methodology.rpt`）。取 8680.000 = 868×10 ns
> 与 `clk_100m` 可公度后该 warning 消失。0.556 ns 对"一位 8.68 µs"的参考框架无意义。

---

## 4. 四种写法都试过：为什么最终形态是 "false_path + 形式 delay"

这一节是本轮最花时间、也最值得留下的部分。**"给异步 IO 编一个 input/output delay
让它变宽松"是错的**，下面每条都用本工程的真实报告验证过。

| 变体 | 参考时钟 | 数值 | `no_input_delay`/`no_output_delay` | 实测时序 | 结论 |
|---|---|---|---|---|---|
| **A**（第一版，任务书原样要求） | 端口 `clk`（20 ns） | in `max 20 / min 0`，out `max 15 / min −5` | 3 / 0 | **WNS −18.481 ns，TNS −5785.882，失败端点 7972/59531** | ✗ 硬失败 |
| **B**（虚拟位时钟，真实位周期） | `uart_bit` 8680.556 | 同上 20 ns | **0 / 0** | `uart_rxd` slack **−17.623**（req 9.444）；`uart_txd` slack **−27.105**（req 0.556） | ✗ 覆盖过了但时序崩 |
| **D**（虚拟时钟取整到网格） | `uart_bit` 8680.000 | 同上 20 ns | **0 / 0** | `uart_rxd` slack **−17.067**（req 10.000）；`uart_txd` slack **−17.661**（req 10.000） | ✗ 仍然不行 |
| **E**（LED 用大 period 虚拟时钟） | `io_slow` 10 µs | out `max 20 / min −20` | **0 / 0** | `led[1]` setup **−13.888**、hold **−18.452**；`led[0]` 同量级 | ✗ 输出侧同样塌 |
| **F = 交付版**（全部端口 false_path + 形式 delay） | 同上 | 同上 | **0 / 0** | 7 个板级端口全部 untimed；最差路径为内部 CPU/DCache 路径 | ✓ |

证据：
- A：`build/reports/io_sta_20261027/io_clkframe/`（`route_timing.rpt`、`check_timing.rpt`、`route_paths.rpt`）
- B/C/D：在**已布线** checkpoint 上重读约束直接跑 STA，不重跑 P&R —
  `build/local/io_sta_20261027/sem3.log`（A 基线 / B / C）、`semD.log`（D）、
  `probe_variantB_timing.rpt`、`probe_variantD_*.rpt`
- E：`build/local/io_sta_20261027/ist.log`、`ist_setup.rpt`、`ist_hold.rpt`
  （`top_pl_bram_physopt.dcp` 上的 `report_timing`，约束 = B/D 版本、LED 走 io_slow+20 ns）
- F：`build/local/io_sta_20261027/final.log`、`final_ct.rpt`（把最终 `const_io.xdc`
  重读到同一 checkpoint：7 个端口全部 untimed，`no_input_delay=0`/`no_output_delay=0`），
  以及交付 run 的报告目录 `build/reports/io_sta_20261027/io/`

### 4.1 机理一：参考时钟选错域，requirement 直接变负

变体 A 最差路径（`route_paths.rpt` 原文数字）：

```
Source:      u_uart_ctrl/u_uart_tx/uart_txd_reg/C   (clocked by clk_out1_clk_wiz_0, 10.000 ns)
Destination: uart_txd                                (output port clocked by clk, 20.000 ns)
Requirement: 10.000 ns   (clk rise@20.000 - clk_out1_clk_wiz_0 rise@10.000)
Data Path Delay: 15.266 ns   Clock Path Skew: 2.084 ns
Slack: -18.481 ns
```

所有板级 IO 触发器都挂在 `clk_100m`（10 ns，`top_pl_bram.v:28-33,107`），
而 `clk` 是 20 ns 的端口晶振。把 IO delay 参考到 `clk`：
- 输入侧：`requirement = 10 − 20 − tsu ≈ −10 ns`；
- 输出侧：还要再吃掉 MMCM 输入→输出的插入延迟差（实测这批路径 −9 ns 里有 ~10 ns 是这个）。

⚠ 关键认知（本轮推翻的直觉）：**负 requirement 的路径在 Vivado 里是"违反"，
不是"恒过"**。input delay 一旦超过采样时钟的周期，路径必然报失败。

### 4.2 机理二：虚拟时钟也救不了，因为 requirement 取的是"最小正边沿对"

- 变体 B：`8680.556 mod 10 = 0.556` → 最坏边沿对只差 0.556 ns → requirement 0.556 ns；
- 变体 D：8680.000 与 10 ns 网格对齐 → 边沿重合，Vivado 取下一个捕获沿 → requirement = 10 ns；
- 变体 E（输出侧，参考 `io_slow` = 10 µs）：同理，最近的捕获沿只差 10 ns
  → `led` setup/hold 双双失败（−13.888 / −18.452 ns）。

**结论：只要 input/output delay 的数值大于捕获时钟周期（本设计 10 ns），换任何参考
时钟都失败** —— 虚拟时钟的周期再大，requirement 也塌到"一个 clk_100m 周期"。
要把 UART 的 4340 ns 容差（≈ 半个位周期）表达出来，只能用**与边沿无关**的约束
（`false_path` 或 `set_max_delay -datapath_only`）。

### 4.3 机理三：false_path 不消 `no_input_delay` / `no_output_delay` 计数

- 只加 `false_path`：`no_input_delay = 4`、`no_output_delay = 3`
  （uart_rxd、button×2、reset_btn / uart_txd、led×2）
  —— `reset_btn` 在 `const.xdc` 里早有 false_path，仍被计数（对照组实测）。
- 同时加 `false_path` + `delay`：计数归零，且路径已退出同步检查 → 无违反。

所以本文件保留两套东西：**false_path 管语义，delay 管覆盖计数**。
把 `const_io.xdc` 里各端口的 delay 注释掉，功能与时序结果不变，只是计数回到 4/3。

---

## 5. 签核判据（本轮 io 变体 vs 同源对照）

两者跑在同一份钉住的源快照上，唯一差别是 `const_io.xdc`：

| 判据 | 要求 | 对照 `noio` | 交付 `io` | 判定 |
|---|---|---|---|---|
| `no_input_delay` | 0 | 4 | **0** | ✓ |
| `no_output_delay` | 0 | 3 | **0** | ✓ |
| `no_clock` | 0 | 10944 | 10944 | ✗ 未达成（PUF/RO 域，见 §10） |
| `unconstrained_internal_endpoints` | 0 | 27312 | 27312 | ✗ 未达成（同上） |
| WNS / TNS | — | WNS 0.152 / TNS 0.000 | **WNS 0.152 / TNS 0.000** | 见 §6 |
| 失败端点数 | 0 | 0/59513 | **0/59513** | ✓ |
| WHS / THS | — | WHS 0.034 / THS 0.000 | **WHS 0.034 / THS 0.000** | ✓ |
| DRC Error | 0 | 0 | **0** | ✓ |
| `TIMING-8`（无公共周期） | 0 | 0 | **0** | ✓ |
| `loops` | 允许（RO 环） | 256 | 256 | ✓（`keys_ro_allow_loops.tcl` 承认） |

报告目录：
- 交付变体：`build/reports/io_sta_20261027/io/`（`check_timing.rpt`、`check_timing_summary.txt`、
  `route_timing.rpt`、`route_paths.rpt`、`route_drc.rpt`、`route_status.rpt`、`cdc.rpt`、
  `clock_interaction.rpt`、`methodology.rpt`、`applied_constraints.xdc`、`clocks.rpt`、`result.txt`、
  `run_state.txt`（报告 ↔ checkpoint 的哈希绑定）、`vivado.log`）
- 同源对照：`build/reports/io_sta_20261027/noio/`（同名文件）
- 被否掉的 A 版：`build/reports/io_sta_20261027/io_clkframe/`
- 早期对照（源集 `bd10697`，因并发提交而作废，仅留档）：`build/reports/io_sta_20261027/noio_rtl_bd10697/`

---

## 6. WNS / TNS 对比与解释

| 版本 | 源集 | IO 约束 | WNS | TNS | 失败端点 | 备注 |
|---|---|---|---|---|---|---|
| P0 三份冻结镜像（`docs/freeze_checkpoint_20261027.md` §4） | keys **之前**（`a323df37…`） | 无 | **+0.087** | 0.000 | 0 | 已上板 |
| keys 阶段 STA（`build/reports/keys_sta_20261025_mmio2`） | keys 集成（`f88e178` 口径） | 无 IO 约束 | +0.023 | 0.000 | 0 | 未上板 |
| 本轮同源对照 `noio` | 钉住 `8623ea3` | 无 | 0.152 | 0.000 | 0 | — |
| **本轮交付 `io`** | 钉住 `8623ea3` | `const_io.xdc` | **0.152** | **0.000** | **0** | 签核变体，未上板 |

**加 `const_io.xdc` 的代价 = 0.000 ns（逐项相同）**：WNS 0.152 → 0.152 ns，TNS 0.000 → 0.000，
失败端点 0 → 0，最差路径同为
`u_cpu_core/id_ex_u/sel_ex_mem_rs1_o_reg/C → u_cpu_core/id_ex_u/func_sel_o_reg[0]/D`，
端点总数同为 59513。两条 run 用同一份钉住的源快照、同一个 COE、同一个实现策略，
唯一差别就是 `const_io.xdc`；因为该文件里 7 个板级端口全部是一条 `false_path`
（路径退出 setup/hold 判定）+ 一条只用于覆盖计数的 delay，
**实现对设计的影响为零**，所以实现结果逐项相同是预期而非巧合。
（注意：两个 run 的 `top_pl_bram_routed.dcp` 字节不同 —— 约束集被嵌进 checkpoint，
XDC 内容不一样 hash 必然不同；这里说的"逐项相同"只指时序指标：WNS/TNS/失败端点数/
最差路径/端点总数。两者的 dcp hash 与 run 收尾状态记在各报告目录的 `run_state.txt`。）

需要说明的边界：`+0.152`（本轮）与 `+0.087`（P0 冻结）、`+0.023`（keys STA 2026-10-25）
之间的差别**不是 IO 造成的**，而是源集不同（P0 早于 PUF/keys 集成）与 P&R 波动；
本轮唯一可归因的对照是上面这一对 run。

**为什么不能把 +0.087 与本轮的差直接归因于 IO**：`+0.087` 来自 keys 之前的源集，
而当前 HEAD 已集成 PUF/密钥子系统（`soc_top.v` 里 `u_puf_key`/`u_key_mmio` 常驻）。
正确的对照只有一个 —— 同一份钉住源快照下加不加 `const_io.xdc`，即上表最后两行。

---

## 7. 为什么这样约束不改变功能

1. **不改 RTL**：本轮没有动 `src/rtl` 任何文件（约束只在 `constrs_1` 里新增一个 XDC）。
2. **不改 `const.xdc`**：引脚、IOSTANDARD、`create_clock`、`reset_btn` 的 false_path 原样。
3. **UART 的位周期比时钟周期大三个数量级**：`T_bit = 8680.56 ns` vs `clk_100m = 10 ns`
   （868 倍）、`clk = 20 ns`（434 倍）。所以任何"约束 UART 引脚何时稳定"的检查都只能是
   宽松量级；`false_path` 更进一步 —— 它把这四个异步端口排除在同步时序判定之外，
   与 RTL 的两级同步器/中点采样是**同一套语义**，不会把异步信号强行当同步信号对待。
4. **没有挤压内部路径**：交付变体里最差路径是内部 CPU 路径
   （`u_soc_axi_top/u_soc_top/u_cpu_core/id_ex_u/sel_ex_mem_rs1_o_reg/C → u_soc_axi_top/u_soc_top/u_cpu_core/id_ex_u/func_sel_o_reg[0]/D`），不是 IO 路径；
   7 个板级端口（uart_rxd/uart_txd/led[1:0]/button[1:0]/reset_btn）全部走 `false_path`，
   不参与 setup/hold 判定（`build/local/io_sta_20261027/final.log` 里逐个端口探针为 `untimed`）。
5. **不产生可烧录镜像**：`impl` 只跑到 `phys_opt_design (Post-Route)`，
   没有 `write_bitstream`。三份冻结 bitstream 的哈希未变（§2）。
6. **BRAM 初值按 P0 口径**（`ascon_hw.coe`，指纹已核）。COE 只影响存储器初始化，
   不影响时序；本轮也没有拿它去烧板。

---

## 8. 未验证 / 不得声称（not_measured）

| 项 | 状态 | 说明 |
|---|---|---|
| 板级真实 IO 延迟（CH340C→PL、PL→CH340C） | **not_measured** | 无示波器、无眼图、无环回抖动测量；20 ns 是建模上界 |
| 底板走线长度/叠层飞行时间 | **estimate** | 底板无走线长度表（核心板有 CSV），按 FR4 ~6.7 ps/mm × ≤30 cm 估 |
| CH340C 输出相位/Tco | **assumed** | 手册无该指标，按 ns 级边沿取 10 ns 上界 |
| 115200 下的实际误码率/裕量 | **not_measured** | 板级功能只按 P0 的 KAT 经验（三套镜像上板通过） |
| 本变体镜像能否上板跑通 | **not_run** | 未生成 bitstream；加约束后布线不同，功能需重新上板验证才能宣称 |
| `no_clock` / `unconstrained_internal_endpoints` 归零 | **未达成** | 见 §10，属 PUF/RO 域，不是 IO 项 |
| 芯片丝印速度等级现场核对 | **not_measured** | 沿用 `-1` 约束（同 `docs/freeze_checkpoint_20261027.md` §8） |

---

## 9. 复现命令

```bash
# 环境：Vivado 2025.2；所有路径用 C:/（MSYS 的 /c/ 会让 vivado.bat 报 Failed to create directory 'C'）

# 1) 交付变体（false_path + 形式 delay）
vivado.bat -mode batch -notrace \
  -log C:/…/build/reports/io_sta_20261027/io/vivado.log \
  -journal C:/…/build/reports/io_sta_20261027/io/vivado.jou \
  -source C:/…/build/build_io_sta.tcl -tclargs io <xpr> <workdir>

# 2) 同源对照组（不加 const_io.xdc）
… -tclargs noio <xpr> <workdir>

# 3) 结果汇总（把 Vivado 报告解析成 result.txt / check_timing_summary.txt，不手填数字）
python build/collect_io_sta_results.py

# 4) 导出 STA 实际吃到的约束
vivado.bat -mode batch -source C:/…/build/collect_applied_constraints.tcl
```

脚本：`build/build_io_sta.tcl`（synth → impl 到 post-route physopt → 报告）、
`build/collect_io_sta_results.py`、`build/collect_applied_constraints.tcl`、
`build/fill_signoff_doc.py`。

踩过的三个坑（都写进脚本注释或本节了）：
- `-tclargs` 必须放在最后，否则 `-log/-journal` 会被当成脚本参数吞掉；
- `write_xdc` 不能写 `-constraints -file …`：Vivado 2025.2 会把 `-constraints` 当带值选项，
  报 `Invalid option value '-file' specified for '-constraints'` 并让 run 以非 0 退出。
  本轮的交付 run 就栽在这一行（**它是脚本最后一步**，前面的 synth/impl/report 全部已成功，
  见 `run_state.txt` 的 `script_tail_error` 说明；`applied_constraints.xdc`/`clocks.rpt`
  随后用 `collect_applied_constraints.tcl` 在同一 checkpoint 上补导）。脚本已修正，
  修正后的语法用 `open_checkpoint` + 该命令实测通过（`build/local/io_sta_20261027/wxd.log`）。
- **工程副本路径不能太长**：Windows 260 字符上限。把工程复制到
  `build/local/io_sta_20261027/pin_root/board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/`
  时，IP 的 OOC 综合会报
  `ERROR: [Common 17-680] Path length exceeds 260-Byte maximum allowed by Windows:
   .../axi_bram_ctrl_0_synth_1/.Xil/Vivado-<pid>-<host>/dcp1/axi_bram_ctrl_0_in_context.xdc`，
  直接 `Failed runs(s): 'axi_bram_ctrl_0_synth_1'`。IO 变体因此放在**短路径**
  `build/local/ist_i/board/x/rvp/`（工程目录名可任意，XPR 内部路径都是相对的；
  但 `$PPRDIR/../../../` 的**层级深度**必须与原工程一致，否则源码解析到错误位置）。
  另外：复制**已跑过 run** 的工程会把 XCI 里的 COE 相对路径带歪，务必从原工程（`xpr`+`.srcs`）复制。

---

## 10. 附带发现（不是 IO 问题，交给 keys/PUF 线）

本轮 `check_timing` 顺带暴露了当前 HEAD 上 PUF/RO 域的覆盖缺口，**与 IO 约束无关**
（对照组一样存在）：

| 现象 | 数量（io 变体 / 同源对照） | 归属 | 证据 |
|---|---|---|---|
| `no_clock` | **10944 / 10944** | 100% 在 `u_soc_axi_top/u_soc_top/u_puf_key/u_puf/*`，根时钟脚 = `ro_clk_div_reg[1]/Q (HIGH)`（被常量折叠成 1），其中 5824 个寄存器/锁存脚直接挂在这条常高时钟上 | `check_timing.rpt` 明细段 |
| `unconstrained_internal_endpoints` | **27312 / 27312** | 同上，PUF/RO 域 | 同上 |
| `TIMING-17` Non-clocked sequential cell | 1000 | PUF/RO 域 | `methodology.rpt` |
| `TIMING-23` / `LUTLP-2` 组合环 | 256 | 有意为之的 RO 环（`src/rtl/keys/ro_unit.v:16`） | `methodology.rpt`、synth 的 100 条 CRITICAL WARNING「found timing loop」 |
| DRC `UTLZ-3` | 4 条 Warning | `pb_ro_puf` 超容：CARRY4 需 1681 > 可用 1470；Slice 需 2707 > 1470 | `route_drc.rpt` |

（早期那份 `bd10697` 对照是 10930 / 27261 —— 差值来自并发提交 `8623ea3` 对
`ro_puf_core.v`/`key_mmio.v` 的改动，同样全部落在 PUF/RO 域，与 IO 无关。）

建议：`ro_clk_div` 被常量折叠、pblock 超容这两条对 RO PUF 的取样功能是实质风险，
应由 PUF/keys 线评估（owner TBD），不要混进 IO 签核结论。

---

## 11. 交付清单

| 文件 | 说明 |
|---|---|
| `board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/riscv_vivado_project.srcs/constrs_1/new/const_io.xdc` | 新增约束（逐条推导注释 + 被否方案留档） |
| `build/build_io_sta.tcl` | 签核变体构建脚本（io / noio） |
| `build/collect_io_sta_results.py` | 报告 → `result.txt` / `check_timing_summary.txt` |
| `build/collect_applied_constraints.tcl` | 导出 `applied_constraints.xdc` / `clocks.rpt` |
| `build/fill_signoff_doc.py` | 把上面两份报告的数字填进本文（避免手抄数字） |
| `build/reports/io_sta_20261027/{io,noio,io_clkframe,noio_rtl_bd10697}/` | 报告与日志（§5 路径） |
| `build/reports/io_sta_20261027/source_hashes_{pinned,prebuild}.txt` | 源集哈希（钉住快照 vs 首轮） |
| `build/local/io_sta_20261027/`, `build/local/ist_i/` | 工程副本（git 忽略，含 runs/checkpoint） |

下一步（建议，owner TBD）：
1. 若要上板验证 IO 约束下的功能，需要另外生成 bitstream 并重跑三套 KAT —— 那会是**第四份**
   镜像，必须单独记录哈希，不得与冻结三份混用。
2. 板级延迟实测（示波器测 T19/J15 相对 PL 引脚，或 UART 环回抖动统计）可把 20 ns 的
   建模上界换成实测值，替换 §3.1 的「假定」行。
3. `no_clock`/`unconstrained_internal_endpoints` 归零属 PUF 线任务（§10）。

---

## 12. 正确性怎么验证、怎么保证

`false_path` 不是"免检"，它是一份**带前提的声明**。所以"正确"要分成三层分别验证，
不能用一个 `no_input_delay=0` 概括。

### 12.1 三层判据

| 层 | 要证明的事 | 验证手段 | 当前状态 |
|---|---|---|---|
| L1 形式覆盖 | 每个板级端口都被"约束过"，check_timing 不再报未约束 | `check_timing` → `no_input_delay`/`no_output_delay` | **0 / 0** ✓（`io/check_timing_summary.txt`） |
| L2 语义前提 | `false_path` 的前提在实现里成立：端口到首级触发器无组合逻辑、同步链真的存在且没被优化/塞进 IOB、采样用的是稳定后的那一级 | 结构探针（`build/local/io_sta_20261027/struct.log`）+ RTL 阅读 | **部分成立**，见 §12.2 |
| L3 物理现实 | 板级真实延迟落在 UART 帧容差内 | 示波器/眼图/环回误码统计 | **not_measured**（§8） |

### 12.2 L2 结构探针（在交付版 `impl_1/top_pl_bram_routed.dcp` 上跑，不重跑 P&R）

| 前提 | 检查结果 | 判定 |
|---|---|---|
| 端口到首级触发器无组合逻辑 | `uart_rxd` 只驱动 `uart_rxd_IBUF_inst/I` | ✓ |
| 首级触发器在 SLICE，未被并进 IOB | `uart_rxd_d0_reg` = `FDCE @ SLICE_X32Y75`；`d1/d2` = `FDCE @ SLICE_X27Y78` | ✓ |
| 同步链没被合并/抽取成 SRL | 两级是独立 `FDCE`，且 `d0/Q` 同时有组合负载（见下行）→ 不满足 SRL 抽取条件 | ✓ |
| **首级输出只供第二级使用** | `uart_rxd_d0_reg/Q` 扇出 **2**：`uart_rxd_d1_reg/D` **和** `rx_flag_i_1/I2` | ✗ **不满足** |
| 采样用稳定后的一级 | `rx_data_t[*] <= uart_rxd_d2`（第 3 级） | ✓ |
| `ASYNC_REG` 属性 | 未设置（属性为空）；`d0` 与 `d1` 相距 5 列 × 3 行 | 最佳实践缺失（影响见 §12.3） |
| 按键同步链 | `key_sync1[*]` Q 扇出仅 1（只到 `key_sync2[*]/D`）；`key_sync1/2` 同 SLICE 放置 | ✓ |

第一条"不满足"来自 RTL 本身：`src/rtl/uart_rx.v:29`
`assign start_en = (!uart_rxd_d0) & uart_rxd_d1 & (!rx_flag);`
—— 起始位检测用的是**第一级** `d0`（尚未消除亚稳态的那一级），且进了组合逻辑
`rx_flag_i_1`。标准写法应比较第二/第三级（`(!uart_rxd_d1) & uart_rxd_d2`）。

**后果是有限的、但必须写清楚**（不能继续用"有两级同步器所以安全"一句带过）：

- 数据位采样走的是 `d2`，不受影响；
- 受影响的是"起始位边沿判定"：`d0` 若正好落在采样窗口（每 10 ns 一个沿，孔径约
  tsu+th ≈ 0.2 ns，约 2% 的到达沿），其输出可能短暂不定，使 `start_en` 晚 1 拍或多判一次；
- 表现为**丢一个字节或一帧错位**，接收机在下一个空闲位重新同步；对控制台是"偶发丢字符"级别，
  不会破坏内部状态机；
- 量化：晚 1 拍 = 采样点偏移 10 ns = 位的 0.12%，相对半位容差 4340 ns 可忽略（见 §12.3）。

建议（**改 RTL 需你确认，本轮未动 `src/rtl`**）：`uart_rx.v:29` 改成
`(!uart_rxd_d1) & uart_rxd_d2 & (!rx_flag)`（同时把第 51/85 行的 `rx_cnt` 起点语义复核一遍）。

### 12.3 L3 之前能给出的定量保证（不是 STA 能给的那部分）

UART 的可靠性不由 STA 判定，由**帧同步预算**决定。本设计的实际数字（可复算，见下方命令）：

| 项 | 值 | 来源 |
|---|---|---|
| 位周期 `T_bit` | 8680.5556 ns | 1/115200 |
| 中点采样容差 | ±4340.2778 ns | `±T_bit/2` |
| PL 侧波特率误差 | **+64 ppm**（+0.0064%） | `BAUD_CNT_MAX = int(100e6/115200) = 868` → 实际 115207.37 Bd |
| 同步+启动判定系统偏移 | ≤ 30 ns（3 个 100 MHz 周期）= 位的 0.35% | `d0/d1/d2` + `start_en` |
| 帧内 10 个位边界的累积漂移 | 接收端时钟误差 0.2% → 179 ns；1% → 874 ns；2% → 1742 ns | 10 × (64 ppm + ε_rx) × T_bit |
| **合计采样偏移 @0.2% 接收端误差** | **209 ns = 半位容差的 4.8% → 余量 20.8×** | 上式相加 |
| 合计 @2%（UART 规范级最坏） | 1772 ns = 40.8% → **余量 2.4×** | 同上 |

2 级同步器 MTBF（`MTBF = exp(t_r/τ)/(T_w·f_clk·f_data)`，τ、T_w 取 **7 系列典型量级**
20–40 ps / 50–200 ps，非器件表征；`f_data` 按 691 kHz 量级估）：

| τ | T_w | MTBF（t_r=9.8 ns） |
|---|---|---|
| 20 ps | 100 ps | ≈ 2.9×10¹⁹² 年 |
| 30 ps | 100 ps | ≈ 3.4×10¹²¹ 年 |
| 40 ps | 100 ps | ≈ 1.2×10⁸⁶ 年 |

结论：**同步器本体不是风险**（即便把 `d0`/`d1` 间距造成的 ~2 ns 走线从 t_r 里扣掉，
MTBF 仍 ≫ 宇宙年龄量级）；`ASYNC_REG` 未设置只影响放置距离这一项，**不构成正确性缺口**，
但建议下次改约束时顺手加上（`set_property ASYNC_REG TRUE [get_cells ...]` 即可，不必改 RTL）。

### 12.4 机器门禁：把"正确"变成可执行判据

`build/check_io_signoff.py` 把本文所有可判定的断言变成脚本（任一条不满足即 exit≠0）：

| 检查 | 内容 | 当前 |
|---|---|---|
| C1 覆盖 | `no_input_delay`/`no_output_delay` 均为 0 | PASS |
| C2 时序 | TNS=0、失败端点=0、WNS≥0 | PASS |
| C3 DRC | `route_drc.rpt` 中 Error 行数 = 0 | PASS（825 checks） |
| C4 时钟 | methodology 中无 `TIMING-8`（无公共周期） | PASS |
| C5 语义 | `applied_constraints.xdc` 仍含 5 条必需 `false_path` | PASS |
| C6 防回归 | 没有任何 IO delay 再引用 `-clock clk`（那正是 §4 的坑） | PASS |
| C7 零代价 | io 变体与同源对照的 WNS/TNS/端点数/总数完全相同 | PASS（0.152/0/0） |

实测输出：`RESULT: PASS (7/7)`，exit 0。**以后任何一次重建或改 `const_io.xdc`，
判据就是这条命令**，而不是"报告看起来没问题"。

复算命令：

```bash
python build/check_io_signoff.py          # C1–C7 门禁
# 结构探针（L2）：见 build/local/io_sta_20261027/probe_sync_structure.tcl + struct.log
```

### 12.5 要把 L3 从 modeled 升级为 measured，需要什么

| 测法 | 能得到什么 | 门槛 |
|---|---|---|
| 示波器：探头打在 PL 引脚（T19/J15）与 CH340C 侧，触发用同一帧的起始位 | `t_co + 走线 + 缓冲器` 的真实值，把 §3.1 的 20 ns 换成实测 | 需要探头与触发条件；20 ns 量级本可用 100 MHz 以上带宽探头 |
| 环回：TX 接 RX（P5 跳线短接），PL 自发自收 N 字节 PRBS，统计误码 | 端到端**裕量结论**（能否在 115200、以及 ±2% 波特率偏差下零误码），给不出 ns | 无需仪器；判据如 10⁸ 字节 0 错 |
| 老化/温度：跑环回同时改变环境温度 | baud 漂移与同步器温度敏感性 | 需要温箱 |

在这三条里，**环回误码统计性价比最高**：它能直接回答"这套 IO 在真实板上带不带得动"，
而示波器那条只回答"延迟是多少 ns"。
