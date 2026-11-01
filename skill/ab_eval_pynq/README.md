# `pynq-overlay-workflow` Skill 验证方案

> 2026-11-01 职责：独立通用 Skill 验证，不是 PUF3 的硬件回归。冻结 L3 的 Ascon 工件为旧 v1
> （pynq-svc-v1），另有 Base GPIO/DMA 回环；L2 为 simulated。不能靠把路径/哈希换成 PUF3 复用旧通过结论。
> 本轮不改实验、判分器、SKILL.md 或已执行 Notebook；新增运行要按实际版本重新取证。

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

### L2 Agent 层：受控 A/B/安慰剂实验（本目录的 harness；2026-10-30~31 已跑完 T1–T4，结果见 6.1）
回答的问题：**同一模型在只差 Skill 的条件下，写出的 PYNQ 主机代码是否更可靠？**

### L3 实板层（2026-10-31 `PASS`）
在 PYNQ 板上按 Skill 流程走一遍：段 A/B 用本仓库 `board/vivado_zynq7000_xc7z020_pynq/release/`
（已在 L1 离线验证过工件解析）；段 C/D 至少再用一个**非 Ascon** overlay（例如 PYNQ 自带 base overlay 的 AXI GPIO，或一个最小 AXI DMA 回环设计）。只有这一层能证明"在真实硬件上可用"。

L2 结果不改变 L3 的判定对象：L2 是 `simulated` Agent 对照，且 `with vs placebo`
不显著、T5 留出未复现，因此 L3 仍采用人工单组功能验证，不做 L3 A/B，也不能用来补证
Skill 的因果提升或泛化。L3 预检记录会增加实际执行 Notebook、`src/pynq` 依赖、Skill
脚本树和 L2 归档的 SHA-256；因板端工作树可能 dirty，`git HEAD` 不再单独作为源码指纹。

实际 L3 session `l3_20261031_063709` 的 preflight、Ascon release、非 Ascon GPIO、
非 Ascon AXI DMA loopback 与汇总全部 PASS；59 项 PASS、1 项 NOT_APPLICABLE、
0 FAIL/ERROR/MISSING。`short_output` 和 `missing_tlast` 仍需专用故障源，标为
`not_tested`。

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

关于提示词补一句（2026-10-30 修订，跑正式批次前登记）：冒烟试验（`with` 组、T1、1 次）显示
模型能列出并加载 Skill，但在真实任务里**不会主动加载**（transcript 无 `skill` 调用，交付文件无
canary），因此 `with` 组会退化成 `without` 组。为此 `make_trials.py` 的 `PROMPT_SUFFIX` 会在
**三组**的 `PROMPT.md` 末尾追加同一句中性提示"若当前环境提供了与本任务相关的 Skill，请先加载它
并按其流程执行"。三组文本仍完全相同（`without` 组没有可用 Skill，这句话对它无作用），故只差
Skill 文件与该条权限规则的归因不变。这条修订必须写进报告，且不得在看完正式结果后再改提示词。

## 3. 执行步骤

