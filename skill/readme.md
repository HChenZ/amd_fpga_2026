# 通用 Skill 交付目录

2026-10-29 最新交付选择：11-01提交；10-30优先测试已有 `rtl-design-discipline`，
见 `docs/skill_test_guide_20261030.md`。当前仅确认文本内容，实际效果仍待测试。
2026-10-30 新增 `pynq-overlay-workflow`（通用 PYNQ Skill），当日仅工具层离线验证（历史状态，已被下行更新）。
2026-10-31 更新：`pynq-overlay-workflow` 的 L2 agent 对照已跑完（`simulated`，4 题 × 3 组 × 5 次 + 留出任务），
实板 L3 session `l3_20261031_063709` 已全部 `PASS`；S01–S03 已有实证。S05 的独立复现由未参与编写 Skill 的
HChenZ 按本文档完成 L1–L3（见下文"验证案例"）。S04 已补可配置指标 schema 与非 Ascon 数据示例（离线验证，见下文）。

本目录存放可复用 Skill 的**受控副本**（不是本工程的运行时依赖，也不绑定具体 agent 平台）。
下表的状态栏只写已验证的事实；没有验证证据的一律写 `not_validated`。

2026-10-29 状态（历史记录）：P0/P1 实板主链已完成，当时 S01-S05 的通用 PYNQ Skill 尚未实现。
2026-10-31 更新：`rtl-design-discipline` 的对照效果仍为 `not_validated`；`pynq-overlay-workflow` 已完成
L1/L2/L3，结论边界见下文。

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
python -m pytest skill/pynq-overlay-workflow/tests -q            # 期望 63 passed（10-30 版本为 47）
python skill/ab_eval_pynq/harness/skill_mutation_check.py         # 期望 killed 16/16（10-30 版本为 13/13）

# 2. 安装给 OpenCode 使用（项目级）
#    复制 skill/pynq-overlay-workflow/ 到 <项目>/.opencode/skills/pynq-overlay-workflow/
#    做对照实验时不要装到全局 ~/.config/opencode/skills，否则"无 Skill"组会受污染

