# 分析现状与完成目标所需工作

- 工具：opencode；模型：gpt-6-astra；会话：`ses_e77ef598effeTkhf1Bz13FlBUN`
- 开始：2026-10-29 22:29；用户提示 7 条；工具调用 508 次

## 用户提示（2026-10-29 22:29）

这里更新了数据，然后这是另一个ai分析的，但是我感觉他的回复有可能是错的， 请你给我分析一下现状距离我们想得到的还差什么，以及我们需要做什么来完成

### 模型回答（2026-10-29 22:29）

我会先对照仓库最新记录和验证证据，区分“已完成但没归档”“确实没完成”和“另一个 AI 推断过度”的部分，再给出按提交目标排序的补齐方案。

<details><summary>工具调用 1 次</summary>

- `shell` git status --short

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-Content AGENTS.md, README.md, docs/project_overview.md, docs/technical_rules.md, tasks/task_board.md, project_log/actual_progress.md, pr

</details>

<details><summary>工具调用 8 次</summary>

- `read` README.md
- `read` docs/project_overview.md
- `read` docs/technical_rules.md
- `read` tasks/task_board.md
- `read` project_log/actual_progress.md
- `glob` **/*20261029*
- `read` submission
- `read` docs/tech_report

</details>

<details><summary>工具调用 8 次</summary>

- `read` docs/current_status_20261029.md
- `read` board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md
- `read` docs/tech_report/data_gap_after_pull_20261029.md
- `read` docs/tech_report/handoff_20261029.md
- `read` docs/interfaces.md
- `read` project_log/readme.md
- `glob` data/pynq/**/*
- `grep` docs

</details>

<details><summary>工具调用 8 次</summary>

- `read` data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json
- `read` data/pynq/error_gate_20261029_134023/pynq_board_error_gate.json
- `read` docs/timing_acb_validation.md
- `grep` src/firmware/pynq_svc
- `read` board/vivado_zynq7000_xc7z020_pynq/validation_20261028.md
- `read` project_log/development_log.md
- `read` docs/tech_report/README.md
- `read` skill

</details>

### 模型回答（2026-10-29 22:30）

已经发现几处需要纠正：RO 的 `no_clock=10944` 属于 PUF 变体，不能套到当前 PYNQ 发布版；`ma_data` 的失败原因已有记录，并非尚未归因；补齐完整 KAT 也不必然需要 DMA。另外，Notebook 功能验证已通过，但 warm benchmark 的已执行 Notebook 本体确实还没归档。

<details><summary>工具调用 1 次</summary>

- `shell` @' import json, pathlib, statistics, hashlib p=pathlib.Path('.') b=json.loads((p/'data/pynq/notebook_20261029_130920/pynq_warm_benchmark.jso

</details>

<details><summary>工具调用 6 次</summary>

