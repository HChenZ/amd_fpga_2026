# 原 XC7Z020 XPR 与当前 Kintex XPR 比较

日期：2026-09-21。比较基准：用户 ZIP 的原工程 XPR 与本轮开始时的 `board/riscv_vivado_project/riscv_vivado_project.xpr`。当前工程原件未修改；新恢复副本的去 DCP 调整单独记录，不能混入两份原件的比较。

## 1. 是否只改过 Part

**需要区分两条事实：**

1. Git 历史显示，`dda9405974fab32ff7bf7c6d5252229705c0d467` 相对仓库初始版本 `3b6b135`，对 XPR **确实只改了三处 Part**（全局、synth_1、impl_1），从 xc7z020clg400-1 改为 xc7k325tlffv676-2L。
2. 但仓库初始版本的 XPR 已不同于本次 ZIP 原 XPR：初始版本中已经没有三个 IP fileset 和 COE，并已改用仓库外部 RTL 引用。因此 **“当前 XPR = 本次 ZIP XPR 只改 Part”不成立**。仅凭相似内容不能证明 ZIP 到初始提交之间的具体操作历史。

提交说明里写的器件拼写与实际 XML 不完全相同；实际 Part 以 XML 为准。上述结论来自 `git log` / `git show` 与原文件对比，不猜“哪个更新”。

## 2. 两份原件身份

| 项 | ZIP 原 XC7Z020 | 当前仓库 Kintex |
|---|---|---|
| SHA-256 | `e11d692d69706b601565901a8d00dd12c0c9f8a9c1cb8afa830f721996fd1e59` | `a5f54c758adea1ccbbf6042e3ed6823a46139d57250133a32f2b60943552c6e6` |
| bytes | 35336 | 19858 |
| Vivado / XML | 2025.2 / Version 7 Minor 71 | 相同 |
| Part | xc7z020clg400-1 | xc7k325tlffv676-2L |
| top | top_pl_bram | top_pl_bram |
| BoardPart | 空 | 空 |
| FileSet 数量 / Run 数量 | 7 / 8 | 4 / 2 |
| File 引用数 | 37（含生成 DCP） | 32 |

## 3. 除 Part 以外的变化

| 范围 | ZIP | 当前仓库 | 影响 |
|---|---|---|---|
| Project Path | 原作者 C:/Users/Y/... 路径 | D:/HCZ/Projects/amd_fpga_2026/... | 机器元数据不同，需验证 Vivado 重定位行为 |
| Project Id | f06f921370fc469a8dfcc51a396ef298 | 7972bf8406fd4cd2835003ed252b7ff0 | 不同工程标识 |
| 31 个 RTL/header 路径 | `$PSRCDIR/sources_1/imports/rtl/...` | `$PPRDIR/../../src/rtl/...` | 原工程私有快照改为共享开发 RTL |
| RTL 导入元数据 | 含 ImportPath / ImportTime | 相应属性不再保留 | 历史来源信息减少，不代表内容有逻辑变化 |
| defines.v FileInfo | `SFType="VHeader"`，IsVisible，synthesis/simulation | 普通 FileInfo，增加 implementation 使用项 | 文件类型/使用属性变化 |
| memory init File | imports/bin_file/freertos_demo.coe | 不存在 | 不仅更改文件名，而是整个初始化输入引用未包含 |
| 三个 IP | clk_wiz_0 / axi_bram_ctrl_0 / blk_mem_gen_0 fileset，3 XCI，6 个相关 synth/impl run | 均未包含 | 当前顶层实例名仍存在，当前工程不具备这些源配置 |
| constraint 引用 | constrs_1/new/const.xdc | constrs_1/new/constrs.xdc | 文件名不同，约束命令比较见下节 |
| incremental DCP | utils_1 File + synth_1 IncrementalCheckpoint 属性 | 两者均未包含，但 AutoIncrementalCheckpoint 仍 true | 生成 checkpoint 依赖被移除 |
| 综合策略 | MaxClockBufferCount=16 | 无该显式 Option | 默认行为可能不同，不推断结果等价 |
| 实现策略 | Performance_ExplorePostRoutePhysOpt | Vivado Implementation Defaults | route `-tns_cleanup`、显式 Directive、启用 post-route physopt 等设置不再保留 |
| Run 元数据 | synth/impl 有 Dir；impl LaunchOptions -jobs 12 | 相应字段未保留 | 启动/位置元数据不同 |
| 导出仿真计数 | XSim/ModelSim/Questa/Riviera/ActiveHDL =15 | =0 | GUI/导出历史变化，不当作功能改变 |

sim_1 的 top 与配置、Simulators、空 Board 和 DashboardSummary 相同。完整文本差异见 [vivado_project.diff](../data/recovery/cicc1000023/vivado_project.diff)，显示时只统一 CRLF→LF，不忽略其他内容。

“IP 被删除”在此仅指相对 ZIP 的当前文件集缺项；Git 初始提交已缺这些 IP，不能把删除动作归因于 dda9405。

## 4. XDC 比较

| 项 | ZIP const.xdc | 当前 constrs.xdc |
|---|---|---|
| bytes | 922 | 901 |
| 解码 | UTF-8 | GB18030 可无损解码，UTF-8 不成立 |
| SHA-256 | `01f639212f00fce073b373a470b559772797842fee9dcd394076499f5fcd42bf` | `e13fefdc309c09271ad8780208edaa13fda6d5a290f5c40b08e15ae7b4eae290` |

按各自编码解码，去掉空行和行首尾空白后，**全部行（包括注释）一致**。引脚、IOSTANDARD、reset false path 和 20 ns 时钟命令一致；存在命名、编码、空行差异，没有观察到约束命令的改变。可读 diff 见 [xdc_content.diff](../data/recovery/cicc1000023/xdc_content.diff)。

| 信号 | PACKAGE_PIN | IOSTANDARD |
|---|---|---|
| clk | U18 | LVCMOS33 |
| uart_rxd / uart_txd | T19 / J15 | LVCMOS33 |
| button[0] / button[1] | L14 / K16 | LVCMOS33 |
| led[0] / led[1] | H15 / L15 | LVCMOS33 |
| reset_btn | N16 | LVCMOS33 |

相同引脚约束不能证明它适用于两种 part 或本次实物板卡，B03 仍需核对板级原理图和版本。

## 5. 初始化与恢复策略

ZIP 的 blk_mem_gen XCI 指向 `../../imports/bin_file/freertos_demo.coe`，Load_Init_File=true；该 COE 与归档 FreeRTOS/build 的 COE 哈希一致。当前 Kintex 原件没有 XCI/COE，无法从当前 XPR 推断它使用了哪种替代初始化方式。

恢复采用原 `.srcs` 布局与原 RTL，避免 XCI→COE 或 XPR→RTL 引用失效。新恢复 XPR 只去掉可再生 DCP 引用并关闭增量综合，其余原设置保留。完整最小变更见 [xpr_recovery.diff](../data/recovery/cicc1000023/xpr_recovery.diff)。这不是从 Kintex part 字符串反向生成的空工程。

恢复阶段曾保留同深度 legacy 副本；foundation 收口核对副本 XPR/XDC 字节一致后，按用户授权 git mv 将原工程统一为 `board/vivado_kintex7_legacy/`。原路径已移除，legacy 的 32 个文件引用均静态可解析；legacy 本身仍缺 IP。本轮未启动 Vivado，因此没有声称任何恢复工程已经重新综合或实现成功。
