# V09 A → C → B 时序修复与验证

> V10 清理更新：按用户要求只保留最终双策略 RPT；本文涉及的旧基线、lint、A+C 中间报告
> 已删除，数值作为历史记录保留，不再宣称这些旧路径存在。最终 RPT/元数据/功能与 ISA 对照
> 证据仍保留。清理范围和重新实跑结果见 [工作区清理](workspace_cleanup.md)。
> 后续用户确认：并行任务恢复的部分 V06/sweep 报告暂时保留；清理后数据复验一致，留存收口延期。

2026-10-18；owner TBD；基线 `f52bc49` + 已有 fix_r1 工作区。
目标 XC7Z020CLG400-1，Vivado 2025.2，top `top_pl_bram`，约束不变。
当前结论：A→C→B 与双策略实现均完成；**既有 100 MHz 约束下 setup/hold/pulse STA 通过**。
两策略 WNS 仅 +0.001/+0.007 ns，余量极小；IO delay/板级约束与实板验收仍未完成。

## 基线端点复核

通过 Ross MCP 打开 **fix_r1 routed checkpoint 的独立副本**，运行
`build/report_timing_endpoints.tcl`，保存每个 failing endpoint，而非推测 top-20：

| 分类 | 失败端点 |
|---|---:|
| ISE P8/P12 私有置换复位 | 93 |
| multiplier | 48 |
| dcache | 11 |
| other | 4 |

`RESULT strategy=fix_r1 wns=-0.128 tns=-11.213 failing=156 whs=0.005`。
原证据路径：`build/reports/timing_acb_baseline/{result.txt,failing_endpoints.csv}`（已按 V10 授权清理）。
因此 A 的预期是解除 93 端点，不是单独实现 100 MHz 收敛。

## 顺序及改动

1. **A**：`src/rtl/ascon/ascon_ise.v` 注册 `perm_rst_n`，切断全局 cancel 组合锥到
   1280-bit 私有 reset 的路径。接受当拍同时启动复位释放和 `p_start`，避免吞 start。
   架构取消仍当拍有效；私有清零延后一拍，已有安全保证不删除，改为明确有界合同与断言。
   A 单独测试：MMIO 13212/0、ISE 1502/0、CPU units 4/4 PASS。
2. **C**：`src/rtl/mult.v` 增加已符号扩展的输入寄存器，乘积独立注册，避免 EX 操作数
   mux 加乘法落在同一周期。数据寄存器无 reset 以允许 DSP packing；控制有 reset/cancel。
   done 保持到 EX ack，支持下游 hold，不修改 ISA。新增 `tb_multiplier_pipeline`：
   256 边界组合 + 1000 固定 seed 随机 + 3 cancel/reset 后恢复 = 1259 例。
   `tb_key_execute` 增加 hold、连续乘法、interrupt cancel。A+C CPU units 5/5 PASS。
3. **B**：`src/rtl/dcache.v` 仅 load miss 经过 MISS_CAPTURE，store/MMIO 恢复 HEAD
   单拍注册请求和固定延迟读回；保持 cache fill 请求为单拍。不改 LRU 或时序例外。
4. **STA**：最终功能回归后，仅一次 fresh synthesis，两个独立 implementation run：
   `Performance_ExplorePostRoutePhysOpt` / `Performance_ExploreWithRemap`。
   脚本 `build/build_timing_acb.tcl`，独立 `build/local/timing_acb_impl`，
   报告 `build/reports/timing_acb_20261018`。源码哈希来自实际隔离快照。

## ISA 验证边界

`python sim/ascon/run_rv32_isa.py --label <unique> --cc-prefix <xpack-prefix>`。
恢复源保持原字节；新 `isa_env` 仅适配启动/链接/结果通知，以真实 `soc_top`、cache、AXI BRAM
运行全部恢复的 RV32I/RV32M 指令测试体（42 + 8 = 50）。包括 load/store、旁路、分支、fence.i、
MUL/MULH/MULHSU/MULHU、DIV/DIVU/REM/REMU。并非标准 U/S 模式/privileged compliance 环境。

| 快照 | PASS | FAIL | 证据 |
|---|---:|---:|---|
| fix_r1 控制快照 | 49 | 1 | `data/ascon/results/isa/fix_r1_control/` |
| A+C | 49 | 1 | 中间结果已按 V10 清理；最终候选与控制保留 |
| A+C+B | 49 | 1 | `data/ascon/results/isa/timing_acb/` |

唯一已知失败 `rv32ui_ma_data` 要求硬件完成非对齐访存；本 CPU 触发异常，适配器返回
`0x1bd5b` 失败签名。控制与候选同样失败，runner 诚实返回 exit 1，不删除测试或改为 PASS。
不将 49/50 宣称全套 ISA 全绿；RV64、A/F/D、privileged tests、完整嵌套中断暂未验证。

## 最终功能/周期/STA

最终整机 sw/hw/ise、三模式 `--security`、ISE `--stall`/`--reset` 共 8 项全部 PASS（exit 0）；
MMIO 生命周期 13212 检查、ISE 1502 检查、CPU units 5/5 全部 PASS。
XSim 2025.2 behavioral 复核：乘法 1259 例、ISE 1502 检查 PASS，完整 compile/elaborate/runtime
日志保存在 `data/ascon/results/timing_acb_xsim/`。无 formal、coverage、门级仿真或实板验收声明。