- `read` src/firmware/pynq_svc/ascon_modes.c
- `read` src/firmware/pynq_svc/ascon_modes.c
- `grep` src/firmware/pynq_svc/main.c
- `read` board/vivado_zynq7000_xc7z020_pynq/release/manifest.json
- `read` skill/readme.md
- `read` project_log/lessons_learned.md

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' import json, pathlib, statistics, hashlib, sys p=pathlib.Path('.') print('PYTHON',sys.version.split()[0]) b=json.loads((p/'data/pynq/note

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` git diff --check

</details>

### 模型回答（2026-10-29 22:31）

**你的怀疑有道理：另一个 AI 对“缺数据”的判断大部分成立，但混淆了不同工程版本，也把部分可选扩展当成了完成项目的必要条件。**

对照最新仓库及原始 JSON 后，我的结论是：

> **核心“RISC-V 上运行标准 Ascon，比较 SW/MMIO/ISE，并通过 PYNQ 展示”的链路已经跑通。现在主要缺验证收口、通用 Skill 和可复现交付，不是还需要重做一套硬件。**

## 一、另一个 AI 哪些地方对，哪些需要改

| 项目 | 核验后的判断 |
|---|---|
| PUF 跨上电、温压、唯一性不足 | **基本正确，但属于 P2，不应阻断当前 P0/P1。** ≥50 次是项目测试要求，不能当作已核实的比赛硬性规定；单板也不能证明跨芯片唯一性。 |
| RO `no_clock=10944` 没解决 | **对 PUF 变体成立，不能套到 PYNQ 发布版。** 当前 release 明确不含 PUF，其实现报告内部未约束端点为 0。 |
| `ma_data` 需要先查原因 | **不准确：已有归因。** 文档明确该测试要求完成非对齐访存，而当前 CPU 触发异常。仍需核验异常行为是否符合声明的执行环境，不能仅写“豁免”就算通过。 |
| 完整 KAT 必须上 DMA/流接口 | **推断过度。** SW/ISE 和固定 16B 的 HW 必须分开处理，见下文。 |
| Notebook 未执行 | **已过时。** 顺序执行、smoke、30 次 warm benchmark 已有实板结果。 |
| demo 已执行 `.ipynb` 没归档 | **正确。** warm benchmark 目录只有 JSON/log；error-gate 的已执行 Notebook 本体已归档。 |
| 小时级运行、资源泄漏没测 | **正确。** 30 次采样、50 次往返不能替代小时级稳定性测试。 |
| 没有 standalone 文件，所以独立核 PPA 没做 | **结论仍是未测，但论证不充分。** 文件名搜索不能证明测量是否存在，应检查综合入口和报告。 |
| 没有实物照片 | **可确认当前提交证据不足。** 但“Git 未跟踪图片”不等于现实中没有照片。 |

相关依据：[`current_status_20261029.md`](docs/current_status_20261029.md)、[`validation_20261029.md`](board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md)、[`timing_acb_validation.md`](docs/timing_acb_validation.md)。

## 二、现在已经真正得到什么

我直接复算了原始 benchmark、错误门禁及发布文件哈希：

- SW/HW/ISE **各 289 组容量内 KAT**、坏 Tag 拒绝已有板级证据。
- Notebook 顺序执行与性能采样已有结果。
- 错误恢复 **9/9 PASS**，包含超长度、半帧、deadline、重复 ID、错误 epoch、FIFO overflow。
- bit/hwh/bin/coe/elf **五项哈希与板端记录一致**。
- 当前 PYNQ 固定 16B、AD=0，每档 30 次采样：

| 模式 | 加密 cycles | 相对 SW 周期加速比 | PS 调用墙钟中位 |
|---|---:|---:|---:|
| SW | 23,342 | 1× | 5.216 ms |
| MMIO HW | 1,439 | 16.22× | 4.479 ms |
| ISE | 3,995 | 5.84× | 5.154 ms |

**这里是报告最需要说清楚的地方：CPU 周期显著减少，不等于 Python 调用也加速相同倍数。** 当前 Python/MMIO/UART 通道开销占比较高，所以 ISE 的周期收益没有等比例体现为 PS 端响应时间收益。

历史 PL-only 的 `20806/688/2570` 应单列，不能与这次 PYNQ 数据拼表计算。

## 三、完整 1,089 KAT 到底还差什么

目前不是“算法只支持 16B”，而是存在不同层级的限制：

- **当前 mailbox 对所有模式统一限制 PT/AD 各 16B。**
- SW 包装已有到 32B 的边界；ISE 实现包含多块处理循环，但更长输入尚未完成当前板级验证。
- MMIO HW 是固定 16B 接口，不能因此认为它已支持多块消息。

因此：

### 如果目标是当前短消息演示交付

可以明确写：

> host 完整 1,089 组通过；板级当前接口容量内 289 组通过；超容量请求显式拒绝。

这不等于完成原定全部验收，**需要项目方确认提交范围，但不必为了凑齐数字临时增加 DMA。**

### 如果坚持完整板级 KAT

- **SW/ISE**：可以考虑独立测试固件内置全部向量，或扩展现有传输协议；不必然需要 DMA。
- **MMIO HW**：需要真正支持持续保存状态的多块 AEAD 处理，再验证 padding、AD、最后一块和认证失败输出。
- **不能把长消息分成多个独立 AEAD 调用再拼接**，那不是同一条消息的标准结果。

后者已属于新增功能。现在过了内部冻结点，**不建议默认启动**。

## 四、距离“可以放心提交”，优先补这些

### 1. 固定最终范围与版本——先做

明确最终提交：

- RV32、当前 PYNQ release；
- PT/AD 各 ≤16B；
- SW/MMIO/ISE；
- PUF 是独立探索，不声称已完成可靠密钥系统。

再把发布文件、实际源集、构建命令、工具版本、报告和板级结果对应起来。manifest 中的 `source_dirty=true` **不直接证明构建有问题，但说明不能只靠 commit 号复现，必须核对源文件哈希及构建输入。**

### 2. 补低风险板级证据

不改 RTL，优先完成：

- 板卡正反面、核心芯片丝印、跳线和 SD 启动配置；
- PYNQ 镜像来源、版本及写卡步骤；
- warm benchmark 已执行 Notebook 本体；
- 建议至少一次小时级连续运行，记录成功/失败、超时、恢复、RSS、FD 数；
- 冷启动后重新跑 smoke，保存每次启动结果；
- 独立频率证据；暂时没有就继续标 `not_measured`。

注意：同源时钟下读 PL 周期计数器，不能独立证明时钟绝对频率。

### 3. 完成通用 Skill——这是目前明显缺失的交付

`S01–S05` 还没有实现，现有 `rtl-design-discipline` 不能替代它们。

最小闭环是：

- 参数化 overlay 加载与身份检查；
- 参数化寄存器访问；
- 可注入 golden callback；
- 通用性能/结果收集；
- 使用说明及失败边界；
- **至少一个非 Ascon 示例验证可复用性**。

优先复用现有工具，不要另起一个复杂框架。

### 4. 关闭验证范围，而不是把所有项目改成绿色

仍未完成的包括：

- 板上 ISA 抽样；
- ISE 完整 spec 与异常/中断覆盖矩阵；
- RV64；
- 原 CICC baseline 全复现、FreeRTOS 依赖。

**这些不能假装完成。** 必须区分：最终范围内必须补测的项目，以及经确认移出本次提交范围的项目。尤其最终版本的回归不能仅凭历史版本通过就标记 V04 完成。

### 5. 完成真正的交付闭环

- 修正文档中的旧状态、墙钟估算和不同 run 数据混用；
- 保存报告底层证据，不只引用开发机私有路径；
- 完成 PPT、真实板级视频、来源/许可、LLM 协作记录；
- 在干净目录验证构建与运行，不依赖旧 `.runs`、缓存或本机绝对路径；
- 最终包离线检查文件、链接、哈希和操作步骤。

**报告已经有较完整草稿和 LaTeX 产物，所以不是“材料从零开始”；但目前未跟踪、未定稿、未验包，也不能算正式交付。**

## 我的建议顺序

**冻结范围和发布身份 → 补照片/Notebook/稳定性证据 → 完成通用 Skill → 最终回归与材料 → 干净复现和验包。**

暂不把 PUF、DMA、大消息吞吐、独立核 PPA 塞入提交前主线；除非你们确认这些是必须兑现的核心承诺。**当前最危险的不是少一个高级功能，而是已有成果的版本、测量口径和复现证据对不上。**

本轮未改设计或报告正文；仅更新三份项目日志。只读复算及 `git diff --check` 均退出 0，未重跑硬件测试，未 commit/push。

## 用户提示（2026-10-29 22:48）

请你检查当前的技术报告，并修改至和现在状态一致的情况，你先将PUF、DMA、大消息吞吐、独立核 PPA 移除掉我们的项目，先保证我们的技术报告可以和当前的版本和证据对上；然后我们后续有时间就截止去跑这个高端功能，一步一步来

### 模型回答（2026-10-29 22:48）

我会先核对技术报告的正文源、生成脚本和现有证据，再把主线统一为当前已验证的 RV32/PYNQ 短消息 SW/MMIO/ISE 版本。PUF、DMA、大消息吞吐和独立核 PPA 会从本次报告范围及承诺中移除；已有代码和历史证据保留，不做删除。

<details><summary>工具调用 1 次</summary>

- `shell` git status --short

</details>

<details><summary>工具调用 8 次</summary>

- `glob` docs
- `read` docs/tech_report/src/01_front.md
- `read` docs/tech_report/src/06_perf.md
- `read` docs/tech_report/src/075_pynq.md
- `read` docs/tech_report/src/08_summary.md
- `read` docs/tech_report/src/09_review.md
- `read` docs/tech_report/build_site.py
- `read` docs/tech_report/build_template_src.py

</details>

<details><summary>工具调用 8 次</summary>

- `read` docs/tech_report/src/02_cpu.md
- `read` docs/tech_report/src/03_ascon.md
- `read` docs/tech_report/src/04_impl.md
- `read` docs/tech_report/src/05_verify.md
- `read` docs/tech_report/build_latex.py
- `read` docs/tech_report/src_template/new
- `read` docs/tech_report/evidence/README.md
- `read` docs/agent_workflow.md

</details>

<details><summary>工具调用 8 次</summary>

- `read` docs/tech_report/evidence/build_evidence.py
- `read` docs/tech_report/evidence/assemble.sh
- `grep` docs/tech_report/src_template/new
- `grep` docs/tech_report/build_latex.py
- `read` docs/tech_report/make_overleaf_zip.py
- `read` docs/tech_report/prerender_figs.py
- `glob` build/reports/pynq_final_20261028/**/*summary*
- `read` docs/tech_report/latex/build.ps1

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path for p in sorted(Path('docs/tech_report/src_template/new').glob('*.md')):  print('\nFILE '+str(p)+'\n'+p.read_tex

</details>

### 模型回答（2026-10-29 22:49）

报告里不只是状态过时：模板稿把 MMIO/ISE 加速比写反、Vivado 写成了 2023.2，还写了当前协议并不存在的 CRC、超时重传，以及错误的产物路径。我会一并纠正，并明确区分“历史 PL-only 实测”和“当前 PYNQ release 实测”，避免继续混用。

<details><summary>工具调用 8 次</summary>

- `read` docs/tech_report/build_latex.py
- `read` docs/tech_report/build_latex.py
- `grep` docs/tech_report/figs
- `read` build/reports/pynq_final_20261028/smoke/summary.json
- `read` build/reports/pynq_final_20261028/regression_final/summary.json
- `read` src/firmware/pynq_svc/build.sh
- `read` docs/tech_report/figs
- `read` docs/development_workflow.md

</details>

<details><summary>工具调用 8 次</summary>

- `read` docs/tech_report/figs/board_photo.jpg
- `read` docs/tech_report/figs/fig_2_1.tex
- `read` docs/tech_report/figs/fig_2_7.tex
- `read` docs/tech_report/figs/fig_2_9.tex
- `read` docs/tech_report/figs/fig_2_11.tex
- `read` docs/tech_report/figs/fig_3_2.tex
- `read` docs/tech_report/figs/fig_2_10.tex
- `read` docs/tech_report/figs/fig_3_4.tex

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path import shutil, datetime, json, ast root=Path('docs/tech_report') out=Path(r'C:/Users/HXZ/AppData/Local/Temp/open

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `glob` data/ascon/results/*failure*

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 7 次</summary>

- `read` build/reports/pynq_final_20261028
- `read` data/ascon/results/failure_contract.json
- `read` data/pynq/board_20261028/identity.txt
- `read` docs/tech_report/figs/fig_2_2.tex
- `read` docs/tech_report/figs/fig_1_1.tex
- `read` docs/tech_report/figs/fig_3_5.tex
- `read` docs/tech_report/build_latex.py

</details>

<details><summary>工具调用 1 次</summary>

- `grep` build/reports/pynq_final_20261028

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path p=Path('docs/tech_report/build_latex.py') for i,l in enumerate(p.read_text(encoding='utf-8').splitlines()[529:53

</details>

### 模型回答（2026-10-29 23:07）

正文已改为当前发布范围，性能主表也已切换到 10-29 的 PYNQ 数据。另外确认了两个新事实：当前 overlay 资源是 LUT 14,269 / FF 19,691，不能沿用历史 PL-only 数字；报告目录已有一张实物正面照片，所以“没有任何照片”也已纠正。

我还注意到 LaTeX 脚本正在被其他会话更新，会保留这些改动，只调整本次必需的生成入口和图件选择。

<details><summary>工具调用 1 次</summary>

- `read` docs/tech_report/build_latex.py

</details>

<details><summary>工具调用 1 次</summary>

- `glob` data/ascon/results/board/*.XDat

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

## 用户提示（2026-10-29 23:11）

本作品面向嵌入式数据安全场景，基于 AMD Zynq-7000（XC7Z020）平台，设计实现集成轻量级密码加速的 RISC-V 处理器 SoC。处理器采用五级流水线架构，支持 RV32IM、Zicsr 指令集，集成动态分支预测、指令与数据 Cache、AXI 总线及 UART、GPIO、CLINT 等外设，工作在 100 MHz。在此基础上，引入符合 NIST SP 800-232 的 Ascon-AEAD128 认证加密算法，设计纯软件（SW）、存储器映射硬件加速（MMIO）与自定义指令扩展（ISE）三种实现方案。已完成三者的 RTL 仿真、官方向量验证、自动化回归与镜像生成，并在领航者 Zynq-7020 开发板上完成实板运行。板级实测 16 字节加密：软件 20806 周期，ISE 2570 周期（8.10 倍），MMIO 端到端 688 周期（30.2 倍），时序余量为正、DRC 无违例。此外完成基于 256 路环形振荡器与芯片 DNA 的 PUF 密钥子系统，板上注册质量 127/128。后续将完善 PS/PL 通信与 Jupyter 交互界面、PUF 稳定性统计及性能对比；这个是我们对于我们工程的简介，我们是自由项目，所以我认为这个PUF和DMA并不是必要完成，我们已经实现了功能，后续的通用性验证和稳定性测试，我认为没有那么重要；请你完成对于我们技术报告的修改后，重新制定当前项目进度，我们实际是在11月1日进行提交项目，那时候才是我们的冻结期，你可以先不去管项目中规定的冻结日期。明天我的队友将进行skill的测试，你可以同时制作一个指导表，给他安排先做什么，后做什么；我会让你跑一晚上，你可以一致跑下去，直到任务完成。如果你认为当前项目中还有没有实现的代码，你也可以直接进行编写代码；对于技术报告你可以直接更改，其他会话更新的内容你也需要检查，因为其他会话我感觉比较降智

### 模型回答（2026-10-29 23:11）

明白，按你这次确认的范围继续：

- **11 月 1 日提交并冻结**，不再用仓库旧冻结日期限制本轮工作。
- PUF、DMA 等扩展移出本次交付；稳定性和额外通用性试验不作为提交阻塞，但仍如实标明未测，不能写成已验证。
- 你贴的简介使用历史 PL-only 周期，且 PS/PL、Jupyter 的状态已过时；我会与当前 PYNQ 成果分开表述，并移除 PUF 段落。
- 完成报告、图件及生成产物后，重订项目进度，并给队友一份明天 Skill 测试的执行顺序、验收项和证据归档表。

新增代码会限于补齐本次交付所需的构建、检查与测试工具，不顺手扩展硬件功能；其他会话的内容会逐项核验，不直接采信或覆盖。

<details><summary>工具调用 1 次</summary>

- `shell` git status --short

</details>

## 用户提示（2026-10-29 23:13）

本作品面向嵌入式数据安全场景，基于 AMD Zynq-7000（XC7Z020）平台，设计实现集成轻量级密码加速的 RISC-V 处理器 SoC。处理器采用五级流水线架构，支持 RV32IM、Zicsr 指令集，集成动态分支预测、指令与数据 Cache、AXI 总线及 UART、GPIO、CLINT 等外设，工作在 100 MHz。在此基础上，引入符合 NIST SP 800-232 的 Ascon-AEAD128 认证加密算法，设计纯软件（SW）、存储器映射硬件加速（MMIO）与自定义指令扩展（ISE）三种实现方案。已完成三者的 RTL 仿真、官方向量验证、自动化回归与镜像生成，并在领航者 Zynq-7020 开发板上完成实板运行。板级实测 16 字节加密：软件 20806 周期，ISE 2570 周期（8.10 倍），MMIO 端到端 688 周期（30.2 倍），时序余量为正、DRC 无违例。此外完成基于 256 路环形振荡器与芯片 DNA 的 PUF 密钥子系统，板上注册质量 127/128。后续将完善 PS/PL 通信与 Jupyter 交互界面、PUF 稳定性统计及性能对比；这个是我们对于我们工程的简介，我们是自由项目，所以我认为这个PUF和DMA并不是必要完成，我们已经实现了功能，后续的通用性验证和稳定性测试，我认为没有那么重要；请你完成对于我们技术报告的修改后，重新制定当前项目进度，我们实际是在11月1日进行提交项目，那时候才是我们的冻结期，你可以先不去管项目中规定的冻结日期。明天我的队友将进行skill的测试，你可以同时制作一个指导表，给他安排先做什么，后做什么；我会让你跑一晚上，你可以一致跑下去，直到任务完成。如果你认为当前项目中还有没有实现的代码，你也可以直接进行编写代码；对于技术报告你可以直接更改，其他会话更新的内容你也需要检查，因为其他会话我感觉比较降智；我们还是需要PUF等高端功能的，要不然老师认可度不高；你可以适度根据当前高端功能的实现来编写技术报告

### 模型回答（2026-10-29 23:13）

按你最后补充，PUF 会保留为**已实现的扩展原型**，单独列出对应版本、板上观测和验证边界，不与当前 PYNQ 演示版混为一体。注册质量以原始日志为准；不会把单次重建成功写成跨上电稳定或完整安全启动。DMA 等尚未实现的功能仍不列为成果。

我会据此完成报告与生成包，按 **11 月 1 日提交/冻结**重订进度，并把明天的 Skill 测试整理成可直接执行的指导表。

<details><summary>工具调用 7 次</summary>

- `read` docs/key_subsystem.md
- `read` data/ascon/results/board/uart_20261027_keys3.txt
- `read` docs/tech_report/build_latex.py
- `read` skill/rtl-design-discipline/SKILL.md
- `read` tasks/milestones.md
- `read` docs/decisions.md
- `read` docs/tech_report/build_local.bat

</details>

<details><summary>工具调用 6 次</summary>

- `read` src/rtl/keys/puf_key.v
- `read` src/rtl/keys/key_mmio.v
- `read` src/firmware/keys_rv32/main.c
- `read` sim/keys
- `read` docs/tech_report/figs/fig_2_8.tex
- `read` docs/tech_report/prerender_figs.py

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 docs/tech_report/evidence/build_evidence.py

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 docs/tech_report/build_template_src.py

</details>

<details><summary>工具调用 1 次</summary>

- `grep` docs/tech_report/build_template_src.py

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 2 次</summary>

- `shell` python -X utf8 docs/tech_report/prerender_figs.py
- `shell` python -X utf8 docs/tech_report/build_template_src.py

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 2 次</summary>

- `shell` python -X utf8 docs/tech_report/build_site.py
- `shell` python -X utf8 docs/tech_report/build_latex.py

</details>

<details><summary>工具调用 1 次</summary>

- `shell` & 'C:\Users\HXZ\AppData\Local\hermes\cache\scratch\tectonic.exe' -X compile main.tex --keep-logs

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 5 次</summary>

- `read` docs/tech_report/build_latex.py
- `read` docs/tech_report/build_latex.py
- `read` docs/tech_report/latex/chapters/ch04.tex
- `read` docs/tech_report/latex/chapters/ch02.tex
- `grep` docs/tech_report/README.md

</details>

<details><summary>工具调用 1 次</summary>

- `read` docs/tech_report/build_latex.py

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 docs/tech_report/build_report.py

</details>

<details><summary>工具调用 5 次</summary>

- `grep` docs/tech_report/src
- `read` src/rtl/dcache.v
- `read` src/rtl/ctrl.v
- `read` ascon/ascon_c/aead/aead.c
- `read` docs/tech_report/figs/fig_2_6.tex

</details>

<details><summary>工具调用 7 次</summary>

- `read` docs/tech_report/figs/fig_2_3.tex
- `read` docs/tech_report/figs/fig_2_4.tex
- `read` docs/tech_report/figs/fig_2_5.tex
- `read` src/rtl/ascon/ascon_permutation.v
- `read` docs/tech_report/src/03_ascon.md
- `grep` src/rtl/regfile.v
- `read` src/rtl/regfile.v

</details>

### 模型回答（2026-10-29 23:28）

PUF 已恢复为独立原型章节，并核实了两点：有效的 v3 日志是 **128/128**，旧简介的 127/128 来自失败片段；当前调试窗口可读出派生所需的响应、掩码和 DNA，因此“key 没有直接读地址”还不能证明密钥对软件保密。报告会保留功能成果，同时把这个边界写清楚。

图件复核还发现了轮函数顺序、旋转常数和寄存器堆同拍读写描述错误，正在按源码纠正，避免正文改对了、图里仍留旧错误。

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `read` docs/tech_report/src/02_cpu.md

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path import pymupdf, re p=Path('docs/tech_report/latex/main.pdf') d=pymupdf.open(p) print('PAGES',len(d)) for term in

</details>

<details><summary>工具调用 3 次</summary>

- `read` C:/Users/HXZ/AppData/Local/Temp/opencode/report_review/page_8.png
- `read` C:/Users/HXZ/AppData/Local/Temp/opencode/report_review/page_21.png
- `read` C:/Users/HXZ/AppData/Local/Temp/opencode/report_review/page_35.png

</details>

<details><summary>工具调用 1 次</summary>

- `glob` sim/ascon/reference/*

</details>

<details><summary>工具调用 1 次</summary>

- `read` sim/ascon/reference

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 docs/tech_report/build_report.py

</details>

<details><summary>工具调用 1 次</summary>

- `read` docs/tech_report/validation/build_20261029_232734/tool_version.log

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 4 次</summary>

- `shell` python -X utf8 docs/tech_report/evidence/assemble.py
- `shell` git diff --check
- `shell` git diff --stat
- `read` docs/tech_report/validation/build_20261029_233156/audit.log

</details>

<details><summary>工具调用 1 次</summary>

- `read` project_log/actual_progress.md

</details>

<details><summary>工具调用 4 次</summary>

- `read` docs/tech_report/figs/fig_2_6.pdf
- `read` docs/tech_report/figs/fig_2_8.pdf
- `read` submission/current_evidence.json
- `shell` git status --short

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 docs/tech_report/build_report.py

</details>

<details><summary>工具调用 1 次</summary>

- `read` docs/tech_report/evidence/proposed_text_changes.md

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

### 模型回答（2026-10-29 23:37）

报告已完成当前证据对齐，PDF、HTML、Overleaf 包和图件均已重建并通过一致性检查。进度已改为 **11 月 1 日提交/冻结**；队友明天的 Skill 指导表也已写好。

我正在做最后封包。仍需你们完成的主要是 Skill 实测、团队信息、PPT/视频和人工提交；长时稳定性与额外通用性试验已明确为非阻塞后续项。

<details><summary>工具调用 4 次</summary>

- `shell` python -X utf8 docs/tech_report/evidence/assemble.py
- `read` docs/tech_report/validation/build_20261029_233545/audit.log
- `shell` git diff --check
- `shell` git diff --name-only -- src board ascon

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

### 模型回答（2026-10-29 23:38）

已完成本轮修改，并按你的最新要求保留 **PUF 独立原型成果**。

### 交付文件
- [技术报告 PDF（57 页）](docs/tech_report/latex/main.pdf)
- [Overleaf 上传包](docs/tech_report/latex_project.zip)
- [更新后的项目简介](docs/project_intro_20261101.md)
- [当前进度与 11-01 提交计划](tasks/release_plan_20261101.md)
- **[队友明天的 Skill 测试指导表](docs/skill_test_guide_20261030.md)**
- [报告证据包](submission/evidence_20261101_20261029_233749.zip)

### 主要修改
- 当前 PYNQ 与历史 PL-only 性能分列，纠正加速比、工具版本、资源数据及协议描述。
- PS/PL、Notebook、错误恢复更新为已有实板验证。
- PUF 保留独立章节：有效 v3 注册质量为 **128/128**，明确同次重建自检的证明范围。
- 移除未实现的 DMA 等成果承诺。
- 项目安排统一为 **11 月 1 日提交并冻结**；额外稳定性与通用性实验不阻塞提交。
- 修复图件错误，并补齐报告自动构建、证据核验和封包工具。

**验证结果：**完整构建通过；51 件证据哈希、16 张正文图、PDF、Overleaf 包及63文件证据包校验通过。普通排版提示仍保留。

下一步按指导表完成 Skill 实测，再补团队信息、PPT/视频和人工提交。本轮任务 D01/D02/D03，owner TBD；未改生产 RTL、固件或发布镜像，未 commit/push。

## 用户提示（2026-10-29 23:44）

现在给出DMA和PUF的实现和验证方案

## 用户提示（2026-10-29 23:45）

现在给出DMA和PUF的实现和验证方案；当前我们已经没法修改简介，我给你说只是让你快速接手项目；还有高端方案的实现计划表

### 模型回答（2026-10-29 23:45）

明白，已提交的简介保持不动。我会结合现有 PYNQ 通道、16B 硬件接口和 PUF 原型，分别给出 DMA/PUF 的实现路径、验证标准及实施计划，并区分“能演示”和“达到可靠性、安全性目标”需要完成的工作。

<details><summary>工具调用 1 次</summary>

- `shell` git status --short

</details>

<details><summary>工具调用 6 次</summary>

- `read` src/pynq/mailbox_protocol.md
- `read` src/rtl/keys/ro_puf_core.v
- `read` board/vivado_zynq7000_xc7z020_pynq/build.tcl
- `read` docs/io_timing_signoff.md
- `read` src/rtl/ascon/ascon_aead_core.v
- `read` src/rtl/keys/ro_unit.v

</details>

<details><summary>工具调用 1 次</summary>

- `skill` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 3 次</summary>

- `webfetch` 
- `webfetch` 
- `webfetch` 

</details>

### 模型回答（2026-10-29 23:46）

方案里最关键的区分是：**DMA 解决数据搬运，不会让现有 16B AEAD 核自动支持长消息。** 我建议先让 DMA 接入 RV32 的不可缓存收发窗口，保留“自研 CPU + SW/MMIO/ISE”主线；直接连接独立密码核的高速路径放到后续阶段。

PUF 则先补功能错误处理：当前采样看门狗超时会发完成信号，却没有独立失败标志，可能把旧响应当成新采样结果使用。这个问题应先于跨上电统计处理。当前未提供 AMD 文档检索服务；已核对 PYNQ 2.7 的 DMA/缓存文档，具体 Vivado IP 参数回读留到实施阶段，不把配置建议标成已验证。

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 3 次</summary>

- `read` src/rtl/keys/ro_puf_core.v
- `shell` git diff --check
- `shell` python -c "from pathlib import Path; import math; paths=['docs/dma_puf_implementation_plan.md','tasks/advanced_features_plan_20261101.md']; 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

### 模型回答（2026-10-29 23:55）

明白：**已提交简介不再修改。DMA、PUF 的后续实现用独立版本和新增证据说明。**

已整理：
- [DMA / PUF 实现与验证方案](docs/dma_puf_implementation_plan.md)
- [高端功能实施计划表](tasks/advanced_features_plan_20261101.md)

## 一、DMA：先加速传输，再扩展密码核

**DMA 不会自动解除现有 AEAD 硬件的 16B 限制。** 建议分两步。

### 第一步：DMA 接入 RV32，保留三模式主线

```text
PS DDR 缓冲区
    ↕ HP0
