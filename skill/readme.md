# 通用 Skill 交付目录

2026-10-29 最新交付选择：11-01提交；10-30优先测试已有 `rtl-design-discipline`，
见 `docs/skill_test_guide_20261030.md`。当前仅确认文本内容，实际效果仍待测试。
2026-10-30 新增 `pynq-overlay-workflow`（通用 PYNQ Skill），工具层已离线验证，agent 对照与实板验证 not_run，见下表。

本目录存放可复用 Skill 的**受控副本**（不是本工程的运行时依赖，也不绑定具体 agent 平台）。
下表的状态栏只写已验证的事实；没有验证证据的一律写 `not_validated`。

2026-10-29 状态（历史记录）：P0/P1 实板主链已完成，当时 S01-S05 的通用 PYNQ Skill 尚未实现。
2026-10-30 更新：`pynq-overlay-workflow` 已成形并通过工具层离线验证；两个 Skill 的 agent 对照效果
仍为 `not_validated`。

## 目录一览

| 路径 | 是什么 | 给 agent 安装？ |
|---|---|---|
| `rtl-design-discipline/` | RTL 设计纪律 Skill（纯文本） | 是 |
| `pynq-overlay-workflow/` | 通用 PYNQ overlay 工作流 Skill（SKILL.md + 参考文档 + Python 工具 + 离线测试） | 是 |
| `ab_eval_pynq/` | 上一项的**验证工具**（对照实验生成、假 PYNQ 判分、统计、安慰剂 Skill） | **否**，只给实验执行人用 |
| `../docs/skill_test_guide_20261030.md` | 10-30 Skill 测试指导表（含 RTL Skill 的最小测试题） | 否 |

## 队友快速上手

```powershell
# 1. 工具层自检（无需板卡/agent；Python>=3.8 + pytest，判分器另需 numpy）
python -m pytest skill/pynq-overlay-workflow/tests -q            # 期望 47 passed
python skill/ab_eval_pynq/harness/skill_mutation_check.py         # 期望 killed 13/13

# 2. 安装给 OpenCode 使用（项目级）
#    复制 skill/pynq-overlay-workflow/ 到 <项目>/.opencode/skills/pynq-overlay-workflow/
#    做对照实验时不要装到全局 ~/.config/opencode/skills，否则"无 Skill"组会受污染

# 3. 对照实验：完整步骤、控制变量与结论措辞见 skill/ab_eval_pynq/README.md
```

## 已交付

| Skill | 来源 | 状态 |
|---|---|---|
| `rtl-design-discipline/` | 队友提出的通病观察（AI 写 Verilog 时对同一逻辑写出一堆等价废话、用打补丁的方式改代码、不关心综合出什么硬件、生成无必要的组合逻辑），2026-10-17 按此要求成形，2026-10-24 收入本目录 | 内容已成形、可直接安装；**在非 Ascon 示例上的对照效果尚未验证（not_validated）** |

### `rtl-design-discipline/`（Hardware-First RTL）

