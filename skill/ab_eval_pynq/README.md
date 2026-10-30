# `pynq-overlay-workflow` Skill 验证方案

owner TBD。本目录是**测量工具**，不是 Skill 本身；不要把它复制到 agent 的试验工作区
（`make_trials.py` 只复制 `skill/pynq-overlay-workflow/` 或安慰剂 Skill）。

## 0. 为什么以前"加不加 Skill 没区别"、而且结论不严谨

| 问题 | 后果 | 本方案的处理 |
|---|---|---|
| 题目太简单（8 位计数器这类） | 天花板效应：基础模型本来就会，两组都 100%，测不出差别 | 题目里埋**陷阱场景**：需求在提示词里写明（两组都知道"要什么"），陷阱考的是"怎么做才真的对" |
| 同一会话/同一 agent 先后测 | 前一次的上下文、已读文件、项目 `AGENTS.md` 污染后一次 | 每次试验 = 一个**全新** `opencode run` + 一个**全新目录**，目录在仓库外（脚本检测到祖先有 `.git`/`AGENTS.md`/`.opencode` 就拒绝） |
| 有无 Skill 之外还有别的差别 | 无法归因 | 三组只差 Skill 文件与 `skill` 权限一条规则；模型、提示词、工具权限、文件完全相同 |
| "加了一段文字就变好"也算 Skill 的功劳 | 混淆"技术内容"与"多了上下文/加载了 Skill" | 加**安慰剂组**：同样长度、同样会被加载、只讲代码风格的 `pynq-style-notes` |
| 每组跑 1 次 | LLM 输出随机，单次结果没有统计意义 | 每组 ≥5 次（推荐 8），随机交错执行顺序，用精确置换检验 |
| 人工看代码打分 | 主观、可被偏好影响 | 自动判分：生成的代码在**假 PYNQ**上跑隐藏场景；诊断题用固定概念规则，另可盲评 |
| 判分器本身没被验证 | 测量工具可能根本分不出好坏 | 先用"好/朴素"两份参考答案验证判分器的区分能力；Skill 工具再做变异测试 |

## 1. 三层验证（层层独立，不能互相替代）

### L1 工具层：确定性，不涉及 LLM（已完成，见第 6 节）
- `python -m pytest skill/pynq-overlay-workflow/tests -q`：47 个离线用例，包括本仓库真实 XC7Z020 release 的 bit/hwh/manifest 与真实 `utilization.rpt`、一份手写 ZynqMP 结构 hwh。
- `python skill/ab_eval_pynq/harness/skill_mutation_check.py`：往工具里注入 13 种典型错误（漏 invalidate、漏 flush、用申请长度代替实际长度、不隔离缓冲、无界等待、只写低 32 位……），每一种都必须让测试失败。

### L2 Agent 层：受控 A/B/安慰剂实验（本目录的 harness，待执行）
回答的问题：**同一模型在只差 Skill 的条件下，写出的 PYNQ 主机代码是否更可靠？**

### L3 实板层（待执行，`not_run`）
在 PYNQ 板上按 Skill 流程走一遍：段 A/B 用本仓库 `board/vivado_zynq7000_xc7z020_pynq/release/`
（已在 L1 离线验证过工件解析）；段 C/D 至少再用一个**非 Ascon** overlay（例如 PYNQ 自带 base overlay 的 AXI GPIO，或一个最小 AXI DMA 回环设计）。只有这一层能证明"在真实硬件上可用"。

## 2. 实验设计（L2）

| 项 | 设定 |
|---|---|
| 组别 | `with`（本 Skill）、`without`（无 Skill，且权限显式拒绝）、`placebo`（风格类 Skill） |
| 固定不变 | 同一 `provider/model`；同一提示词；同一工作区文件；所有组均禁 web、禁读工作区外目录、禁子 agent；默认禁 shell（见下） |
| 任务 | T1 overlay 加载与校验、T2 HLS 核驱动、T3 AXI DMA 流处理、T4 现象诊断（文字） |
| 每题隐藏场景 | T1：扁平/层级 IP 名、旧 hwh、bit 哈希错、ID 错、hwh 非同名；T2：基本、连续调用、残留 done、64 位高字残值、永不完成、单元素；T3：基本、连续、奇数长度、短包、无 TLAST、超过最大传输长度；T4：8 个症状 |
| 主指标（事先登记） | 每次试验的场景通过率（0–1）；组间比较用双侧精确置换检验 + Cliff's δ |
| 次指标 | 全通过率；每个场景分组通过率；卡死（hang）次数；Skill 被实际加载的比例（canary） |
| 顺序 | 所有试验随机打乱后串行执行（种子写入 `design.json`），抵消时间漂移、限流等因素 |

关于 shell：允许 shell 后 agent 能用命令读取任意路径（包括本仓库里的 Skill），破坏隔离。
因此默认对**所有组**禁用 shell（条件相同）。若想让 agent 自测代码，必须在**没有本仓库的机器/账户**上用 `--allow-shell` 运行。

关于全局 Skill：若有人把本 Skill 装进了 `~/.config/opencode/skills`，`without` 组的
`skill * deny` 规则仍会拒绝加载；但执行前仍应确认全局目录里没有它。