AXI DMA
    ↕ AXI-Stream
独立请求/响应缓冲
    ↕ RV32 不可缓存 MMIO
RV32 服务固件 → SW / MMIO / ISE
```

采用 **simple mode、双向通道、32-bit 流接口**起步。保留 UART 作为诊断通道。

需要实现：
- 流接口收发、`TKEEP/TLAST`、背压和长度检查；
- RV32 不可缓存收发窗口；
- 固件新增传输后端；
- Python 连续缓冲分配、缓存同步、超时恢复。

这里 RV32 仍搬运参数，不能宣传“CPU 完全不参与搬运”。

**验证顺序：**
1. DMA 环回：各种长度逐字节一致，缓冲边界无破坏。
2. 注入背压、错误/缺失 `TLAST`、超时、复位。
3. 接入真实 RV32，重跑三模式容量内 **289 KAT、坏 Tag、恢复测试**。
4. 同次采集 CPU 周期与 PS 墙钟，验证收益，不预设加速倍数。

### 第二步：支持完整 KAT、多块消息

- SW/ISE：扩协议能力与缓冲，先做到32B，验证完整1089组。
- HW：新增真正保留320-bit状态的多块AEAD控制器。
- 解密候选明文先留在PL私有缓冲，**认证成功后才送往PS DDR**。
- DMA直连密码核可另设 `HW_DIRECT`，不能称为CPU ISE加速。

不能把多个独立16B加密结果拼起来当作一条标准长消息。

## 二、PUF：先补正确性，再做可靠重建

### 优先完成：让已有原型可信地工作

当前最值得先修的不是增加RO数量，而是：

1. **采样失败明确上报**  
   当前watchdog会发完成信号，但没有独立失败标志，可能发布旧响应。需增加错误状态和事务新鲜度检查。

2. **核心时钟域增加超时保护**  
   `ro_clk`停摆时，同域watchdog也会停止。失败后清除旧key有效状态，拒绝继续加密。

3. **检查真实RO及跨域采样**  
   检查不振荡、计数相等、溢出、常量折叠、同步级和快照时序；不能靠全局`false_path`让报告变绿。

4. **补真正的密钥使用证明**
   ```text
   enroll → 内部key执行AEAD
          → reconstruct
          → 同一测试输入执行AEAD
          → 比较CT/tag
   ```
   现有板级PASS主要检查状态，并未完成这项证明。

5. **正常模式失败关闭**  
   重建失败不再把DNA-only回退当作秘密密钥正常使用。

### 后续：跨上电与保密重建

先区分两个目标：

- **诊断持久化**：保存REF/MASK，断电后不重新注册，只重建，验证流程。
- **保密重建**：关闭RAW/REF回读，设计纠错辅助数据、提取与派生机制，并分析信息泄漏。

当前完整响应及派生输入可读，所以只隐藏key寄存器并不足以保密。输出128-bit key，也不等于拥有128-bit秘密熵。

**验证包括：**
- 停RO、停采样时钟、坏helper、watchdog、复位等故障注入；
- 内部key的AEAD使用与失败拒绝；
- 固定一次注册后的真实断电重建；
- 有条件再做温压、多板测试。

50次零失败只能算初步实验，不能证明99.9%可靠。

## 三、高端功能优先计划

以下工时为估计，EDA运行和板卡等待另计，owner均为TBD。

| 顺序 | 工作 | 验收结果 | 估计 |
|---|---|---|---|
| 1 | 固定独立实验工程及回退镜像 | 原PYNQ始终可恢复 | 2–3小时 |
| 2 | PUF错误传播、超时、旧key清理 | 故障明确失败，不误用旧响应 | 4–8小时 |
| 3 | DMA最小环回 | 长度、尾字节、缓存、恢复通过 | 4–8小时＋构建 |
| 4 | PUF内部key的AEAD演示 | 注册/重建后结果一致，失败拒绝 | 4–8小时＋构建 |
| 5 | DMA接RV32三模式 | 289 KAT及错误恢复通过 | 1–2天＋板测 |
| 6 | SW/ISE完整1089组 | 按模式明确容量 | 4–8小时＋回归 |
| 7 | PUF持久化重建 | 固定helper的断电记录 | 1–2天＋板测 |
| 8 | 多块HW、保密纠错重建 | 独立完整验收 | 各数天以上 |
| 9 | 镜像认证原型 | 正确镜像允许、篡改拒绝 | 最后开展 |

**11月1日前建议争取第2～4项；第5项视实际进展决定。** 若只有一人一块板，优先完成PUF错误处理和真实使用证明，再做DMA环回。

本轮仅完成方案与计划，未修改硬件、简介或报告。具体DMA IP配置尚未应用和回读，不能视为已经实现。

## 用户提示（2026-10-29 23:56）

在你制定好计划后，请你把除了上板能做的内容都完成，并将高速路径也进行计划后实现

### 模型回答（2026-10-29 23:56）

我会按“先验证协议与错误处理，再接入 CPU，最后实现 DMA 直连多块核”的顺序推进。高速路径会单独标为 `HW_DIRECT`，与现有 ISE 路径区分。

本轮会完成可在本机执行的代码、仿真和构建检查，并为上板测试准备脚本与清单。正式 PYNQ release 保留作为回退；仿真、综合/实现和未执行的板测结果分别记录。

<details><summary>工具调用 1 次</summary>

- `shell` git status --short

</details>

<details><summary>工具调用 1 次</summary>

- `skill` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 6 次</summary>

- `shell` Get-Command vivado,iverilog,vvp,python,wsl -ErrorAction SilentlyContinue | Select-Object Name,Source
- `read` C:/Users/HXZ/.agents/skills/vivado-simulate-rtl/references/xsim.md
- `read` src/rtl/ascon/readme.md
- `read` src/pynq/readme.md
- `read` docs/interfaces.md
- `read` tasks/advanced_features_plan_20261101.md

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` PUF fail-closed implementation

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` CPU DMA host integration

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 4 次</summary>

- `read` sim/ascon/golden.py
- `read` sim/ascon/support.py
- `read` src/rtl/ascon/ascon_round.v
- `glob` data/ascon/**/LWC_AEAD_KAT_128_128.txt

</details>

<details><summary>工具调用 1 次</summary>

- `grep` sim/ascon/support.py

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_regression.py --smoke

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_regression.py --smoke

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_regression.py

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `read` build/local/advanced_dma/dma_properties.txt

</details>

<details><summary>工具调用 1 次</summary>

- `read` C:/Users/HXZ/.agents/skills/vivado-ip-configurator/lib/ipcfg.tcl

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_regression.py

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

### 模型回答（2026-10-30 00:12）

高速直连路径的首轮功能回归已通过：新的多块 AEAD 核和流协议在 **Icarus、Vivado XSim 两个模拟器**上均完成了 3,335 个用例，包含全部 1,089 组官方 KAT 的加密、解密、坏 Tag，以及最长 1KiB 的补充输入、背压和协议错误。

这还不是 DMA 整机或板级通过；接下来验证 AXI-Lite 控制、真实 DMA/PS 集成和实现时序。PUF 与 CPU-DMA 后端正在独立推进。

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `read` build/local/advanced_dma/ps7_hp_properties.txt

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path import shutil,json,hashlib root=Path('.').resolve(); out=root/'data/advanced/dma_direct/xsim_20261030_0010';out.

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` PUF adapter and firmware

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_control.py

