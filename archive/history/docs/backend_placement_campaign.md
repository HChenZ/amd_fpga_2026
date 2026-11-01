# 后端战役：控制锥复制 + 依赖驱动 floorplan + 疏松布局（2026-10-21 夜间）

> 2026-11-01：历史布局/路由战役，非当前PUF3候选或上板结果。保留当时的源/COE/策略，不套用其周期或WNS。
> 当前入口见 version_entrypoints.md，不自动继续扫掠或覆盖他人工程。

owner TBD。**不改 RTL、不改 baseline XDC/工程、不 commit**（`git status` 只多出
`build/backend_opt_20261021/`、`build/reports/backend_opt_20261021/` 与本文件）。
所有实验从同一张已验收网表出发：

```
build/local/timing_acb_impl/riscv_vivado_project.runs/acb_remap/top_pl_bram_opt.dcp
```

即 HEAD `3c6f134` 生产策略（+0.007 ns）的 post-opt 快照，携带 clk 20 ns /
clk_out1 10 ns 三个时钟、IP 已 stitching、零黑盒、8/31461 单元已布局。

> 注意：同目录 `synth_1/top_pl_bram.dcp` **不能**用作起点——它没有约束（`get_clocks` 为空）
> 且 clk_wiz / blk_mem_gen / axi_bram_ctrl 三个 IP 是黑盒（`opt_design` 会以 DRC INBB-3 失败）。

## 1. 用户要的三件事，以及实测到的物理现实

1. **复制同义寄存器、把控制锥本地化**；
2. **按依赖强度摆模块**（强依赖靠近、弱依赖分开放远）；
3. **布局尽量疏松**，从后端而非 RTL 找时序余量。

先把"控制锥有多大"量出来（`report_high_fanout_nets`，`recon/high_fanout.rpt`）：

| 网络（驱动） | 扇出 | 负载 | 该网自身最差裕量 | 该网延时 |
|---|---|---|---|---|
| `u_ascon_mmio/rst_sync_reg[2]` | **9657** | 全部 Set/Reset | +0.907 | **7.091 ns** |
| `ascon_mmio/.../p12_inst/SR[0]` | 3989 | 全部 CE | +2.537 | 4.739 |
| `ex_stage/u_ascon_ise/u_p12/SR[0]` | 1280 | 全部 CE | +2.779 | 3.916 |
| `ex_stage/u_ascon_ise/mode_p12_reg_n_0` | 661 | 数据/CE | +1.619 | **7.550** |
| `ascon_mmio/.../crypto_aead/state[3]` | 627 | 数据 | +1.699 | 1.297 |
| `dcache/bus_addr_r_reg[2]_1` | 457 | 数据 | +0.549 | 2.247 |

**关键点：这些巨型锥的自身裕量是 +0.9 ~ +2.8 ns，它们不是时序墙。** 全设计 1633 条
≥128 pin 的非时钟网络，把它们复制会花面积和布局自由度，但不会把墙推走（§4.1 实测）。

再量"依赖强度"（`dep_analysis.py`，14161 条 <2.0 ns 路径）：

| 起点模块 | 终点模块 | 路径数 | 最差裕量 | 结论 |
|---|---|---|---|---|
| dcache | ascon_mmio | 8858 | **+0.525** | 量大但裕量足 → 可以分开 |
| ascon_mmio | ascon_mmio | 2068 | +0.108 | 自己的墙 → 独占区域 |
| if_stage | ascon_ise | 647 | +0.145 | ISE 在 EX 内 → 必须同区 |
| id_ex | dcache | 401 | **+0.007** | 当前 WNS 家族 → 必须同区且紧凑 |
| id_ex | id_ex | 307 | +0.034 | 同上 |
| id_ex | if_id | 165 | +0.178 | 同上 |
| icache | id_ex | 107 | +0.197 | 同上 |

实际布局（同一张网表）：`u_cpu_core` X32..106 / Y0..113，`u_dcache`
**X35..106 / Y3..113（纵向拉成 110 行）**，`u_ascon_mmio` X27..99 / Y26..120 与 CPU 交织。
器件只有 X0..113 × Y0..149、6 个时钟区域（`recon/clock_regions.csv`）。

约束：CPU 逻辑最小面积约 2500 slice，而器件总共 13300 slice —— **想把 CPU 压成
50×50 的方块等于 100% 密度，不可能**；它能做到的"紧凑"上限就是大半个时钟区域。
这条硬约束决定了 floorplan 的天花板。

## 2. 实验装置

`build/backend_opt_20261021/`：

| 文件 | 作用 |
|---|---|
| `run_variant.tcl` | 一个臂一个进程：open post-opt DCP → 打属性 → `opt_design Explore` → (pblock) → `place_design` → 定向复制 → `phys_opt_design` → `route_design` → `phys_opt_design` → 报告 + `result.txt` |
| `run_wave.sh` | 并行波次launcher，每臂独占工作目录（Vivado 默认日志不互相覆盖），结果追加 `results.tsv` |
| `floorplan.py` | 由依赖强度生成 pblock 脚本（fp2 / fp3 / fpc） |
| `dep_analysis.py` | 模块级依赖矩阵、强耦合对、relief 依据 |
| `summarize.py` | 汇总排名表（`build/reports/backend_opt_20261021/summary.md`） |
| `fanout_compare.py` | 逐网络对比各臂的扇出拆分（复制到底有没有发生） |
| `probe_*.tcl` | 扇出/几何/布局/pblock 是否真的生效/时序墙分布 |