关于 canary：试验目录里的 Skill 副本末尾追加一句"使用本 Skill 时在交付文件首行写
`skill-canary`"。判分时据此统计 Skill 是否真被加载（`with` 组没加载的试验要单独报告，不能删除）。

## 3. 执行步骤

```powershell
# 0) 前置：L1 必须全绿
python -m pytest skill/pynq-overlay-workflow/tests -q
python skill/ab_eval_pynq/harness/skill_mutation_check.py

# 1) 判分器自检：好答案应满分，朴素答案应在陷阱上失败
python skill/ab_eval_pynq/harness/grade.py --task t3_dma --solution skill/ab_eval_pynq/harness/selftest/t3_dma/good
python skill/ab_eval_pynq/harness/grade.py --task t3_dma --solution skill/ab_eval_pynq/harness/selftest/t3_dma/naive

# 2) 生成试验（目录必须在仓库外；模型用实际 provider/model）
python skill/ab_eval_pynq/harness/make_trials.py --root D:\ab_trials\run1 --reps 5 --model <provider/model>

# 3) 执行（先用 `opencode run --help` 确认本机 CLI 版本的用法；每个试验一个新进程）
powershell -ExecutionPolicy Bypass -File D:\ab_trials\run1\run_all.ps1

# 4) 判分与统计
python skill/ab_eval_pynq/harness/grade.py --root D:\ab_trials\run1
python skill/ab_eval_pynq/harness/stats.py D:\ab_trials\run1\results.csv
```

规模：4 题 × 3 组 × 5 次 = 60 次 `opencode run`。若时间不够，先做 T3 + T1（陷阱最多）× 3 组 × 5 次。

## 4. 样本量与判读

- 每组 n=5 时，置换检验能达到的最小 p 约为 0.008（两组完全分开）；n=2 最小只有 0.33，**不足以下结论**。推荐每组 8 次。
- 事先确定：主指标 = T1–T3 的场景通过率；显著性 α=0.05；同时报告效应量。不要跑完后再挑对自己有利的指标或删除试验。
- 判读规则：
  - `with` > `without` 且 `with` > `placebo` 显著 → 可以说"Skill 的技术内容提升了该模型在这些 PYNQ 任务上的正确率"。
  - `with` ≈ `placebo` > `without` → 提升来自"多一份上下文/被提醒"，不是 Skill 的具体内容。
  - 无显著差异 → 如实写"在本任务集与该模型上未测到差异"，这也是有效结果。
- 看**每个场景**的分组通过率，找出 Skill 真正起作用（或没起作用）的规则，用于改进 Skill。
- 防过拟合：T1–T4 是与 Skill 同时设计的（开发集）。对外宣称前，请一位**没读过 Skill** 的队友另写 1–2 个留出任务（例如 AXI GPIO 中断、AXI BRAM 读写），只跑一次正式实验，不再根据结果修改 Skill。

## 5. 结论措辞（必须遵守）

- 只写实际测到的：模型名/版本、日期、n、任务、p 值与效应量、失败与未加载的试验。
- 假 PYNQ 上的结果是 `simulated`，只能说明"代码在模拟的硬件行为下是否正确"，不能写成板级通过。
- L3 未完成前，Skill 在真实硬件上的效果写 `not_measured`。

## 6. 本轮已完成的证据（2026-10-30，本机 Windows，Python 3.13.9，pytest 8.4.2，numpy 2.3.5）

| 检查 | 命令 | 结果 |
|---|---|---|
| 工具单元测试 | `python -m pytest skill/pynq-overlay-workflow/tests -q` | 47 passed，0 skipped（含真实 release 工件） |
| 工具变异测试 | `python skill/ab_eval_pynq/harness/skill_mutation_check.py` | 13/13 killed，exit 0（第一次运行发现 HLS 测试假模型错误地丢掉残留 done，修复后通过；另有一个等价变异被替换为有意义的变异） |
| 判分器区分能力 | `grade.py --solution selftest/<task>/<good|naive>` | good：6/6、6/6、6/6、8/8；naive：T1 3/6、T2 0/6、T3 3/6、T4 0/8，失败都落在设计的陷阱上 |
| 流程连通性 | `make_trials.py`（仓库内拒绝；仓库外 18 个试验）→ 用参考答案代替 agent 输出 → `grade.py` → `stats.py` | 连通；n=2 时 p=0.33，印证第 4 节样本量要求。**这是管线自检，不是 Skill 效果数据** |
| L2 真实 agent 实验 | — | `not_run` |
| L3 实板 | — | `not_run` |

## 7. 已知局限

- 假 PYNQ 是行为模型：DMA 中间没有流 FIFO（先发并等待发送完成再启动接收会卡住）、HLS 核在 2 ms 后完成、地址越界时核挂起。这些假设写在 `harness/fake_pynq/pynq/__init__.py` 中。
- T4 的概念规则较粗，可能误判措辞不同的正确答案；对外报告前建议两人按同一规则盲评复核。
- 模型温度在 OpenCode V2 中无法通过 agent 配置下发，因此依靠重复次数控制随机性。
- 只测一个模型的结果不能推广到其他模型。