```powershell
# 0) 前置：L1 必须全绿
python -m pytest skill/pynq-overlay-workflow/tests -q
python -m pytest skill/ab_eval_pynq/harness/tests -q      # 假 PYNQ 的 API 覆盖面
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
- L3 真实硬件功能已经通过；Skill 对硬件任务的统计效果仍写 `not_measured`。

## 6. 本轮已完成的证据（2026-10-30，本机 Windows；L1 轮 Python 3.13.9 / pytest 8.4.2 / numpy 2.3.5，L2 轮 Python 3.14.0 / pytest 9.0.3 / numpy 2.5.4）

| 检查 | 命令 | 结果 |
|---|---|---|
| 工具单元测试 | `python -m pytest skill/pynq-overlay-workflow/tests -q` | 47 passed，0 skipped（含真实 release 工件） |
| 假 PYNQ API 测试 | `python -m pytest skill/ab_eval_pynq/harness/tests -q` | 5 passed（`Bitstream` 不下载/计数、`Overlay` 继承、`hierarchy_dict`、`device`、`hash`、与 `Overlay` 字节一致） |
| 工具变异测试 | `python skill/ab_eval_pynq/harness/skill_mutation_check.py` | 13/13 killed，exit 0（第一次运行发现 HLS 测试假模型错误地丢掉残留 done，修复后通过；另有一个等价变异被替换为有意义的变异） |
| 判分器区分能力 | `grade.py --solution selftest/<task>/<good|naive>` | good：6/6、6/6、6/6、8/8；naive：T1 3/6、T2 0/6、T3 3/6、T4 0/8，失败都落在设计的陷阱上 |
| 流程连通性 | `make_trials.py`（仓库内拒绝；仓库外 18 个试验）→ 用参考答案代替 agent 输出 → `grade.py` → `stats.py` | 连通；n=2 时 p=0.33，印证第 4 节样本量要求。**这是管线自检，不是 Skill 效果数据** |
| L2 真实 agent 实验 | `make_trials.py --tasks t1_overlay,t2_hls,t3_dma,t4_diagnose --reps 5` → `run_all.ps1` → `grade.py` → `stats.py` | `done`（4 题 60 次 + T1×placebo 复跑 5 次，65/65 exit=0），结果见 6.1 |
| L2 冒烟（配置生效性） | 单次 `with` 试验 + 环境自检探针 | agent=`trial`、模型=deepseek-flash、shell 拒绝（模型报 `NO-SHELL`）、Skill 可列出并可加载、canary 写入成功 |
| 留出任务（防过拟合） | `t5_bram`（AXI BRAM：字节读-改-写、窗口容量、连续调用）→ `run3` | `done`（15/15 exit=0）；`with` 1.000 vs `without`/`placebo` 0.800，p=1.0 → **未复现主实验差异**，见 6.2 |
| L3 实板 | `test_board/` session `l3_20261031_063709` | **PASS**：Ascon、GPIO、DMA 全 PASS，`hardware_measured` |

### 6.1 L2 真实 agent 实验（2026-10-30 ~ 10-31，`simulated`）

- 环境：Windows 11，Python 3.14.0（`D:\Application\Python\Python314`，pytest 9.0.3 / numpy 2.5.4），
  opencode v2.2.2，模型 `providerID/modelID = deepseek/deepseek-flash`（三组相同）。
- 规模：4 题（T1/T2/T3/T4）× `with`/`without`/`placebo` × 5 次 = **60 次 `opencode run`**，分两批执行
  （第一批 T1+T3，`ab_trials\run1`；第二批 T2+T4，`ab_trials\run2`），每批内随机交错顺序；另加 T1×placebo
  修复仪器后的 5 次复跑（`run1_fix_t1_placebo`）。每个试验独立进程 + 仓库外独立目录；
  `65/65 exit=0`，判分超时（20 s/场景）内**无 hang**。
- 试验数据：`ab_trials\run1\`、`ab_trials\run2\`、`ab_trials\run1_fix_t1_placebo\`（各自 `design.json`
  记录 seed 20261030、顺序、`allow_shell=false`）。仓库内只归档汇总 CSV，不留原始 transcript。
- 操作检查（canary，次指标）：`with` **20/20** 加载（`pynq-overlay-workflow`）、`placebo` **20/20**
  （`pynq-style-notes`）、`without` **0/20** → 三组确只差 Skill。`pynq_skill` 辅助库被引用 0/60。

主指标（第 2 节预注册）= **T1–T3** 的场景通过率。下表是**修复仪器后**的最终数据：T1 的 `placebo` 换成
修复后重跑的 5 次（`run1_fix_t1_placebo`），其余用修复后的判分器重判（`results_final.csv`；只有 1 个旧试验
的分数变化，见"仪器缺口"）。

| 任务 | with | without | placebo | with vs without | with vs placebo | placebo vs without |
|---|---|---|---|---|---|---|
| T1 overlay | 1.000（5/5 全通过） | 0.933（4/5） | 0.900（4/5） | +0.067，p=1.0000，δ=+0.20 | +0.100，p=1.0000，δ=+0.20 | −0.033，p=1.0000，δ=−0.04 |
| T2 HLS | 1.000（5/5） | 1.000（5/5） | 1.000（5/5） | 0.000，p=1.0000，δ=0.00 | 0.000，p=1.0000，δ=0.00 | 0.000，p=1.0000，δ=0.00 |
| T3 DMA | 1.000（5/5） | 0.567（1/5） | 0.633（3/5） | **+0.433，p=0.0476，δ=+0.80** | +0.367，p=0.4444，δ=+0.40 | +0.067，p=0.7778，δ=+0.24 |
| **T1–T3 合并（主指标，n=15/组）** | **1.000（15/15）** | 0.833（10/15） | 0.844（12/15） | **+0.167，p=0.0425，δ=+0.33** | +0.156，p=0.2248，δ=+0.20 | +0.011，p=1.0000，δ=+0.10 |
| T4 诊断（文字，次指标） | 1.000（5/5） | 0.900（1/5） | 0.825（0/5） | +0.100，p=0.0476，δ=+0.80 | **+0.175，p=0.0079，δ=+1.00** | −0.075，p=0.2778，δ=−0.52 |
| T1–T4 合并（探索性，n=20/组） | **1.000（20/20）** | 0.850（11/20） | 0.840（12/20） | **+0.150，p=0.0014，δ=+0.45** | **+0.160，p=0.0030，δ=+0.40** | −0.010，p=0.9283，δ=+0.03 |

T2 是**天花板**：三个组在 6 个场景上都是 30/30，没有任何一个组失败，所以这道题对该模型没有区分度，
它的 1.000 会把合并效应量稀释（合并 δ 从 T1+T3 的 +0.50 降到 T1–T3 的 +0.33）。T4 的区分点集中在
Q6（ap_done 是 clear-on-read，轮询前打印过 CTRL 会吃掉完成位）：`with` 5/5、`without` 1/5、`placebo` 1/5；
`placebo` 另有 Q5（FCLK 参考时钟）2/5 失败、Q2（wait 不返回）1/5 失败。

主指标判读（严格按第 4 节预注册规则）：

- `with` 显著优于 `without`（T1–T3 p=0.0425，δ=+0.33；T3 单独 p=0.0476，δ=+0.80），`placebo` 与
  `without` 无差异（p=1.0，δ=+0.10）→ 方向与"Skill 技术内容有用"一致。
- 但主指标下 `with` vs `placebo` **未达显著**（p=0.2248，δ=+0.20）。按第 4 节规则，**不能**宣称
  "提升来自 Skill 的具体技术内容"已被证实；只能说 n=5 时检验力不足、方向一致。
- T4（次指标，文字题、规则较粗）上 `with` 与 `placebo` 完全分离（p=0.0079 = n=5 可达最小 p，δ=+1.00）；
  把它并入 T1–T4 的探索性合并后 `with` vs `placebo` 才显著（p=0.0030）。**这不是主指标结论**，
  且 T4 判分是正则概念匹配，存在误判风险，不能据此对外宣称。
- 可写的事实：`with` 组 20/20 试验、T1–T3 的 18 个场景、T4 的 8 个问答全部通过（无失败）；
  `without` 的失败集中在 DMA 缓存一致性、未启动 S2MM、超最大传输未切分、`short_output` 少字节、
  以及 T4 的 clear-on-read；`placebo` 的失败在同类陷阱，另加一次先发后收超时（无流 FIFO）。

失败归类（最终数据共 40 条非 pass 行，全部为 `fail`，无 `hang`/`missing`）：

| 组 | 主要原因 |
|---|---|
| without | 缓存未 invalidate、DMA 未启动、超长传输未切分、奇长度未对齐、短包少字节；T4 的 clear-on-read 与时钟参考 |
| placebo | 同上，另有 1 次先发后收（无流 FIFO 时超时） |
| with | 无 |

仪器缺口与修正（必须随结论一起报告）：

- 首轮判分发现 `fake_pynq` 缺 `pynq.Bitstream`（真实 PYNQ 2.7 有，且 `Overlay` 本身就继承 `Bitstream`），
  `t1_overlay/placebo/rep04` 用"先 `Bitstream` 校验再下载"的正确写法却被 `ImportError` 判 0 分；
  同一解法用到的 `overlay.hierarchy_dict` / `overlay.device` 也不存在。这是测量工具保真度缺口，
  不是模型错误。
- 修正：`fake_pynq` 增加 `Bitstream`（构造不下载、只有 `download()` 计数），让 `Overlay` 继承
  `Bitstream`（`hash`/`timestamp`/`downloaded`），补 `hierarchy_dict`（嵌套 `ip`/`hierarchies`）与
  `device`；新增 `harness/tests/test_fake_pynq_api.py`（5 例）钉住这些 API。判分器区分度复核未变：
  T1/T3 good 6/6、naive 3/6，T2 good 6/6 / naive 0/6，T4 good 8/8 / naive 0/8。
- 影响：用修复后的判分器重判旧批次，只有 `t1_overlay/placebo/rep04` 从 0.000 变为 1.000（其余
  29 个试验逐场景不变）；旧 placebo 合并均值因此 0.683 → 0.783，`with` vs `placebo` 的 p 从 0.0867
  升到 0.2105，差异比首轮更不显著。随后按用户要求重跑 T1 的 placebo 5 次（0.900）作为最终数据。
- L2 后已完成首个留出任务和 L3 实板功能验证；L2 数字仍是 `simulated` 且未泛化。

每个场景的分组通过率（每组 5 次）：
| 场景 | with | without | placebo |
|---|---|---|---|
| T1 good_flat | 5/5 | 4/5 | 4/5 |
| T1 good_hierarchy | 5/5 | 4/5 | 4/5 |
| T1 stale_hwh | 5/5 | 5/5 | 5/5 |
| T1 bad_bit | 5/5 | 5/5 | 5/5 |
| T1 wrong_id | 5/5 | 5/5 | 4/5 |
| T1 hwh_not_sibling | 5/5 | 5/5 | 5/5 |
| T2 basic | 5/5 | 5/5 | 5/5 |
| T2 back_to_back | 5/5 | 5/5 | 5/5 |
| T2 stale_done | 5/5 | 5/5 | 5/5 |
| T2 addr_high_word_dirty | 5/5 | 5/5 | 5/5 |
| T2 never_done | 5/5 | 5/5 | 5/5 |
| T2 single_element | 5/5 | 5/5 | 5/5 |
| T3 basic | 5/5 | 3/5 | 3/5 |
| T3 back_to_back | 5/5 | 3/5 | 3/5 |
| T3 odd_length | 5/5 | 3/5 | 3/5 |
| T3 short_output | 5/5 | 2/5 | 3/5 |
| T3 no_tlast | 5/5 | 4/5 | 4/5 |
| T3 larger_than_max_transfer | 5/5 | 2/5 | 3/5 |
| T4 Q1 | 5/5 | 5/5 | 5/5 |
| T4 Q2 | 5/5 | 5/5 | 4/5 |
| T4 Q3 | 5/5 | 5/5 | 5/5 |
| T4 Q4 | 5/5 | 5/5 | 5/5 |
| T4 Q5 | 5/5 | 5/5 | 3/5 |
| T4 Q6 | 5/5 | 1/5 | 1/5 |
| T4 Q7 | 5/5 | 5/5 | 5/5 |
| T4 Q8 | 5/5 | 5/5 | 5/5 |

### 6.2 留出任务 `t5_bram`（2026-10-31，一次性，`simulated`）

设计与夹带审计见 `holdout/t5_bram_design.md`。这道题**不属于** T1–T3 主指标，只回答"效果能否推广到
一道新题"。规模：3 组 × 5 次 = 15 次 `opencode run`，`15/15 exit=0`，无 hang。

| 组 | 场景通过率 | 全通过 | canary |
|---|---|---|---|
| with | 1.000 | 5/5 | 5/5 |
| without | 0.800 | 4/5 | 0/5 |
| placebo | 0.800 | 4/5 | 5/5 |

- `with` vs `without`：+0.200，**p=1.0000**，δ=+0.20（不显著）；`with` vs `placebo`：p=1.0000，δ=+0.20；
  `placebo` vs `without`：p=1.0000，δ=0.00。
- 差异全部来自 2 个试验：`without/rep03` 与 `placebo/rep04` 各自 7 个场景**全失败**，原因是解法从
  `ip_dict` 里读 `desc['vlnv']` 找 IP。PYNQ 的 `ip_dict` 条目用的是 `type` 键（`phys_addr`/`addr_range`/
  `type`/`parameters`/`registers`/`state`），没有 `vlnv` 键——这是模型自己编的键名，在真板上同样会失败，
  不是仪器缺口。其余 8 个非 `with` 试验全部 7/7 通过。
- 判读：**在本题上没有测到显著差异**（p=1.0），且 10 个非 `with` 试验里有 8 个满分，接近天花板。
  按第 4 节规则，这是一次"未复现主实验方向"的留出结果，必须照实写，不能因为 T1/T3 显著就淡化它。
  可能原因：题目偏易（4/5 的解法都做对了读-改-写），以及单次失败集中在一个"键名写错"的低级错误上，
  这种错误与 Skill 的流程规则无关。
- 因此对外只能说：**主实验的差异未能在这一道留出任务上复现**；泛化性证据不足，需要更多留出题
  （且由没读过 Skill 的人写）才能下结论。

## 7. 已知局限

- 假 PYNQ 是行为模型：DMA 中间没有流 FIFO（先发并等待发送完成再启动接收会卡住）、HLS 核在 2 ms 后完成、地址越界时核挂起。这些假设写在 `harness/fake_pynq/pynq/__init__.py` 中。
- 假 PYNQ 的 API 覆盖面靠 `harness/tests/test_fake_pynq_api.py` 钉住（`Bitstream`、`Overlay` 继承、`hierarchy_dict`、`device`、`hash`）。首轮曾因缺 `pynq.Bitstream` 把一份正确解法判 0 分；新出现的 `ImportError`/`AttributeError` 应先当成仪器缺口排查，再当成模型错误。
- 模型温度在 OpenCode V2 中无法通过 agent 配置下发，因此依靠重复次数控制随机性；模型在真实任务里默认不主动加载 Skill，提示词里需要有中性提示，否则 `with` 组会退化成 `without`（见第 2 节修订）。
- T4 的概念规则较粗，可能误判措辞不同的正确答案；对外报告前建议两人按同一规则盲评复核。
- 只测一个模型的结果不能推广到其他模型。