### 2.1 复制与"system attribute"

- 选网：`get_nets -filter {FLAT_PIN_COUNT >= N}`，按驱动 pin 去重，排除
  BUFG/BUFR/BUFH/MMCM/PLLE/PS7 驱动的时钟网 → 每个臂实际命中 33~64 条网络
  （`VARIANT ... wide_nets=33 minpins=256 applied=33/33`）；
- `set_property MAX_FANOUT <N> [get_nets ...]`；驱动单元
  `set_property EQUIVALENT_REGISTER_REMOVAL NO`（**禁止 opt_design 把副本合并回去**）；
- 布局后与布线后各跑一次 `phys_opt_design -force_replication_on_nets <这些网>`；
- **定向复制**（`crep N`）：只取布局后最差 N 条路径终点的 CE pin，复制这些使能锥的驱动
  （`crit_ce_nets`），不碰与失败路径无关的 1600 条宽网。
- 两个对照臂把"复制本身"和"属性本身"分开：
  `rep256_nofrn`（只给 `MAX_FANOUT` + `EQUIVALENT_REGISTER_REMOVAL=NO`，不加
  `-force_replication_on_nets`）与 `rep256_noeq`（强制复制但不加
  `EQUIVALENT_REGISTER_REMOVAL`）。实测见 §4.1。

### 2.2 floorplan

| tag | pb_cpu | pb_crypto（ascon_mmio） | pb_sys（总线/外设） |
|---|---|---|---|
| `fp2` | X0..113 / Y0..49（5700 slice） | 并入 pb_rest | X26..113 / Y50..149（10000） |
| `fp3` | X0..113 / Y0..49（5700） | X50..113 / Y50..149（5200） | X26..49 / Y50..149（2400） |
| `fpc` | X0..49 / Y0..149（4900，列向切分） | 并入 pb_rest | X50..113 / Y0..149（8400） |

IO/时钟/BRAM/DSP 单元不进 pblock（区域里没有对应 site 时不会让 place 失败）。
`add_cells_to_pblock` 只给层次单元，子单元自动继承（实测 pb_cpu 覆盖 10404 个 leaf）。

### 2.3 "疏松"

- `place_design` **没有** `-place_density` 选项；pblock 上 `PLACE_DENSITY` 在 2025.2
  直接报 `Netlist 29-177 property does not exist`（`fp3_loose` 因此失效，已把该写回改成
  受 `catch` 保护的 no-op）；
- 真正可用的"疏松/散开"是放置 directive：`AltSpreadLogic_medium/_low/_high`
  （"Spreads logic throughout the device to avoid congestion"）与
  `ExtraNetDelay_high`（放置阶段就为高扇出网络加延时权重）。

## 3. 结果总表

共 41 条测量：**35 个布局/复制臂**（同一张 post-opt DCP 出发布局布线）+ **5 个 `hf_*`**（冠军网表上的布线后 hold 修补臂，见 §4.7，全部 0 变化）+ **1 个 `hfp_split_near`**（hold 导向 floorplan，见 §4.7）。
完整表格亦见 `build/reports/backend_opt_20261021/summary.md`（`hf_*` 行的旋钮列为 `-`，
因为它们不是从 post-opt DCP 重跑的实现，而是对冠军 routed DCP 的修补尝试）。