</details>

<details><summary>工具调用 6 次</summary>

- `read` sim/pynq_dma_cpu/readme.md
- `read` board/vivado_zynq7000_xc7z020_pynq_dma_cpu/readme.md
- `read` src/pynq/dma_transport.py
- `read` src/rtl/pynq_dma_cpu
- `read` sim/keys_v2/sources.json
- `read` src/rtl/keys_v2/puf_physical_v2.v

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` CPU DMA exhaustive regression

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 6 次</summary>

- `grep` build/local/dma_direct/d.runs/d_engine_0_synth_1
- `read` src/rtl/keys_v2/mmio_abi.md
- `read` sim/keys_v2/cpu_sources.json
- `read` src/rtl/keys_v2/ro_array_v2.v
- `read` src/rtl/keys_v2/puf_mmio_physical_v2.v
- `read` src/rtl/pynq_dma_cpu/dma_control.v

</details>

<details><summary>工具调用 1 次</summary>

- `read` build/local/dma_direct/d.gen/sources_1/bd/d/ip/d_dma_0/sim/d_dma_0.v

</details>

<details><summary>工具调用 1 次</summary>

- `read` build/local/dma_direct/d.gen/sources_1/bd/d/ip/d_dma_0/sim/d_dma_0.vhd

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_control.py

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `glob` build/local/**/puf_v2.hex

</details>

<details><summary>工具调用 1 次</summary>

- `glob` data/advanced/puf/**/puf_v2.hex

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 4 次</summary>

- `read` data/advanced/puf/physical_ooc_20261030_0054/cdc.rpt
- `read` data/advanced/puf/physical_ooc_20261030_0054/timing.rpt
- `read` data/advanced/puf/physical_ooc_20261030_0054/drc.rpt
- `read` src/rtl/keys_v2/ro_puf_core_v2.v

</details>

<details><summary>工具调用 1 次</summary>

- `grep` data/advanced/puf/physical_ooc_20261030_0054/cdc.rpt

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` PUF CDC report repair

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `glob` build/local/dma_direct/**/d_dma_0.xci

