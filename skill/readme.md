# 通用 Skill 交付目录

本目录存放可复用 Skill 的**受控副本**（不是本工程的运行时依赖，也不绑定具体 agent 平台）。
下表的状态栏只写已验证的事实；没有验证证据的一律写 `not_validated`。

2026-10-30 状态：P0/P1 实板主链已完成，但 S01-S05 的通用 PYNQ Skill 仍未实现，
S05 尚无验收版说明。`rtl-design-discipline` 只保留一次非 Ascon 8-bit counter 的
受限功能样例；复核发现模型身份、A/B 提示词和 oracle 独立性等问题，验证已停止，
状态为 `STOPPED_INCONCLUSIVE`。不得据此宣传资源或广泛质量提升。

## 已交付

| Skill | 来源 | 状态 |
|---|---|---|
| `rtl-design-discipline/` | 队友提出的通病观察（AI 写 Verilog 时对同一逻辑写出一堆等价废话、用打补丁的方式改代码、不关心综合出什么硬件、生成无必要的组合逻辑），2026-10-17 按此要求成形，2026-10-24 收入本目录 | **单次非 Ascon counter 功能样例保留；验证已停止；Skill 效果 inconclusive；资源 not_measured；广泛通用性 not_proven** |

### `rtl-design-discipline/`（Hardware-First RTL）

- **依赖/版本**：纯文本，无运行时依赖；宿主为支持 SKILL.md 式 skill 的 agent（Hermes / Claude Code 等）。语言适用范围 Verilog、SystemVerilog、VHDL、Chisel、HLS C++。
- **输入**：一段待写/待改/待评审的 RTL 或 HLS C++，以及其设计意图（寄存器清单、控制/数据通路划分）。
- **输出**：改写后的最小等价电路表达；以及一份「哪些组合逻辑是多余的、哪些条件分支应改成互斥 case」的说明。
- **执行步骤**：先列寄存器清单 → 每个信号的下一值只在一处赋值 → 同子表达式出现 ≥2 次就提具名 wire → 有优先级用 `if-else`、天然互斥用 `case` → 组合块保证完整（防隐式锁存器）→ 改需求时重写整段选择逻辑而不是再包一层。
- **成功判据**（可判定，不靠感觉）：同一语义的表达式在文件内只出现一次；无 `always_comb` 未赋值路径；无「为绕过一个特例而新增的嵌套层」；综合前后 LUT/FF 数量不因"重写"而上升（等价重写应持平或下降）。
- **失效条件**：需要跨模块做**时序**收敛（pblock、复制寄存器、流水级重构）时本 skill 不提供方法，走 Vivado/时序类 skill；需要 SPEC 与验证流程时走 Verilog Design Flow；HLS 具体 pragma 语法走 hls-* 系列。
- **来源案例**：RISC-V 取指单元里 `Mux(redirectNow, redirectNowTarget, …)` 被同义重写三次（不同嵌套层），属于典型漂移风险点。
- **验证结论（2026-10-30）**：历史记录中，显式提供 Skill 生成的非 Ascon
  `counter8` 通过冻结 TB（1,046 cycles）和一次故障注入；无 Skill 对照组也通过。
  复核发现模型身份记录不一致、A/B 提示词存在方法暗示、oracle 作者不独立等问题，
  因此验证停止，整体结论 `inconclusive`。未做综合，LUT/FF/时序为 `not_measured`；
  Skill discovery 和广泛通用性均未验证。停止说明见
  `data/skill/results/20261030_validation_stop.md`。

## 预留（尚未实现）

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