| # | variant | WNS | Δctl | TNS | fail | WHS | LUT | FF | rep | place | popt | route | fp | dens | worst path (start → end) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `hf_aggr` | +0.138 | +0.240 | 0.000 | 0 | +0.017 | 11690 | 16042 | - | - | - | - | - | - | - → - |
| 2 | `hf_aggr_both` | +0.138 | +0.240 | 0.000 | 0 | +0.017 | 11690 | 16042 | - | - | - | - | - | - | - → - |
| 3 | `hf_clock` | +0.138 | +0.240 | 0.000 | 0 | +0.017 | 11690 | 16042 | - | - | - | - | - | - | - → - |
| 4 | `hf_clock_hold` | +0.138 | +0.240 | 0.000 | 0 | +0.017 | 11690 | 16042 | - | - | - | - | - | - | - → - |
| 5 | `hf_explore` | +0.138 | +0.240 | 0.000 | 0 | +0.017 | 11690 | 16042 | - | - | - | - | - | - | - → - |
| 6 | `pl_ndh_crit200_ntr` | +0.138 | +0.240 | 0.000 | 0 | +0.017 | 11690 | 16042 | 45 | ExtraNetDelay_high | AggressiveExplore | NoTimingRelaxation | - | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ...u_core/id_ex_u/rs1_o_reg[14]/CE |
| 7 | `pl_ndh_crit200_ntr_dup` | +0.138 | +0.240 | 0.000 | 0 | +0.017 | 11690 | 16042 | 45 | ExtraNetDelay_high | AggressiveExplore | NoTimingRelaxation | - | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ...u_core/id_ex_u/rs1_o_reg[14]/CE |
| 8 | `pl_ndh_crit120_ntr` | +0.117 | +0.219 | 0.000 | 0 | +0.022 | 11681 | 16042 | 45 | ExtraNetDelay_high | AggressiveExplore | NoTimingRelaxation | - | - | ...cpu_core/u_if_stage/pc_reg[4]/C → ...ge/u_ascon_ise/state_reg[187]/D |
| 9 | `pl_ndh_crit200` | +0.074 | +0.176 | 0.000 | 0 | +0.017 | 11691 | 16042 | 45 | ExtraNetDelay_high | AggressiveExplore | AggressiveExplore | - | - | .../id_ex_u/sel_mem_wb_rs1_o_reg/C → ...cpu_core/u_dcache/lru_reg[14]/D |
| 10 | `pl_ndh_crit60` | +0.068 | +0.170 | 0.000 | 0 | +0.022 | 11673 | 16042 | 45 | ExtraNetDelay_high | AggressiveExplore | AggressiveExplore | - | - | ..._icache/data_way0_reg/CLKARDCLK → ...id_ex_u/sel_ex_mem_rs1_o_reg/CE |
| 11 | `pl_ndh_crit` | +0.030 | +0.132 | 0.000 | 0 | +0.017 | 11655 | 16033 | 36 | ExtraNetDelay_high | AggressiveExplore | AggressiveExplore | - | - | ...cpu_core/u_if_stage/pc_reg[5]/C → ...e/u_ascon_ise/state_reg[262]/CE |
| 12 | `pl_ndh_crit_prod` | +0.030 | +0.132 | 0.000 | 0 | +0.017 | 11655 | 16033 | 36 | ExtraNetDelay_high | Explore | AggressiveExplore | - | - | ...cpu_core/u_if_stage/pc_reg[5]/C → ...e/u_ascon_ise/state_reg[262]/CE |
| 13 | `fp3` | +0.017 | +0.119 | 0.000 | 0 | +0.023 | 11702 | 16033 | 60 | Default | AggressiveExplore | AggressiveExplore | fp3 | - | ...cpu_core/u_if_stage/pc_reg[4]/C → ...ge/u_ascon_ise/state_reg[20]/CE |
| 14 | `pl_ndh` | +0.017 | +0.119 | 0.000 | 0 | +0.017 | 11652 | 16033 | 60 | ExtraNetDelay_high | AggressiveExplore | AggressiveExplore | - | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ...cpu_core/u_dcache/lru_reg[25]/D |
| 15 | `prod_place` | +0.016 | +0.118 | 0.000 | 0 | +0.010 | 11689 | 16033 | 36 | Explore | Explore | AggressiveExplore | - | - | .../u_ex_mem/ex_rd_data_o_reg[5]/C → ...dcache/data_way1_reg_2/DIADI[4] |
| 16 | `pl_ndh_ntr` | +0.010 | +0.112 | 0.000 | 0 | +0.017 | 11655 | 16033 | 36 | ExtraNetDelay_high | AggressiveExplore | NoTimingRelaxation | - | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ...cpu_core/u_dcache/lru_reg[33]/D |
| 17 | `fp2` | +0.007 | +0.109 | 0.000 | 0 | +0.008 | 11687 | 16033 | 36 | Default | AggressiveExplore | AggressiveExplore | fp2 | - | .../id_ex_u/sel_mem_wb_rs1_o_reg/C → ...re/u_dcache/valid_way0_reg[2]/D |
| 18 | `fp2_ndh` | +0.007 | +0.109 | 0.000 | 0 | +0.015 | 11720 | 15986 | 36 | ExtraNetDelay_high | AggressiveExplore | AggressiveExplore | fp2 | - | ...ore/id_ex_u/csr_addr_o_reg[4]/C → ...dcache/data_way0_reg_2/DIADI[3] |
| 19 | `pl_ndh_crit300_ntr` | +0.003 | +0.105 | 0.000 | 0 | +0.022 | 11697 | 16042 | 45 | ExtraNetDelay_high | AggressiveExplore | NoTimingRelaxation | - | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → .../id_ex_u/sel_mem_wb_rs1_o_reg/D |
| 20 | `pl_spread` | +0.002 | +0.104 | 0.000 | 0 | +0.014 | 11685 | 16033 | 36 | AltSpreadLogic_medium | AggressiveExplore | AggressiveExplore | - | - | ...cpu_core/u_if_stage/pc_reg[5]/C → ...e/u_ascon_ise/state_reg[234]/CE |
| 21 | `ctl_ntr` | +0.001 | +0.103 | 0.000 | 0 | +0.010 | 11690 | 16033 | 36 | Default | AggressiveExplore | NoTimingRelaxation | - | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ...dcache/data_way1_reg_1/DIADI[7] |
| 22 | `pl_ndh_crit200_prod` | +0.001 | +0.103 | 0.000 | 0 | +0.020 | 11706 | 16040 | 43 | ExtraNetDelay_high | Explore | AggressiveExplore | - | - | ...cpu_core/u_if_stage/pc_reg[4]/C → ...e/u_ascon_ise/state_reg[108]/CE |
| 23 | `pl_spread_lo` | -0.027 | +0.075 | -0.084 | 6 | +0.012 | 11728 | 16033 | 36 | AltSpreadLogic_low | AggressiveExplore | AggressiveExplore | - | - | .../id_ex_u/sel_ex_mem_rs2_o_reg/C → ...u_core/id_ex_u/rs1_o_reg[31]/CE |
| 24 | `pl_ndh_crit120` | -0.039 | +0.063 | -0.077 | 4 | +0.022 | 11685 | 16042 | 45 | ExtraNetDelay_high | AggressiveExplore | AggressiveExplore | - | - | .../id_ex_u/w_reg_waddr_o_reg[0]/C → ...dcache/data_way0_reg_1/DIADI[3] |
| 25 | `fp3_prod` | -0.061 | +0.041 | -0.353 | 13 | +0.019 | 11698 | 16033 | 36 | Explore | Explore | AggressiveExplore | fp3 | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ...re/u_dcache/valid_way0_reg[2]/D |
| 26 | `fpc` | -0.065 | +0.037 | -0.619 | 16 | +0.043 | 11715 | 16033 | 36 | Default | AggressiveExplore | AggressiveExplore | fpc | - | .../id_ex_u/sel_mem_wb_rs1_o_reg/C → ...dcache/captured_addr_reg[28]/CE |
| 27 | `rep128` | -0.074 | +0.028 | -0.795 | 18 | +0.010 | 12356 | 16264 | 919 | Default | AggressiveExplore | AggressiveExplore | - | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ...pu_core/id_ex_u/imm_o_reg[0]/CE |
| 28 | `ctl` | -0.102 | +0.000 | -1.012 | 27 | +0.051 | 11694 | 16033 | 60 | Default | AggressiveExplore | AggressiveExplore | - | - | .../u_ex_mem/ex_rd_data_o_reg[3]/C → ..._cpu_core/u_dcache/lru_reg[1]/D |
| 29 | `ctl_dup` | -0.102 | +0.000 | -1.012 | 27 | +0.051 | 11694 | 16033 | 36 | Default | AggressiveExplore | AggressiveExplore | - | - | .../u_ex_mem/ex_rd_data_o_reg[3]/C → ..._cpu_core/u_dcache/lru_reg[1]/D |
| 30 | `rep256_nofrn` | -0.102 | +0.000 | -1.012 | 27 | +0.051 | 11694 | 16033 | 36 | Default | AggressiveExplore | AggressiveExplore | - | - | .../u_ex_mem/ex_rd_data_o_reg[3]/C → ..._cpu_core/u_dcache/lru_reg[1]/D |
| 31 | `fp3_ndh_crit` | -0.105 | -0.003 | -2.392 | 52 | +0.058 | 11746 | 16045 | 48 | ExtraNetDelay_high | AggressiveExplore | AggressiveExplore | fp3 | - | .../u_if_stage/pc_reg[6]_replica/C → ...e/u_ascon_ise/state_reg[130]/CE |
| 32 | `hfp_split_near` | -0.110 | -0.008 | -3.338 | 73 | +0.032 | 11805 | 16037 | 40 | ExtraNetDelay_high | AggressiveExplore | NoTimingRelaxation | hfp2 | - | .../id_ex_u/sel_mem_wb_rs1_o_reg/C → ...id_ex_u/w_reg_waddr_o_reg[0]/CE |
| 33 | `crit_rep20` | -0.128 | -0.026 | -0.395 | 10 | +0.013 | 11758 | 16071 | 44 | Default | AggressiveExplore | AggressiveExplore | - | - | ...ore/id_ex_u/csr_addr_o_reg[8]/C → ...dcache/data_way1_reg_1/DIADI[7] |
| 34 | `pl_ndh_crit60_ntr` | -0.154 | -0.052 | -0.708 | 19 | +0.022 | 11671 | 16042 | 45 | ExtraNetDelay_high | AggressiveExplore | NoTimingRelaxation | - | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ...id_ex_u/sel_ex_mem_rs2_o_reg/CE |
| 35 | `pl_spr_crit` | -0.179 | -0.077 | -3.148 | 50 | +0.014 | 11728 | 16039 | 42 | AltSpreadLogic_medium | AggressiveExplore | AggressiveExplore | - | - | ...cpu_core/id_ex_u/rs1_o_reg[1]/C → ...cache/captured_wdata_reg[13]/CE |
| 36 | `rep256` | -0.188 | -0.086 | -9.696 | 145 | +0.051 | 11868 | 16092 | 287 | Default | AggressiveExplore | AggressiveExplore | - | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ...cpu_core/u_dcache/lru_reg[31]/D |
| 37 | `prod_crit200_ntr` | -0.195 | -0.093 | -8.119 | 93 | +0.013 | 11762 | 16053 | 56 | Default | Explore | NoTimingRelaxation | - | - | ...cpu_core/id_ex_u/rs1_o_reg[4]/C → .../captured_addr_reg[7]_rep__0/CE |
| 38 | `fp3_ndh` | -0.228 | -0.126 | -21.925 | 261 | +0.041 | 11713 | 16033 | 36 | ExtraNetDelay_high | AggressiveExplore | AggressiveExplore | fp3 | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ...e/u_dcache/valid_way0_reg[55]/D |
| 39 | `rep512` | -0.295 | -0.193 | -14.581 | 152 | +0.013 | 11740 | 16061 | 64 | Default | AggressiveExplore | AggressiveExplore | - | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ..._cpu_core/u_dcache/lru_reg[3]/D |
| 40 | `rep256_noeq` | -0.398 | -0.296 | -36.104 | 265 | +0.051 | 11837 | 16092 | 95 | Default | AggressiveExplore | AggressiveExplore | - | - | .../id_ex_u/sel_ex_mem_rs1_o_reg/C → ...cache/captured_wdata_reg[17]/CE |
| 41 | `ctl_hdc` | -0.514 | -0.412 | -89.852 | 484 | +0.053 | 11692 | 16033 | 36 | Default | AggressiveExplore | HigherDelayCost | - | - | ...cpu_core/id_ex_u/rs1_o_reg[3]/C → ...cpu_core/u_dcache/lru_reg[18]/D |