- **依赖/版本**：纯文本，无运行时依赖；宿主为支持 SKILL.md 式 skill 的 agent（Hermes / Claude Code 等）。语言适用范围 Verilog、SystemVerilog、VHDL、Chisel、HLS C++。
- **输入**：一段待写/待改/待评审的 RTL 或 HLS C++，以及其设计意图（寄存器清单、控制/数据通路划分）。
- **输出**：改写后的最小等价电路表达；以及一份「哪些组合逻辑是多余的、哪些条件分支应改成互斥 case」的说明。
- **执行步骤**：先列寄存器清单 → 每个信号的下一值只在一处赋值 → 同子表达式出现 ≥2 次就提具名 wire → 有优先级用 `if-else`、天然互斥用 `case` → 组合块保证完整（防隐式锁存器）→ 改需求时重写整段选择逻辑而不是再包一层。
- **成功判据**（可判定，不靠感觉）：同一语义的表达式在文件内只出现一次；无 `always_comb` 未赋值路径；无「为绕过一个特例而新增的嵌套层」；综合前后 LUT/FF 数量不因"重写"而上升（等价重写应持平或下降）。
- **失效条件**：需要跨模块做**时序**收敛（pblock、复制寄存器、流水级重构）时本 skill 不提供方法，走 Vivado/时序类 skill；需要 SPEC 与验证流程时走 Verilog Design Flow；HLS 具体 pragma 语法走 hls-* 系列。
- **来源案例**：RISC-V 取指单元里 `Mux(redirectNow, redirectNowTarget, …)` 被同义重写三次（不同嵌套层），属于典型漂移风险点。
- **已验证效果**：无。没有做过「同一需求，用/不用本 skill 写两版，比较 LUT/FF/时序」的对照实验，因此不得对外声称它能提升电路质量。要做的话最小实验是：取一个已收敛模块（如 `ascon_round.v` 或 `bypass.v`），让两个 agent 分别按/不按本 skill 实现，比较 LUT/FF 与最差路径——这一步 `not_measured`。

| `pynq-overlay-workflow/` | 2026-10-30 依据本项目 PYNQ 实板/DMA 审计中的真实踩坑（bit/hwh 不配套、COR ap_done、DMA 无界自旋、S2MM 实际长度、缓存一致性、参考时钟假设）与 PYNQ v2.7.0 源码提炼 | L1 工具层通过（47 单元测试、13/13 变异检出）；L2 agent 对照与 L3 实板 **not_run** |

### `pynq-overlay-workflow/`（通用 PYNQ overlay 工作流）

- **覆盖**：Overlay 加载与校验（bit/hwh 哈希、ip_dict/hwh 比对、ID 寄存器、FCLK）；接口契约 → 寄存器驱动 + pytest 骨架、`register_map` 使用范式与 hwh 交叉核对；有界 AXI DMA 与 flush/invalidate 封装、失败缓冲隔离；常见错误形态定位表；黄金参考比对（含诊断提示与变异自检）；性能（cold/warm）与 Vivado 资源/时序报告采集。
- **不绑定题目/板卡**：无 Ascon 地址或长度；示例为 AXI GPIO、HLS vadd、AXI DMA；hwh 解析覆盖 Zynq-7000（真实工件）与 ZynqMP（手写结构样例，非 Vivado 产物）。
- **验证方案**：`skill/ab_eval_pynq/README.md`（三层：工具确定性 / 受控 A/B/安慰剂 agent 实验 / 实板）。

## 预留（尚未实现）

S01–S04 的目标现已由 `pynq-overlay-workflow` 的工具覆盖（loader/register/golden/collector），但"至少一个非 Ascon 实板示例"仍未完成，下表保留为原始需求记录。

状态：尚未实现；本文件是目录交付说明，不是已经验证的可安装 Skill。本阶段不绑定具体 agent 平台或创建插件。

| 任务 | 可复用目标 |
|---|---|
| S01 | overlay loader：板型、bit/hwh、版本与异常检查 |
| S02 | register map helper：参数化地址、位宽、端序 |
| S03 | golden reference checker：可注入参考实现，诊断输出差异 |
| S04 | performance/report collector：可配置指标与证据来源 |
| S05 | 使用说明、适用范围、失效条件、真实验证案例与经验来源 |

以 Y01-Y05 的实际开发经验提炼，10-21 交 P1 验收版（含使用说明），10-27 冻结功能，11-01 前完成提交材料整理。每项必须使用至少一个非 Ascon 示例证明可复用，不能把 Ascon key/nonce 长度、寄存器地址或板卡 image 硬编码进通用层。

最终说明应写出：依赖/版本、输入输出、执行步骤、成功判据、错误与失效条件、支持的平台、已验证效果、来自哪些失败/观察；现在没有可声称的验证效果。