# 3. 对照实验：完整步骤、控制变量与结论措辞见 skill/ab_eval_pynq/README.md
```

## 已交付

| Skill | 来源 | 状态 |
|---|---|---|
| `rtl-design-discipline/` | 队友提出的通病观察（AI 写 Verilog 时对同一逻辑写出一堆等价废话、用打补丁的方式改代码、不关心综合出什么硬件、生成无必要的组合逻辑），2026-10-17 按此要求成形，2026-10-24 收入本目录 | 内容已成形、可直接安装；**在非 Ascon 示例上的对照效果尚未验证（not_validated）** |
| `pynq-overlay-workflow/` | 2026-10-30 依据本项目 PYNQ 实板/DMA 审计中的真实踩坑（bit/hwh 不配套、COR ap_done、DMA 无界自旋、S2MM 实际长度、缓存一致性、参考时钟假设）与 PYNQ v2.7.0 源码提炼 | L1 通过；L2 完成（`simulated`，T5 未复现）；L3 `l3_20261031_063709` PASS；S05 独立复现已完成；S04 可配置报告与非 Ascon 数据示例离线通过（报告工具本身未在板上运行） |

### `rtl-design-discipline/`（Hardware-First RTL）

- **依赖/版本**：纯文本，无运行时依赖；宿主为支持 SKILL.md 式 skill 的 agent（Hermes / Claude Code 等）。语言适用范围 Verilog、SystemVerilog、VHDL、Chisel、HLS C++。
- **输入**：一段待写/待改/待评审的 RTL 或 HLS C++，以及其设计意图（寄存器清单、控制/数据通路划分）。
- **输出**：改写后的最小等价电路表达；以及一份「哪些组合逻辑是多余的、哪些条件分支应改成互斥 case」的说明。
- **执行步骤**：先列寄存器清单 → 每个信号的下一值只在一处赋值 → 同子表达式出现 ≥2 次就提具名 wire → 有优先级用 `if-else`、天然互斥用 `case` → 组合块保证完整（防隐式锁存器）→ 改需求时重写整段选择逻辑而不是再包一层。
- **成功判据**（可判定，不靠感觉）：同一语义的表达式在文件内只出现一次；无 `always_comb` 未赋值路径；无「为绕过一个特例而新增的嵌套层」；综合前后 LUT/FF 数量不因"重写"而上升（等价重写应持平或下降）。
- **失效条件**：需要跨模块做**时序**收敛（pblock、复制寄存器、流水级重构）时本 skill 不提供方法，走 Vivado/时序类 skill；需要 SPEC 与验证流程时走 Verilog Design Flow；HLS 具体 pragma 语法走 hls-* 系列。
- **来源案例**：RISC-V 取指单元里 `Mux(redirectNow, redirectNowTarget, …)` 被同义重写三次（不同嵌套层），属于典型漂移风险点。
- **已验证效果**：无。没有做过「同一需求，用/不用本 skill 写两版，比较 LUT/FF/时序」的对照实验，因此不得对外声称它能提升电路质量。要做的话最小实验是：取一个已收敛模块（如 `ascon_round.v` 或 `bypass.v`），让两个 agent 分别按/不按本 skill 实现，比较 LUT/FF 与最差路径——这一步 `not_measured`。

### `pynq-overlay-workflow/` 的 L2 结果（2026-10-31，`simulated`，不可当板级结论）

- 模型 `deepseek/deepseek-flash`，4 题（overlay 加载、HLS 核、AXI DMA、现象诊断）× 3 组 × 5 次 = 60 次
  `opencode run`（另加 5 次复跑），全部 `exit=0`。canary 证明 `with` 20/20、`placebo` 20/20、`without` 0/20。
- 主指标（预注册 = T1–T3 场景通过率，n=15/组）：`with` 1.000（15/15 全通过）、`without` 0.833、
  `placebo` 0.844；`with` vs `without` p=0.0425、δ=+0.33；`with` vs `placebo` p=0.2248（不显著）。
- 留出任务 `t5_bram`（15 次）：`with` 1.000 vs `without`/`placebo` 0.800，**p=1.0，未复现差异**。
- 可以说"在该任务集与该模型上，加载 Skill 的组全部通过并显著优于无 Skill 组"；**不能**说
  "技术内容被证明是提升来源"，也**不能**说"已证明可泛化"。实板效果 `not_measured`。
- 明细：`ab_eval_pynq/README.md` 6.1/6.2、`ab_eval_pynq/holdout/t5_bram_design.md`、
  `ab_eval_pynq/results/l2_20261030_deepseek-flash/`。

### `pynq-overlay-workflow/`（通用 PYNQ overlay 工作流）

- **覆盖**：Overlay 加载与校验（bit/hwh 哈希、ip_dict/hwh 比对、ID 寄存器、FCLK）；接口契约 → 寄存器驱动 + pytest 骨架、`register_map` 使用范式与 hwh 交叉核对；有界 AXI DMA 与 flush/invalidate 封装、失败缓冲隔离；常见错误形态定位表；黄金参考比对（含诊断提示与变异自检）；性能（cold/warm）与 Vivado 资源/时序报告采集。
- **不绑定题目/板卡**：无 Ascon 地址或长度；示例为 AXI GPIO、HLS vadd、AXI DMA；hwh 解析覆盖 Zynq-7000（真实工件）与 ZynqMP（手写结构样例，非 Vivado 产物）。
- **验证方案**：`skill/ab_eval_pynq/README.md`（三层：工具确定性 / 受控 A/B/安慰剂 agent 实验 / 实板）。
- **依赖/版本**：Python ≥3.8，工具只用标准库；离线测试需 pytest；板上需 PYNQ（实测 2.7.0）。宿主为支持
  SKILL.md 的 agent（实测 OpenCode v2.2.2）。
- **输入**：`.bit`/`.hwh`（及可选哈希 manifest）、IP 的接口契约 JSON（格式见 `pynq-overlay-workflow/references/contract_format.md`）、
  待搬运的数据与独立黄金参考、可选的 Vivado `report_utilization`/`report_timing_summary` 文件。
- **输出**：通过/失败的校验报告（列出全部问题）、由契约生成的驱动与 pytest 骨架、DMA 实际接收长度与解码后的 DMASR、
  带诊断提示的比对结果、Markdown+JSON 报告（每个数值带 measured/simulated/estimated/not_measured）。
- **执行步骤**：工件哈希 → 下载 → ip_dict/hwh/ID/FCLK 读回 → 契约生成寄存器访问 → 有界的 MMIO/DMA 搬运
  （flush/invalidate、实际长度、失败先停再释放）→ 黄金比对（边界+随机+背靠背+哨兵+变异）→ 报告。详见 `SKILL.md` 第 0–5 节。
- **成功判据**：五段门禁全部通过；每个等待有 deadline；至少一个故意制造的错误能被比对检出；报告中无未标注证据级别的数值。
- **错误与失效条件**：不覆盖 Scatter-Gather/micro DMA（工具会拒绝）、Versal/RFSoC 专有 IP、PetaLinux/设备树定制、
  RTL/HLS 内部设计与时序收敛。Python 层无法打断一次不返回的 MMIO 访问（AXI 从口不应答时只能修硬件）。
  FCLK 读回值依赖 PYNQ 的参考时钟假设，只能当作推算值。
- **支持平台**：实板为 Zynq-7000（armv7l，PYNQ 2.7.0 镜像，内核 5.4.0-xilinx-v2020.2；板型字段未采集，记 `not_available`）。
  ZynqMP 仅用手写结构的 hwh 样例做过离线解析，**未上板**。
- **来源**：本项目的真实失败（PS 直写共享 BRAM 读到旧数据、RX FIFO 溢出、busy/done 归属错、PUF key 源被静默替换、
  PYNQ 2.7 DMA 驱动无界自旋、hwh 中 33.333 MHz 与 PYNQ 50 MHz 参考时钟假设不一致），见 `project_log/lessons_learned.md`
  与 `board/vivado_zynq7000_xc7z020_pynq_dma_cpu/pynq27_audit.md`；PYNQ v2.7.0 `pynq.lib.dma`/`pynq.buffer` 源码；AMD PG021、PG144。

#### 验证案例（全部可追溯到仓库内原始文件）

| 层 | 案例 | 结果 | 证据 |
|---|---|---|---|
| L1 | 离线单元测试（含本仓库真实 release bit/hwh/manifest、真实 utilization 报告）；注入错误 | 10-30 版 47 passed、13/13；10-31 加 S04 后 63 passed、16/16 | `pynq-overlay-workflow/tests/`、`ab_eval_pynq/harness/skill_mutation_check.py` |
| L2 | deepseek-flash，4 题 × 3 组 × 5 次 + 留出题 T5 | 见上节；`simulated` | `ab_eval_pynq/results/l2_20261030_deepseek-flash/` |
| L3-0 | 实板预检：依赖、Skill 文件树哈希冻结、release 工件、篡改 manifest 被拒绝 | 7/7 PASS | `data/skill/l3_20261031_063709/00_preflight.json` |
| L3-A/B | 本项目 Ascon release 的加载与身份校验（控制/邮箱 ID、非模拟服务、固件自检） | 9/9 PASS，`hardware_measured` | `.../10_ascon_release.json` |
| L3-C | **非 Ascon**：PYNQ BaseOverlay 的 AXI GPIO（`leds_gpio`）寄存器读写、恢复原值、hwh 交叉核对、错误契约被拒绝 | 8/8 PASS，`hardware_measured` | `.../20_non_ascon_gpio.json` |
| L3-D | **非 Ascon**：自建 AXI DMA 回环 overlay，长度 8/9/16/64/256 与重复传输、超长在启动前拒绝、比对器能检出错误、出错后恢复到 halted | 26/26 PASS，`hardware_measured` | `.../30_non_ascon_dma.json`、`board/vivado_zynq7000_xc7z020_axi_dma_loopback/` |

L3 未覆盖：短包与缺 TLAST 两个 DMA 场景（需要专用 PL 源，或会故意让正式路径卡住），记 `not_tested`；
报告采集工具未在板上运行，板上吞吐量未采集。

#### S04 报告采集（2026-10-31，离线）

- 新增：可配置指标 schema（`pynq-overlay-workflow/references/report_schema.md`）、`report --schema/--source` 命令、
  `tool_report` 证据级别（Vivado 报告数值与板上实测分开）、估算必须写依据、缺失项一律 `not_measured`、必需指标缺失时 exit 1。
- 非 Ascon 数据示例：`examples/report_schema.dma_loopback.json` 把 AXI DMA 回环工程的真实 Vivado 报告与 L3 实板结果
  合成一份报告，16 个指标：LUT 2436 / FF 3333 / BRAM 2 / 锁存器 0、WNS +1.736 ns / WHS +0.025 ns（`tool_report`）；
  6 次传输共 369 B 且全部比对通过（`measured`）；吞吐量 `not_measured`（该次实板运行未采集）；理论流峰值 400 MB/s（`estimated`，带依据）。
  输出归档：`data/skill/s04_report_dma_loopback/`。
- 验证：`tests/test_report_schema.py` 16 个用例（schema 校验、缺失/必需、汇总、CLI 退出码、真实非 Ascon 数据），
  变异检查新增 3 项（缺失被标成实测、必需缺失不报错、估算无依据被接受）全部检出。
- **版本边界**：L2/L3 验证的是提交 `7bc1abf` 的 Skill（L3 预检冻结了文件树哈希）。S04 只新增/扩展了
  `report.py`、CLI、文档与测试，未改 loader/regmap/DMA/golden；这部分新增内容只有离线验证，没有重跑 L2/L3。

#### 陌生使用者复现（S05 验收）

HChenZ 未参与本 Skill 的编写，仅依据 `skill/readme.md`、`pynq-overlay-workflow/SKILL.md` 与
`ab_eval_pynq/README.md`，独立完成了 L1 自检、L2 全部对照实验、L3 四项实板验证，并归档原始数据
（提交 `6094734`、`1a44b92`、`cd5276d`、`63b39f9`）。

## 原始需求 S01–S05 与现状

S01–S03 已由 L3 的 Ascon release、非 Ascon AXI GPIO 和 AXI DMA 回环实板实例验证；
S04 的可配置报告与非 Ascon 数据示例、S05 的使用说明与陌生使用者复现均见上文。

下表保留为原始需求记录。

| 任务 | 可复用目标 |
|---|---|
| S01 | overlay loader：板型、bit/hwh、版本与异常检查 |
| S02 | register map helper：参数化地址、位宽、端序 |
| S03 | golden reference checker：可注入参考实现，诊断输出差异 |
| S04 | performance/report collector：可配置指标与证据来源 |
| S05 | 使用说明、适用范围、失效条件、真实验证案例与经验来源 |

以 Y01-Y05 的实际开发经验提炼，10-21 交 P1 验收版（含使用说明），10-27 冻结功能，11-01 前完成提交材料整理。每项必须使用至少一个非 Ascon 示例证明可复用，不能把 Ascon key/nonce 长度、寄存器地址或板卡 image 硬编码进通用层。

最终说明应写出：依赖/版本、输入输出、执行步骤、成功判据、错误与失效条件、支持的平台、已验证效果、来自哪些失败/观察。
`pynq-overlay-workflow` 已按此写在上文；`rtl-design-discipline` 仍没有可声称的验证效果。