## 4. 五个结论（都带实测数字）

### 4.1 复制确实发生了，但不推动时序墙

`fanout_compare.py ctl rep128 rep256` 直接读各臂的 `route_high_fanout.rpt`：

| 网络 | ctl | rep128 / rep256 |
|---|---|---|
| `rst_sync_reg[2]` | 1 条 × 9650 pin | **跌破 256 pin**（被拆成多份） |
| `p12_inst/SR[0]` | 1 条 × 3989 | 跌破 256 |
| `ise/u_p12/SR[0]` | 1 条 × 1280 | 跌破 256 |
| `mode_p12_reg_n_0` | 1 条 × 661 | 跌破 256 |
| `dcache/bus_addr_r_reg[2]_1` | 1 条 × 457 | 跌破 256 |

即"把同义寄存器复制、控制锥本地化"这件事**在物理上成功执行了**（Slice Reg +59…+231，
Slice LUT +1.5%（rep256）/ +5.7%（rep128），复制单元 287~919 个），但 WNS 反而下降：`rep128 −0.074`、`rep256 −0.188`、
`rep512 −0.295`，而生产指令锚点 `prod_place` 是 **+0.016**。

两个对照臂把它拆清楚了：

| 臂 | 做法 | 实测 | 含义 |
|---|---|---|---|
| `rep256_nofrn` | 只给 `MAX_FANOUT 256` + `EQUIVALENT_REGISTER_REMOVAL=NO` | **与 `ctl` 逐位相同**（−0.102 / Slice Reg 16033） | 光给属性**不会**产生复制；2025.2 里复制只由 `-force_replication_on_nets` 触发 |
| `rep256_noeq` | 强制复制但不加 `EQUIVALENT_REGISTER_REMOVAL` | −0.398 / 265 失败 | 属性不是损失的原因；**损失来自复制这些锥本身** |