</details>

<details><summary>工具调用 1 次</summary>

- `read` build/local/dma_direct/d.gen/sources_1/bd/d/ip/d_dma_0

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 5 次</summary>

- `read` data/advanced/dma_cpu/full_20261030_002958_293520/xsim_all/manifest.json
- `read` data/advanced/dma_cpu/full_20261030_002958_293520/xsim_all/sources.json
- `read` board/vivado_zynq7000_xc7z020_pynq_dma_cpu/pynq_dma_cpu.v
- `read` sim/pynq_dma_cpu/tb_dma_cpu.v
- `read` src/rtl/pynq_dma_cpu/top_dma.v

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` CPU DMA Vivado implementation

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `grep` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 4 次</summary>

- `grep` build/local/dma_direct/d.runs/impl_1/runme.log
- `glob` data/advanced/dma_direct/vendor_xsim_*/result.txt
- `read` src/rtl/keys_v2/cdc_review_20261030.md
- `read` src/rtl/ascon_dma/ascon_aead_multiblock.v

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-Content 'build/local/dma_direct/d.runs/impl_1/runme.log' -Tail 70

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` PUF physical offline closure

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_regression.py

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_regression.py

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` Audit highspeed security tests

</details>

### 模型回答（2026-10-30 01:16）

CPU-DMA 路径已完成真实 RV32 仿真：SW/ISE 各全量 1,089 组、原 HW 容量内 289 组，共 **7,401 次加密/解密/坏 Tag 事务通过**。PUF 新版也已通过故障注入、内部 key 的 AEAD 使用、helper 断电重载模型及真实 RV32 固件测试。

实现阶段发现高速核首版存储没有推成 BRAM，导致资源和布线压力偏大。我已改为同步 RAM 结构，更新后的 **3,467 项功能回归通过**，接着验证新的综合与布局布线；不会把仅仿真通过的版本当作可上板成品。

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `read` sim/ascon_dma/direct_review.md

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` Close core contract probes

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_regression.py

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `grep` build/local/dma_direct_bram/d.runs/d_engine_0_synth_1/d_engine_0_utilization_synth.rpt