ISA runner exit 1 来自上述既有 `ma_data`，并非新增功能失败。
`python sim/ascon/summarize_timing_acb.py` exit 0 只表示功能无新回归，输出明确保存
`full_isa_pass=false` 和已知失败边界；同时核对 8 次整机仿真的生产源码 hash 与工作区一致。
受控汇总：`data/ascon/results/timing_acb_functional_summary.json`。

| mcycle 指标 | 原 HEAD | fix_r1 | 最终 A+C+B |
|---|---:|---:|---:|
| sw enc 16B | 17353 | 17410 | 17353 |
| sw enc 32B | 21515 | 21588 | 21515 |
| sw dec 16B | 17847 | 17911 | 17847 |
| sw dec 32B | 22094 | 22171 | 22094 |
| hw crypto | 99 | 97 | 99 |
| hw full MMIO | 670 | 717 | 670 |
| ISE | 2496 | 2550 | 2496 |

三种模式最终周期均恢复到前轮相同 xpack 工具链的 HEAD 对照值；hw full MMIO 相对
fix_r1 减少 47 cycles（6.56%），取消了原相对 HEAD 的 +7.0% 代价。
这些都是 RTL 仿真 mcycle，不是上板时延。

RTL lint：EX hierarchy 4 条（含 1 条既有 critical），dcache 2 条；唯一新增 warning 是乘积的
未使用扩展高位。未屏蔽诊断；原 CSV/控制对照目录 `build/reports/timing_acb_lint/` 已按 V10 清理。

原始功能日志 `build/local/timing_acb/`、受控 JSON/log
`data/ascon/results/key_lifecycle/*timing_acb*`。

## 双策略最终布局布线结果

Ross MCP `source build/build_timing_acb.tcl` 已完成，exit 0（3895.571 秒）。
40 个生产 RTL/header 文件与最终已测试工作区逐字节 hash 匹配，原 baseline XDC 与构建副本
hash 一致；没有降低频率、增加 multicycle/false-path 例外或更改 IP 功能配置。
两个策略共用一次综合结果，均执行到 post-route phys_opt。

| 策略 | WNS ns | TNS ns | setup 失败 | WHS ns | hold 失败 | pulse 失败 | 路由错误 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Performance_ExplorePostRoutePhysOpt | +0.001 | 0 | 0 | +0.031 | 0 | 0 | 0 |
| Performance_ExploreWithRemap | +0.007 | 0 | 0 | +0.023 | 0 | 0 | 0 |

相对 fix_r1：ISE private **93→0**、multiplier **48→0**、dcache **11→0**、other **4→0**。
这是组合 A+C+B 的最终端点分类，不是单独 A/C 的物理消融测试。
没有修改 LRU；其余 dcache 尾部由本次布局/布线覆盖。最终 CSV 均仅有表头（0 个失败端点）。

| 资源 | fix_r1 | PostRoute | Remap |
|---|---:|---:|---:|
| LUT | 11536 | 11680 | 11752 |
| FF | 16022 | 15992 | 16040 |
| BRAM tiles | 38.5 | 38.5 | 38.5 |
| DSP | 4 | 4 | 4 |

Remap routed DCP 只读核验：乘法器 4 个 DSP48E1 全部 AREG=1、BREG=1，1 个 PREG=1，
其余 PREG=0、全部 MREG=0。不能声称所有 DSP 输出寄存器都打包了；其余乘积组合由 DSP/
fabric 与产品寄存器实现。实测输入注册化已落到 DSP。原始属性见 `remap/dsp_registers.txt`。

最差路径：PostRoute 为 `if_stage/pc_reg[4] → ascon_ise/state_reg[*]/CE`（+0.001）；
Remap 为 `id_ex/w_reg_waddr_o_reg[0] → dcache/data_way1/DIADI[7]`（+0.007）。
不再是原 P8/P12 私有复位或乘法 DSP 输入长组合锥。不要因余量极小而继续无边界改 RTL。

**候选推荐 Remap**：本次 setup 余量稍大，但 +7 ps 不构成跨工具/源码变更的鲁棒性保证。
两报告均明确 0 unconstrained internal endpoints、0 no_clock，且打印
`All user specified timing constraints are met.`；同时 no_input_delay 检查 4 项
（3 项实际缺失 + 1 项已有 false path），no_output_delay 3 项。方法学提醒仍有 LUTAR-1、
RAM/宽乘法/clock scope warnings。**这不是完整板级时序、DRC 或电气签核。**

证据：`build/reports/timing_acb_20261018/{postroute,remap}/` 内含最终 timing/paths/route status/
utilization、RESULT 与端点 CSV，根目录 `build_context.txt`、`source_hashes.json`、
`validation_gate.json`、`summary.json` 保存版本/配置/源码/检查边界。
`python build/summarize_timing_acb.py` exit 0，交叉核对 RESULT 与完整 timing summary、端点 CSV、
资源/路由和 XDC hash。DCP 在 ignored `build/local/timing_acb_impl/acb_{postroute,remap}_routed.dcp`。

## 交付与剩余门禁

任务 V09 完成本轮授权范围（不是 V01/B03/板级全部完成）。改动核心为
`src/rtl/{mult,ex_stage,dcache}.v`、`src/rtl/ascon/ascon_ise.v`，对应测试、独立构建/汇总脚本及
接口/任务/日志已同步。原恢复资产、实验归档、扫掠工程和既有证据均保留。
下一接收：B03/V01/I08，先核实板卡、IO timing/电气约束、DRC 与复位，再做 bitstream/实板 KAT；
当前不扩展 RV64/特权模式/嵌套中断或 PUF。
未 commit/push，未打开或修改策略扫掠工程、原 baseline、XCI/XDC。