原因见 §1：这些锥自己的裕量是 +0.9~+2.8 ns，不在失败路径上；复制它们只消耗布局自由度
和布线资源，反而把真正的关键路径挤得更差。

### 4.2 定向复制（只复制失败端点的 CE 锥）是唯一有正收益的复制

`crep N` 只碰最差 N 条路径终点的使能锥：Slice Reg 仅 +9（16033→16042），
`place ExtraNetDelay_high` 下 `N=20 +0.030 / 60 +0.068 / 120 −0.039 / 200 +0.074`；
再加 `route NoTimingRelaxation` 时 `N=60 −0.154 / 120 +0.117 / 200 +0.138 / 300 +0.003`。
**非单调，量级 ±0.15 ns 与"一次布局重抽"同阶**，所以 N 不能当可调旋钮；

但 `N=120/200` 那一族是唯一稳定落在正区间且 0 失败端点的组合，而且
`pl_ndh_crit200_ntr` 与它的重复臂 `pl_ndh_crit200_ntr_dup` 在两个不同波次给出
**完全相同**的 +0.138 / WHS +0.017 / Slice LUT 11690 / Slice Reg 16042（§4.6），
所以"这一档配置"是可复现的，只是它的优越性来自这一次具体布局，不是来自
"复制越多越好"的单调规律。

### 4.3 floorplan 生效了，但只在"生产指令"以外才有微弱收益

- pblock 确实被遵守：fp3 的 pb_cpu 放进去 10404 个 leaf，只有 **275 个（2.6%）**落在
  区间外——那是 place 之后 `phys_opt_design` 插入副本/做 critical-cell 优化造成的溢出；
  pb_crypto 溢出 89 个（0.5%）。**判断 floorplan 有没有生效必须数这个，不能看模块 bbox。**
- 它确实把若干锥压短了：`mode_p12_reg` 的网络延时 7.193 → 4.410 ns，
  `state[3]` 2.673 → 1.266 ns；