</details>

<details><summary>工具调用 1 次</summary>

- `grep` build/local/dma_direct_bram/d.runs/d_engine_0_synth_1/runme.log

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_regression.py

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_lifecycle.py --backend iverilog

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `read` build/local/dma_direct/d.runs/impl_1/.vivado.begin.rst

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-CimInstance Win32_Process -Filter "ProcessId=30092" | Select-Object ProcessId,ParentProcessId,CommandLine

</details>

### 模型回答（2026-10-30 01:42）

高速核的存储重构已通过完整功能与生命周期回归；两个新发现的接口问题——加载新输入时旧结果未撤销、同步 RAM 数据与地址有效标志不同拍——也已修复，并由故障注入测试确认能检出错误。

旧版纯寄存器实现的布线已运行较久，且出现拥塞和负时序余量。我会保留其日志并停止这个已被替代的实验，把资源用于新版存储结构的实现，不影响原正式工程。

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path import shutil,json,datetime root=Path('.'); src=root/'build/local/dma_direct/d.runs/impl_1';dst=root/'data/advan

</details>

<details><summary>工具调用 1 次</summary>

- `shell` taskkill /PID 30092 /T /F

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `grep` build/local/dma_direct_bram/d.runs/d_engine_0_synth_1/d_engine_0_utilization_synth.rpt

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 build/advanced/package_direct.py data/advanced/dma_direct/vivado_20261030_015458

