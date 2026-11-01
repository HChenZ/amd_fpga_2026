## 4 硬件实现与时序收敛

本章区分当前 PYNQ 发布工程与历史 PL-only 工程。时序、资源、DRC 属具体实现 run，
不因相同器件或模块名称而跨工程沿用。正余量不替代实板正确性或温压稳定性试验。

### 4.1 当前工程与构建入口

当前入口为 `board/vivado_zynq7000_xc7z020_pynq/build.tcl`，top=`pynq_wrapper`、
part=`xc7z020clg400-1`、Vivado 2025.2。PS7 GP0 连接两个 AXI-Lite 窗口，
FCLK0 配置为 100 MHz；`proc_sys_reset` 与控制窗口管理复位。
COE 作为 128 KiB BRAM 初值，由服务固件 ELF/BIN 生成；板上不做动态固件装载。

源集明确使用 `rtl_p0/soc_top.v` 和 `rtl_p0/ascon_mmio.v`，其余 CPU/Ascon 模块按构建脚本选择。
实际逐文件哈希、IP 版本与产物大小见 release/manifest.json。
不能用当前 main 的同名文件、旧工程缓存或不同 COE 替代该发布源集。
`rebuild_firmware.tcl` 用于已有独立工程的 BRAM 重建与后续实现，不等于干净构建入口。

历史 PL-only 基准使用 `top_pl_bram`、板外串口及 clk_wiz_0；它与当前 PS 时钟工程分开保存。
三套历史固件对应三份 bitstream，当前 PYNQ 则在同一 overlay 下按 mode 选择三方案。

> <span class="figslot">图 2-2</span> **历史 PL-only 工程结构**：top_pl_bram 的板外时钟与串口入口，
> 仅用于解释历史基准；当前 PS7/FCLK0/AXI-Lite 结构见 PS/PL 通路图。

### 4.2 历史时序收敛过程

本节为带原始记录的研制过程，不将历史余量称为当前 release 余量。
历史默认策略 WNS −0.942 ns，33 组策略中最优 Performance_ExploreWithRemap 为
−0.118 ns、TNS −1.008 ns、22 个失败端点。记录见
`data/ascon/results/strategy_sweep_20261017/strategy_sweep_summary.json`。
它说明已测策略的效果，不证明所有可能策略的理论上限。

对 fix_r1 快照的端点归因识别出 ISE 私有状态复位扇出、乘法器组合路径及 D-cache 请求通路三类问题。
对应结构改造为：局部复位注册化、乘法器输入输出注册与 ack/cancel 握手、MISS_CAPTURE 与
store/MMIO 绕过。归因分类不是互斥端点总数之和，不以分类数相加覆盖所有端点。

| 历史 run | WNS ns | TNS ns | setup 失败端点 |
|---|---:|---:|---:|
| A+C+B / ExplorePostRoutePhysOpt | +0.001 | 0 | 0 |
| A+C+B / ExploreWithRemap | +0.007 | 0 | 0 |
| PL-only 三镜像报告 | +0.087 | 0 | 0/55572 |
| 当前 PYNQ release | +0.034 | 0 | 0/62861 |

前两项为历史策略快照，第三项为历史板测镜像实现，第四项为独立 PYNQ BD 实现；不能将相邻行之差
全归因于某一补丁。当前余量仅 34 ps，任何功能、约束或 IP 变化都须重新验证。

> <span class="figslot">图 3-2</span> **历史 PL-only 时序收敛记录**：默认策略、已测策略最优、
> 结构改造与历史板测镜像的 WNS；不替代当前 PYNQ 实现报告。

### 4.3 时钟与 IO 的适用范围

当前 PYNQ 通路位于 PL 内部，通过 PS 的 AXI-Lite 窗口交互，没有沿用历史板外 UART、LED、按键 IO XDC。
当前报告内部未约束端点为 0，未列出 no_clock/no_input_delay/no_output_delay 问题。
这不等于测得了板外 IO 延迟，也不能把别的源集的 IO 覆盖检查作为本工程签核。