- 但 WNS：`fp3 +0.017`（≈ 锚点 +0.016，无收益）、`fp2 +0.007`、`fpc −0.065`、
  `fp3_prod −0.061`、`fp3_ndh −0.228`、`fp3_crit_rep20 −0.105`。
  即**没有一种几何在跨指令组合后仍稳定优于"不给约束"**。原因见 §1 的硬约束：
  CPU 最小面积已占器件的 1/5，"更紧凑"在这颗 7z020 上没有空间。

### 4.4 "疏松"要么无效要么有害

`pl_spread`（AltSpreadLogic_medium）+0.002、`pl_spread_lo` −0.027、
`pl_spr_crit` −0.179。器件 22% LUT 占用，布局本来就"松"，人为再散开只是把关键路径
的每一跳拉得更长。

### 4.5 真正有效的是"放置时给高扇出网加权重"＋"布线不做时序松弛"

- `place_design -directive ExtraNetDelay_high`：`pl_ndh +0.017`、`pl_ndh_crit200 +0.074`；
- `route_design -directive NoTimingRelaxation`：`ctl_ntr +0.001`（同一 ctl 是 −0.102）；
- 两者叠加 `pl_ndh_crit200_ntr`：**+0.138 ns，0 失败端点，WHS +0.017**。
- 反向的 `HigherDelayCost` 灾难性：−0.514（484 个失败端点）。

时序墙分布（`probe_wall.tcl`，同一网表、同一进程）：

| 臂 | <0 | <0.05 | <0.1 | <0.2 | <0.3 | <0.5 | <1.0 |
|---|---|---|---|---|---|---|---|
| `ctl`（Default place） | 27 | 55 | 81 | 179 | 319 | 803 | 2407 |
| `prod_place`（生产指令锚点） | 0 | 9 | 44 | 127 | 278 | 816 | 3260 |
| `pl_ndh_crit200` | 0 | 0 | 4 | 44 | 125 | 457 | 3505 |
| **`pl_ndh_crit200_ntr`** | 0 | 0 | **0** | **7** | **44** | 310 | 2939 |

最差路径的构成也变了：ctl `dp=9.979 logic=2.882 net=7.097 lv=11` →
冠军 `dp=9.502 logic=3.193 net=6.309 lv=11`（累计走线 −0.79 ns，逻辑 +0.31 ns）。

### 4.6 流程是确定性的（所以上面的差值不是"抽签噪声"）

三组逐位相同的测量：

| 对照 | 结果 |
|---|---|
| `ctl` vs `ctl_dup`（不同波次、同旋钮） | WNS −0.102 / TNS −1.012 / 失败 27 / Slice LUT 11694 / Slice Reg 16033 —— 完全相同 |
| `pl_ndh_crit200_ntr` vs `..._dup` | WNS +0.138 / WHS +0.017 / Slice LUT 11690 / Slice Reg 16042 —— 完全相同 |
| `rep256_nofrn` vs `ctl` | 完全相同（说明只给 `MAX_FANOUT` 属性时工具什么都没做） |

因此臂间差异是旋钮引起的**因果**差异；但由于设计对布局极度敏感（同一网表仅换一条
directive 即可摆动 ±0.1 ns），单个差值仍**不能**外推成"这个旋钮普遍有效"。

### 4.7 WHS 侧：能查的都查了，post-route 修不了（+5 臂）

WHS（worst hold slack，最差保持余量）在冠军网表上是 **+0.017 ns**（正、0 个 hold 失败端点），
比 `docs/timing_margin_plan.md` §8 写的 +0.05 门限薄。专门补了 5 个"只做布线后修复、
不重布局"的臂（`run_holdfix.tcl`，都从冠军 routed DCP 起）：

| 臂 | 动作 | WNS | WHS | ΔWNS | ΔWHS |
|---|---|---|---|---|---|
| `hf_explore` | `phys_opt_design -directive ExploreWithHoldFix` | +0.138 | +0.017 | 0.000 | 0.000 |
| `hf_aggr` | `-directive ExploreWithAggressiveHoldFix` | +0.138 | +0.017 | 0.000 | 0.000 |
| `hf_aggr_both` | 上面 + `-aggressive_hold_fix` | +0.138 | +0.017 | 0.000 | 0.000 |
| `hf_clock` | `phys_opt_design -clock_opt`（post-route 偏斜优化） | +0.138 | +0.017 | 0.000 | 0.000 |
| `hf_clock_hold` | `-clock_opt` + `-aggressive_hold_fix` | +0.138 | +0.017 | 0.000 | 0.000 |

**五个臂全部是空操作（LUT 数也不变）**。原因写在 help 原文里：`-hold_fix` /
`-aggressive_hold_fix` 只作用于 "high hold **violators**"，而这里 WHS 是正的、没有违例，
所以工具无事可做；`-clock_opt` 在这个全局时钟树上也没有可改的偏斜。

为什么 hold 薄，实测很清楚：冠军网表最差的 20 条 hold 路径**全部是 Ascon 核内部 0~1 级逻辑的
寄存器对**，数据延时只有 0.30~0.44 ns：