</details>

<details><summary>工具调用 5 次</summary>

- `read` data/advanced/dma_direct/vivado_20261030_015458/result.txt
- `grep` data/advanced/dma_direct/vivado_20261030_015458/utilization.rpt
- `grep` data/advanced/dma_direct/vivado_20261030_015458/timing.rpt
- `read` data/advanced/dma_direct/vendor_xsim_20261030_011029/result.txt
- `grep` data/advanced/dma_direct/vendor_xsim_20261030_011029/simulate.log

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` PUF synchronous timing repair

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `read` data/advanced/dma_direct/lifecycle_20261030_014019_800532/sources.json

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` CPU build integration note

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `grep` build/local/dma_vendor_sim/v.sim/sim_1/behav/xsim/simulate.log

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path import shutil,json,hashlib,datetime r=Path('.').resolve();out=r/'data/advanced/dma_direct/vendor_final_20261030_

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 4 次</summary>

- `shell` git diff --name-only -- src/rtl board ascon
- `shell` git diff --check
- `read` src/rtl/pynq_dma_cpu/readme.md
- `read` data/advanced/dma_direct/vivado_20261030_015458/manifest.json

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/run_regression.py

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 build/advanced/package_direct.py data/advanced/dma_direct/vivado_20261030_024214

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path import hashlib p=Path('board/vivado_zynq7000_xc7z020_pynq/release/sha256sums.txt') for l in p.read_text(encoding

</details>

<details><summary>工具调用 4 次</summary>

- `grep` src/pynq/dma_transport.py
- `grep` board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py
- `read` src/pynq/puf_helper_v2.py
- `read` board/vivado_zynq7000_xc7z020_pynq_dma_cpu/pynq27_audit.md

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py --help

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `grep` src/pynq/dma_transport.py

</details>

<details><summary>工具调用 1 次</summary>

- `read` src/pynq/dma_transport.py

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path import ast, json, sys files=[Path('src/pynq/dma_transport.py'),Path('src/pynq/puf_helper_v2.py'),Path('board/viv

</details>

<details><summary>工具调用 1 次</summary>

- `grep` data/advanced/dma_direct/vivado_20261030_024214/candidate/dma_direct.hwh

</details>

<details><summary>工具调用 1 次</summary>

- `grep` sim/pynq_dma_cpu/tb_dma_cpu.v

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path import hashlib,json,shutil r=Path('.').resolve(); out=r/'data/advanced/dma_direct/vendor_final_20261030_0302';ou

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `read` data/advanced/dma_direct/lifecycle_20261030_014019_800532

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 build/advanced/verify_direct_evidence.py --implementation data/advanced/dma_direct/vivado_20261030_024214 --vendor-test data/

</details>

<details><summary>工具调用 1 次</summary>

- `grep` data/advanced/dma_direct/vivado_20261030_024214/candidate/dma_direct.hwh

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/check_hwh.py data/advanced/dma_direct/vivado_20261030_024214/candidate/dma_direct.hwh --output data/advanced/dm

</details>

<details><summary>工具调用 1 次</summary>

- `read` data/advanced/dma_direct/vivado_20261030_024214/manifest.json

</details>

<details><summary>工具调用 1 次</summary>

- `subagent` PUF SoC board candidate

</details>

### 模型回答（2026-10-30 03:12）

高速直连版本已完成 100 MHz 综合、布局布线和 bitstream 生成：**WNS +0.345 ns、TNS 0、WHS +0.029 ns，DRC 0 Error/0 Critical**，已保存配套 bit/HWH 与源码哈希。

PUF 的同步逻辑关键路径也已修复并通过复验；RO 实际频率和外部接口预算仍需现场确认，不能把这部分称为完整物理签核。接下来收拢 CPU-DMA 和 PUF 独立上板工程的最终证据与操作入口。

<details><summary>工具调用 1 次</summary>

- `read` data/advanced/dma_direct/vivado_20261030_024214/result.txt

</details>

### 模型回答（2026-10-30 03:16）

更正一个数值：最终带故障锁定版本的 **WHS 是 +0.031 ns**；+0.029 ns 属于前一版。最终结果以 `vivado_20261030_024214/result.txt` 为准。

<details><summary>工具调用 1 次</summary>

- `grep` data/advanced/dma_direct/vivado_20261030_024214/utilization.rpt

</details>

<details><summary>工具调用 1 次</summary>

- `grep` data/advanced/dma_direct/vivado_20261030_024214/timing.rpt

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-Process -Id 44316 -ErrorAction SilentlyContinue | Select-Object Id,ProcessName

</details>

<details><summary>工具调用 1 次</summary>

- `grep` data/advanced/dma_direct/vivado_20261030_024214/candidate/dma_direct.hwh

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/ascon_dma/check_hwh.py data/advanced/dma_direct/vivado_20261030_024214/candidate/dma_direct.hwh --output data/advanced/dm

</details>

<details><summary>工具调用 1 次</summary>

- `read` src/pynq/dma_transport.py

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `read` data/advanced/puf/physical_quality_decode_20261030_023728

</details>

<details><summary>工具调用 1 次</summary>

- `read` data/advanced/puf/physical_quality_decode_20261030_023728/verification_manifest.json

</details>

<details><summary>工具调用 1 次</summary>

- `grep` data/advanced/puf/physical_quality_decode_20261030_023728/verification_manifest.json

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path import json,hashlib r=Path('.').resolve();p=r/'data/advanced/puf/physical_quality_decode_20261030_023728';m=json

</details>

### 模型回答（2026-10-30 03:43）

高速路径已完成代码、全量仿真及 100 MHz 实现，候选 bit/HWH 已归档。

CPU-DMA 和 PUF 独立上板工程仍在后台验证。结果返回后继续核验、整理交接材料；目前不宣称全部完成。

<details><summary>工具调用 5 次</summary>

- `read` data/advanced/puf_soc/validation_20261030.md
- `read` data/advanced/puf_soc/handoff_updates.md
- `read` board/vivado_zynq7000_xc7z020_puf_v2/readme.md
- `read` board/vivado_zynq7000_xc7z020_puf_v2/candidate
- `shell` git status --short

</details>

<details><summary>工具调用 1 次</summary>

- `read` .gitignore

</details>

<details><summary>工具调用 1 次</summary>

- `read` board/vivado_zynq7000_xc7z020_puf_v2/verify_delivery.py

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 board/vivado_zynq7000_xc7z020_puf_v2/verify_delivery.py

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

### 模型回答（2026-10-30 04:20）

PUF 实际 SoC 候选已完成并经父会话核验，文件在：

`board/vivado_zynq7000_xc7z020_puf_v2/candidate/`

它仍是**结构诊断候选**：已定义路径时序通过，但 RO 未约束路径尚未签核。相关限制、测试记录和上板入口已更新。

CPU-DMA 的最终工程验证仍在后台进行；返回后继续完成整体验证与交接。

### 模型回答（2026-10-30 04:55）

CPU-DMA 的最终结果已返回：**80 MHz 实现通过**，完整 7,418 项 XSim 和 95 项真实 DMA/CPU/vendor BRAM 联合仿真通过。100 MHz 的失败及优化尝试已保留；这个实验候选不会与原 100 MHz 发布版混称。

我现在核对最后的工件哈希，更新交接索引并关闭本轮会话。

<details><summary>工具调用 5 次</summary>

- `read` data/advanced/dma_cpu/handoff_summary.json
- `read` data/advanced/dma_cpu/vivado_20261030_040257
- `read` board/vivado_zynq7000_xc7z020_pynq_dma_cpu/readme.md
- `glob` board/vivado_zynq7000_xc7z020_pynq_dma_cpu/*verify*
- `read` data/advanced/dma_cpu/vivado_20261030_040257/candidate

</details>

<details><summary>工具调用 6 次</summary>

- `read` board/vivado_zynq7000_xc7z020_pynq_dma_cpu/readme.md
- `read` board/vivado_zynq7000_xc7z020_pynq_dma_cpu/setup.tcl
- `read` data/advanced/dma_cpu/vivado_20261030_040257/candidate_audit.json
- `read` data/advanced/dma_cpu/vivado_20261030_040257/sha256.json
- `read` data/advanced/dma_cpu/vivado_20261030_040257/result.txt
- `read` data/advanced/dma_cpu/vivado_20261030_040257/readme.md

</details>

<details><summary>工具调用 5 次</summary>

- `read` data/advanced/dma_cpu/xsim_20261030_014606_238543/verified.json
- `read` data/advanced/dma_cpu/xsim_20261030_030042_215364/verified.json
- `read` data/advanced/dma_cpu/unit_20261030_043721_118939
- `glob` sim/pynq_dma_cpu/*verify*
- `read` build/advanced/cpu_dma_80mhz.tcl

</details>

<details><summary>工具调用 1 次</summary>

- `read` sim/pynq_dma_cpu/verify_xsim.py

</details>

<details><summary>工具调用 2 次</summary>

- `shell` python -X utf8 sim/pynq_dma_cpu/verify_xsim.py data/advanced/dma_cpu/xsim_20261030_014606_238543 --marker CPU_DMA_VENDOR_TEST_PASS --cases 7
- `shell` python -X utf8 sim/pynq_dma_cpu/verify_xsim.py data/advanced/dma_cpu/xsim_20261030_030042_215364 --marker CPU_VENDOR_DMA_TEST_PASS --cases 9

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' from pathlib import Path import json,hashlib,xml.etree.ElementTree as ET r=Path('.').resolve();out=r/'data/advanced/dma_cpu/vivado_202610

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 3 次</summary>

- `shell` git diff --check
- `shell` git diff --name-only -- src/rtl board ascon
- `shell` @' from pathlib import Path import json,hashlib r=Path('.');index=json.loads((r/'data/advanced/current_candidates.json').read_text(encoding=

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-Process -Id 17680,43728,42504,10524,44316 -ErrorAction SilentlyContinue | Select-Object Id,ProcessName

</details>

<details><summary>工具调用 1 次</summary>

- `patch` 

</details>

### 模型回答（2026-10-30 05:11）

本轮离线实现与验证已收口，产出三个独立候选：

| 候选 | 完成情况 |
|---|---|
| **HW_DIRECT 高速路径** | 支持 PT/AD 各 **1KiB**；全量 KAT、协议及生命周期验证通过；**100MHz，WNS +0.345ns**，已生成 bit/HWH |
| **CPU-DMA** | 保留 SW/MMIO/ISE；**7,418 项 XSim＋95 项实际 DMA IP 联合仿真通过**；合格候选为 **80MHz，WNS +0.601ns**，100MHz 失败证据保留 |
| **PUF v2 SoC** | 已实现失败关闭、内部 key 驱动 AEAD、诊断 helper 持久化及小镜像认证原型；固件和联合仿真通过，已生成**结构诊断候选** |

**边界：**新版本均未上板。PUF 尚未完成 RO 全域时序、熵与可靠性验证；保密 helper/ECC 安全定案及完整可信启动仍未完成。

### 交接入口
- [候选文件与哈希索引](data/advanced/current_candidates.json)
- [详细状态与证据](docs/advanced_offline_status_20261030.md)
- [上板操作清单](docs/advanced_board_handoff.md)
- [高速路径快速启动](board/vivado_zynq7000_xc7z020_dma_direct/quickstart.md)

已核验候选哈希、更新进度并关闭本轮 Vivado 会话。**原正式 release 和已提交简介未改，未 commit/push。**