历史板外 UART 的约束分析仅作为工程资料保留，不列为当前 release 的新增成果。
FCLK0 配置为 100 MHz，但独立频率测量仍为 not_measured；本报告不据配置值声称实测 Fmax。
时序报告中的 WNS、TNS、WHS、THS 与路径覆盖须联合检查，不能只展示一个正 WNS。

### 4.4 当前与历史整机实现结果

当前 `pynq_wrapper` 的完整资源原表为 `build/reports/pynq_final_20261028/utilization.rpt`，
数字由证据脚本抽取并列在附录 C，不用历史 PL-only 数字代替。

| 当前 PYNQ 指标 | 结果 | 原始报告 |
|---|---|---|
| WNS / TNS | +0.034 ns / 0 | timing.rpt |
| WHS / THS | +0.020 ns / 0 | timing.rpt |
| setup / hold 失败 | 均 0/62861 | timing.rpt |
| 内部未约束端点 | 0 | timing.rpt 的 check_timing 段 |
| DRC | 0 Error / 0 Critical Warning | drc.rpt |

整机资源为 LUT 14269、FF 19691、BRAM 34.5 tile、DSP 4。
DRC 默认报告有 53 项 Warning，其中包含规则条数上限提示；不能将该显示数当作所有潜在 Warning 的总数，
更不能写成“DRC 无任何警告”。DSP 流水、RAM 输出寄存器等提示保留在原始报告。

历史 PL-only 整机资源为 LUT 12426、FF 16156、BRAM 34.5 tile、DSP 4，WHS +0.021 ns。
原件位于 `build/local/proj_backup_first_time_20261027/first_time.runs/impl_1/`，不是当前工程报告。
这些是整机总资源，不据此推导每条加速路径的独立面积或功耗。

> <span class="figslot">图 3-6</span> **Vivado 实现后器件视图**：打开 Implemented Design 的 Device 窗口，
> 展示 PS7 与 PL 内 CPU、Cache、Ascon 等逻辑在 XC7Z020 上的布局。

> <span class="figslot">图 3-7</span> **Vivado 资源利用率报告**：Report Utilization 的汇总页，
> 应可见 LUT 14269、FF 19691、BRAM 34.5、DSP 4。

### 4.5 发布身份与复现边界

| 对象 | 当前记录 |
|---|---|
| release source commit | 86dc10f13e96adbb360f1adfe0c4891ce2f8e2a7；source_dirty=true |
| 板端 benchmark Git | ac9143d5c6acc9e7ac61f907a7e802eb6b35cddd |
| pynq.bit | 4045688 B；SHA-256 前缀 6e7f9320 |
| pynq.hwh | 148833 B；SHA-256 前缀 3ebd2640 |
| 固件 | pynq-svc-v1；ELF/BIN/COE 逐项哈希见 manifest |
| 身份核验 | 板端 release_hashes.log 与 identity.json；bit/hwh/固件必须配套 |

bit/hwh 来自同一 BD 实现；BRAM MIF 与最终 BIN 的 128 KiB 补零镜像有逐字节一致性证据。
manifest 的 source_sha256 是重建输入核对依据；source_dirty=true 表示只给 Git commit 不足以冻结全部输入。
manifest 中 hardware_validation=NOT_RUN 是构建时快照，后续板测应引用日期明确的外部证据，
本次不修改已发布 manifest 来追写状态。

从干净环境重建并运行的 D05 仍未完成；本文提供实际入口与现有记录，不承诺 clean clone 一键全部验收。
复建不要求 bitstream 字节必然相同，应分别核对源输入、功能、时序、资源和新产物身份。

<span class="evid">证据 board/vivado_zynq7000_xc7z020_pynq/release/manifest.json；board/vivado_zynq7000_xc7z020_pynq/validation_20261028.md；validation_20261029.md；build/reports/pynq_final_20261028/；docs/timing_acb_validation.md</span>