| slack | 数据延时 | 级数 | 起点 → 终点（`u_ascon_mmio/u_ascon_core/…`） |
|---|---|---|---|
| **+0.017** | 0.381 | 1 (LUT6) | `p12_inst/s_out_reg[315]` → `u_crypto_aead/s4_reg[59]` |
| +0.020 | 0.300 | 0 | `run_key_reg[27]` → `key_r_reg[27]` |
| +0.025 | 0.419 | 1 | `p12_in_reg[251]` → `s_reg_reg[251]` |
| +0.030 | 0.305 | 0 | `data_out_reg[77]` → `out_shf_reg[77]` |
| +0.040 | 0.390 | 1 | `tag_reg[46]` → `tag_out_r_reg[46]` |

即：hold 余量由"相邻寄存器之间只有 0~1 个 LUT"这个 RTL 结构决定，靠 +0.271 ns 的时钟偏斜
才撑到 +0.017。要抬高它只有两条路，而且都与 setup 冲突：

1. **增加最小延时**：把那几对寄存器在物理上拉开（例如把 `u_ascon_mmio/u_ascon_core` 切成
   两个子 pblock）。预算来源是 `u_ascon_mmio` 自己的 setup 墙（+0.108 ns），比全局 WNS
   （+0.138）更紧，最多能花约 0.09 ns。
2. **整体放松布局**：实测 `fpc` WHS +0.043（WNS −0.065）、`fp3` +0.023（WNS +0.017）
   —— 用 setup 换 hold。

**再试"把 hold 关键的那对寄存器物理拉开"**（`floorplan_hold.py`，把
`u_crypto_aead/p12_inst` 从 `u_ascon_mmio` 里切出去单独一块，其余照冠军配置）：

| 臂 | 几何 | WNS | WHS | 失败端点 |
|---|---|---|---|---|
| `hfp_split_near` | p12 X26..49/Y0..49，crypto 相邻 X50..113/Y0..49 | **−0.110** | **+0.032** | 73 |
| `hfp_split`（远分离） | p12 左下，crypto 右上 X79..113/Y50..149 | 未完成 | — | — |

- 相邻切分把 WHS 从 **+0.017 抬到 +0.032**（<0.03 ns 的端点从 5 条降到 0 条），
  代价是 WNS 从 +0.138 掉到 **−0.110（失败 73 个端点）**——用 0.015 ns 的 hold 换
  0.248 ns 的 setup，交换率 1:16，净亏。
- 远分离几何让 placer 在 `Phase 4.1.1.2 Post Placement Timing Optimization`
  卡住 30+ 分钟无进展，已终止（见 `build/reports/backend_opt_20261021/README_failures.md`）。
- **为什么抬不高**：切分成功后最差 hold 路径并没有消失，只是换了一条——
  `p8_inst/s_reg_reg[109]`（0.389 ns）、`nonce_r_reg[47]`（0.375 ns）、
  `ise/u_p8/s_out_reg[27]`（0.375 ns）……WHS 是由**一整群 0~1 级逻辑的
  寄存器对**（Ascon p8/p12 + ISE 都算）共同决定的，把一族推开只会露出下一族。

结论：WHS 在这版网表上是**结构量**（RTL 里"相邻寄存器只隔一个 LUT"），
不是布局/优化指令能改的量。

**结构性事实（35 臂统计）**：`corr(WNS, WHS) = −0.516`；**所有 WHS ≥ +0.05 的 7 个臂，
WNS 全部 ≤ −0.102（setup 违例）**；官方生产跑法也只有 +0.023（remap）/ +0.031
（ExplorePostRoutePhysOpt）。也就是说"同时 WNS ≥ 0 与 WHS ≥ +0.05"在这一版网表上
**从未出现过**。建议把 §8 的 hold 门限改成"hold 失败端点 = 0 且 WHS > 0"（当前事实），
而不是为 33 ps 的 hold 余量牺牲 0.1 ns 以上的 setup。

## 5. 结论与建议

1. **后端已经打满了**：35 个布局/复制臂（含重复对照）+ 6 个 hold 专项臂，覆盖复制（全局/定向）、
   四套 floorplan、疏松、放置与布线 cost model、布线后 hold 修补，WNS 区间 −0.514 ~ **+0.138**，没有一档达到 +1.0 ns。
   唯一真正改善的是**接近临界的端点数量**（<0.2 ns 从 127 降到 7，<0.3 ns 从 278 降到 44），
   也就是把"随时可能翻负"的脆弱性去掉了。
2. **可落地的配置**（若要采信最好的一档）：
   `place ExtraNetDelay_high` + `route NoTimingRelaxation` +
   `phys_opt AggressiveExplore`（前后各一次）+ 定向复制最差 200 条路径的 CE 锥。
   一键复现：`BOPT_MAXTHREADS=4 build/backend_opt_20261021/run_wave.sh 1 pl_ndh_crit200_ntr`，
   产物 `build/local/backend_opt_20261021/pl_ndh_crit200_ntr/pl_ndh_crit200_ntr_routed.dcp`。
   验收：`route_status` 0 布线错误、WNS +0.138 / TNS 0 / 失败 0 / WHS +0.017、
   Slice LUT 11690 / Slice Reg 16042（生产参考 11752 / 16040，本 harness 锚点 11689 / 16033
   —— 即与生产同级，没有面积代价）。
   **以 +0.138 ns（周期的 1.4%）当作"100 MHz 有余量"仍然不成立**，只能当"比 +0.007 好一个量级"；
   它的价值在 §4.5 的分布：<0.2 ns 的端点从 127 条降到 7 条，抗二次改动能力明显变好。
   若要把它变成生产产物，需要在 baseline 工程里建一个用这套指令 + 定向复制的独立 impl 入口，
   再跑一遍 `docs/freeze_checkpoint_20261018.md` §2 的全套回归（本轮只做 STA，未跑功能回归，
   因为 `src/rtl` 未被修改、变换是 Vivado 的等价实现变换）。
3. **要真余量还是那两条老路**：降频到 90 MHz（同一网表折算 ≈ +1.11 ns）或按
   `docs/cpu_timing_architecture_plan.md` 做 RTL 深度削减（B+C+E → A+D → F）。
   本轮实测进一步确认：**任何纯后端手段都无法把这道墙抬到 +1.0 ns**。
4. 后续不要再扫内置策略/floorplan/复制：本轮与 10-20 的 33 策略扫掠、
   4 变体 P&R 扫掠合起来，已经覆盖了这些维度。

## 6. 复现

```bash
# 单臂 / 波次（每臂独占工作目录与报告目录；已有 result.txt 的臂会被拒绝重跑）
BOPT_MAXTHREADS=4 build/backend_opt_20261021/run_wave.sh 5 ctl rep256 fp3 pl_ndh rep128
# 只跑到 place（验证 pblock 合法性与容量，约 10 min）
BOPT_SMOKE=1 build/backend_opt_20261021/run_wave.sh 3 fp2 fp3 fpc
# 汇总 + 扇出对比 + 时序墙
python build/backend_opt_20261021/summarize.py
python build/backend_opt_20261021/fanout_compare.py ctl rep128 rep256 fp3
# vivado -mode batch -source build/backend_opt_20261021/probe_wall.tcl -notrace \
#        -tclargs "ctl prod_place pl_ndh_crit200_ntr"
```

工具：Vivado 2025.2，`xc7z020clg400-1`，top `top_pl_bram`，起点 DCP 见文首；
每臂 `result.txt` 记录 WNS/TNS/失败端点/WHS/LUT/FF/复制单元数/布线错误/最差路径两端与
logic-net 拆分/全部旋钮/HEAD/工具版本。

## 8. 出 bitstream（2026-10-21 13:06，xc7z020clg400-1）

从冠军 routed DCP 直接出编程文件（`write_bitstream -bin_file`，脚本
`build/backend_opt_20261021/write_bitstream_champion.tcl`）：

| 项 | 值 |
|---|---|
| 文件 | `build/local/backend_opt_20261021/pl_ndh_crit200_ntr/pl_ndh_crit200_ntr.bit`（4,045,687 B）+ `.bin` |
| sha256 | `6cff4f2f7443e68c38549ed8db2b8aed13259ba60c2d1b5adcff66c8614e4baa` |
| Bitgen | `Bitgen Completed Successfully`（自带 DRC 只报 warning） |
| 时序（出 bit 前复测） | WNS +0.138 / WHS +0.017 |
| 引脚（沿用恢复的 baseline `const.xdc`） | clk=U18、reset_btn=N16、uart_rxd=T19、uart_txd=J15、led=H15/L15、button=L14/K16 |
| BRAM 内容 | **baseline 的 `freertos_demo.coe`（8333 字），不是 Ascon 固件** |

两条必须记住的限制：

1. **`xc7z020clg400-1` 是器件/封装，不是板型。** 引脚与 50 MHz 时钟仍来自恢复的
   baseline 假设；`docs/ascon_board_checklist.md` 与 `board_bringup_plan.md` 都写明
   "板卡型号未核实前不烧录"、"PYNQ-Z2 是 125 MHz 另一引脚，照抄会把 MMCM 打到 250 MHz"。
   若实际板子的时钟引脚/频率不同，这份 bit 不会正常工作（症状：无 UART 输出、LED 不动）。
2. **烧上去跑的是 FreeRTOS demo，不是 Ascon。** 现有网表的 BRAM 初始化来自
   `board/vivado_zynq7000_xc7z020_baseline/.../freertos_demo.coe`。

把 Ascon 固件放进去的路径（T0.2）：板级 BRAM 是 32 个 ramloop × 32-bit，深度
**32768 字**；`build/local/ascon_ise/ascon_ise.hex` 恰好 **32768 行 32-bit**（1552 行非零），
所以可以 1:1 转成 COE。但换 COE 必须重新生成 `blk_mem_gen_0` 并重新 synth + impl，
**+0.138 ns 不会保留**，需在新网表上重测（本战役 harness 可直接复用，约 35 min/臂）。

## 7. 不要做的事

- 不把 `+0.138 ns` 写成"100 MHz 收敛有余量"；它是周期的 1.4%，而板级 XDC + PS7 上板后
  这个数字不会保留。
- 不用 `set_multicycle_path` / 降 `clock uncertainty` / 假 `false_path` 刷 WNS。
- 不因为"复制了 9657 pin 的复位网络"就认为控制锥问题解决了（§4.1）。
- 不再用 `HigherDelayCost`（−0.514）。
