# PYNQ skill 制作与验证方案

- 工具：opencode；模型：claude-opus-5-5；会话：`ses_e74bfb58cffdMQh2fTMt8YBnnX`
- 开始：2026-10-30 13:20；用户提示 4 条；工具调用 117 次

## 用户提示（2026-10-30 13:20）

当前的skill只有对于rtl设计的一些原则，而没有有关PYNQ的skill；这个图片是我们对于skill的要求，请你按照要求给我们制作一份skill，并且给出验证方案。我们现在的困境是，加入skill和不加入skill在简单RTL生成时并无太大区别，并且在同一agent情况下去测试无法控制变量，带来验证结论不严谨的问题

### 模型回答（2026-10-30 13:20）

我先看一下仓库里现有的 skill、PYNQ 代码和测试指南。

<details><summary>工具调用 3 次</summary>

- `shell` git status --short | Select-Object -First 40; git log --oneline -5
- `glob` **/SKILL.md
- `glob` **/*{pynq,PYNQ,overlay,skill}*

</details>

<details><summary>工具调用 3 次</summary>

- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\readme.md
- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\rtl-design-discipline\SKILL.md
- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\docs\skill_test_guide_20261030.md

</details>

### 模型回答（2026-10-30 13:20）

现在看已有的 PYNQ 主机代码与踩坑记录，Skill 的经验要从这些真实失败里提炼。

<details><summary>工具调用 3 次</summary>

- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\pynq_transport.py
- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\dma_transport.py
- `grep` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\lessons_learned.md

</details>

<details><summary>工具调用 3 次</summary>

- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\lessons_learned.md
- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\lessons_learned.md
- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_dma_cpu\pynq27_audit.md

</details>

<details><summary>工具调用 2 次</summary>

- `shell` python --version; python -c "import pytest;print('pytest',pytest.__version__)"; Get-Command opencode -ErrorAction SilentlyContinue | Select-
- `skill` 

</details>

<details><summary>工具调用 1 次</summary>

- `webfetch` 

</details>

<details><summary>工具调用 2 次</summary>

- `webfetch` 
- `webfetch` 

</details>

<details><summary>工具调用 2 次</summary>

- `shell` $f='board/vivado_zynq7000_xc7z020_pynq/release/pynq.hwh'; (Get-Item $f).Length; Select-String -Path $f -Pattern '<MEMRANGE ' | Select-Object
- `glob` {src/pynq/readme.md,src/pynq/test_pynq_transport.py,board/vivado_zynq7000_xc7z020_pynq/readme.md,board/vivado_zynq7000_xc7z020_pynq/release/

</details>

<details><summary>工具调用 2 次</summary>

- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq\release\manifest.json
- `glob` board/**/*{utilization,util}*.rpt

</details>

<details><summary>工具调用 1 次</summary>

- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf\candidate\reports\utilization.rpt

</details>

### 模型回答（2026-10-30 13:22）

真实 hwh/manifest/utilization 报告都可以当测试夹具。确认一下 OpenCode V2 无头运行的命令语法（A/B 批量跑要用）。

<details><summary>工具调用 1 次</summary>

- `webfetch` 

</details>

<details><summary>工具调用 1 次</summary>

- `webfetch` 

</details>

### 模型回答（2026-10-30 13:22）

资料与关键事实都已核实。现在开始写 Skill，放在 `skill/pynq-overlay-workflow/`。先写主文件 SKILL.md：

<details><summary>工具调用 1 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\SKILL.md

</details>

### 模型回答（2026-10-30 13:24）

接下来是两份参考文档（错误定位表、接口契约格式）：

<details><summary>工具调用 2 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\references\failure_signatures.md
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\references\contract_format.md

</details>

### 模型回答（2026-10-30 13:25）

现在写工具包。先是工件校验、hwh 解析和 overlay 校验：

<details><summary>工具调用 3 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\__init__.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\artifacts.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\hwh.py

</details>

### 模型回答（2026-10-30 13:25）

Clean up a leftover no-op loop in hwh.py:

<details><summary>工具调用 1 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\hwh.py

</details>

<details><summary>工具调用 1 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\overlay_check.py

</details>

### 模型回答（2026-10-30 13:26）

Register contract module (load/validate, field access with rc/w1c protection, hwh cross-check, code generation):

<details><summary>工具调用 1 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\regmap.py

</details>

### 模型回答（2026-10-30 13:26）

That constructor check is convoluted; simplify with a validation marker:

<details><summary>工具调用 2 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\regmap.py
- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\regmap.py

</details>

### 模型回答（2026-10-30 13:27）

Generated driver would embed JSON `null` (invalid Python) — switch to a Python literal:

<details><summary>工具调用 3 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\regmap.py
- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\regmap.py
- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\regmap.py

</details>

### 模型回答（2026-10-30 13:27）

Now the bounded DMA helper and HLS control helper:

<details><summary>工具调用 2 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\dma.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\hls_ctrl.py

</details>

### 模型回答（2026-10-30 13:28）

Now the offline fakes (MMIO, non-coherent cache buffers, AXI DMA model with fault injection, overlay):

<details><summary>工具调用 1 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\fakes.py

</details>

### 模型回答（2026-10-30 13:28）

Fix the fake: per PYNQ's `_first_transfer` workaround, Idle is not set merely by RS:

<details><summary>工具调用 1 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\fakes.py

</details>

### 模型回答（2026-10-30 13:28）

Now golden comparison/timing and report collection:

<details><summary>工具调用 2 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\golden.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\report.py

</details>

### 模型回答（2026-10-30 13:29）

Now the CLI and the three non-Ascon example contracts:

<details><summary>工具调用 4 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill_cli.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\examples\axi_gpio.contract.json
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\examples\hls_vadd.contract.json
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\examples\axi_dma_simple.contract.json

</details>

### 模型回答（2026-10-30 13:30）

Now offline tests, including a synthetic ZynqMP-style hwh fixture (cross-family) plus the real XC7Z020 release artifacts as fixtures:

<details><summary>工具调用 2 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\tests\fixtures\mini_zynqmp.hwh
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\tests\conftest.py

</details>

<details><summary>工具调用 3 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\tests\test_overlay.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\tests\test_regmap.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\tests\test_dma_golden_report.py

</details>

### 模型回答（2026-10-30 13:31）

Tidy up that messy quarantine test:

<details><summary>工具调用 2 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\tests\test_dma_golden_report.py
- `shell` python -m pytest skill/pynq-overlay-workflow/tests -q -p no:cacheprovider 2>&1 | Select-Object -Last 40

</details>

### 模型回答（2026-10-30 13:32）

Only a test-regex mismatch; make the error message explicit instead:

<details><summary>工具调用 2 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\scripts\pynq_skill\dma.py
- `shell` python -m pytest skill/pynq-overlay-workflow/tests -q -p no:cacheprovider -rs 2>&1 | Select-Object -Last 8; python skill/pynq-overlay-workfl

</details>

<details><summary>工具调用 2 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\SKILL.md
- `shell` python -c "import numpy; print(numpy.__version__)"

</details>

<details><summary>工具调用 4 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\fake_pynq\pynq\__init__.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\fake_pynq\pynq\lib\dma.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\fake_pynq\pynq\lib\__init__.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\fake_pynq\pynq\ps.py

</details>

### 模型回答（2026-10-30 13:36）

Now task definitions (prompts, agent-visible files, hidden scenarios, and per-scenario checks):

<details><summary>工具调用 1 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\tasks.py

</details>

### 模型回答（2026-10-30 13:37）

Clean up a garbled expression in the T3 check:

<details><summary>工具调用 1 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\tasks.py

</details>

### 模型回答（2026-10-30 13:38）

Now the trial generator, grader and statistics:

<details><summary>工具调用 3 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\make_trials.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\grade.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\stats.py

</details>

### 模型回答（2026-10-30 13:39）

Placebo skill (controls for "a skill was loaded / extra context" without PYNQ technical content), then reference solutions to validate the grader itself:

<details><summary>工具调用 9 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\placebo\pynq-style-notes\SKILL.md
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\selftest\t1_overlay\good\solution.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\selftest\t1_overlay\naive\solution.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\selftest\t2_hls\good\solution.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\selftest\t2_hls\naive\solution.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\selftest\t3_dma\good\solution.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\selftest\t3_dma\naive\solution.py
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\selftest\t4_diagnose\good\answers.md
- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\selftest\t4_diagnose\naive\answers.md

</details>

### 模型回答（2026-10-30 13:40）

Now validate the measuring instrument itself — the good reference must pass everything, the naive one must fail on the traps:

<details><summary>工具调用 1 次</summary>

- `shell` $h='skill/ab_eval_pynq/harness'; foreach ($t in 't1_overlay','t2_hls','t3_dma','t4_diagnose') { foreach ($v in 'good','naive') { "=== $t / $

</details>

<details><summary>工具调用 2 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\skill_mutation_check.py
- `shell` python skill/ab_eval_pynq/harness/skill_mutation_check.py; echo "exit=$LASTEXITCODE"

</details>

<details><summary>工具调用 3 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\tests\test_regmap.py
- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\pynq-overlay-workflow\tests\test_regmap.py
- `shell` python -m pytest skill/pynq-overlay-workflow/tests -q -p no:cacheprovider 2>&1 | Select-Object -Last 3; python skill/ab_eval_pynq/harness/sk

</details>

<details><summary>工具调用 2 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\skill_mutation_check.py
- `shell` python skill/ab_eval_pynq/harness/skill_mutation_check.py; echo "exit=$LASTEXITCODE"

</details>

### 模型回答（2026-10-30 13:52）

The "unbounded wait" mutant makes the suite itself spin forever — which *is* detection, but the checker needs a timeout to record it. Add one:

<details><summary>工具调用 2 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\skill_mutation_check.py
- `shell` Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'pytest' -and $_.CommandLine -match 'Temp' 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python skill/ab_eval_pynq/harness/skill_mutation_check.py; echo "exit=$LASTEXITCODE"

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $h='skill/ab_eval_pynq/harness'; python $h/make_trials.py --root build/local/ab_should_refuse --reps 1 2>&1 | Select-Object -Last 1 $r='C:\U

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $h='skill/ab_eval_pynq/harness'; $r='C:\Users\HXZ\AppData\Local\Temp\opencode\ab_dry' foreach ($t in 't1_overlay','t3_dma','t4_diagnose') { 

</details>

### 模型回答（2026-10-30 13:57）

Pipeline works end to end. One anomaly: t4 "with" scored 5/8 although it holds the 8/8 reference answers. Let me check whether that's the grader or my PowerShell copy step:

<details><summary>工具调用 1 次</summary>

- `shell` $r='C:\Users\HXZ\AppData\Local\Temp\opencode\ab_dry'; python -c "import sys;b=open(r'$r\t4_diagnose\with\rep01\answers.md','rb').read();prin

</details>

### 模型回答（2026-10-30 13:57）

Confirmed — it's my PowerShell step (PS 5 read the UTF-8 file as GBK and re-encoded it into mojibake), not the grader. Redo that copy with Python and re-grade:

<details><summary>工具调用 1 次</summary>

- `shell` $h='skill/ab_eval_pynq/harness'; $r='C:\Users\HXZ\AppData\Local\Temp\opencode\ab_dry' python -c "import pathlib;src=pathlib.Path(r'$h/selfte

</details>

<details><summary>工具调用 1 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\harness\make_trials.py

</details>

### 模型回答（2026-10-30 13:59）

Now the validation plan document:

<details><summary>工具调用 1 次</summary>

- `write` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\ab_eval_pynq\README.md

</details>

### 模型回答（2026-10-30 13:59）

Now update the repo's skill index and project logs (required by AGENTS.md rule 11). Let me check their formats first:

<details><summary>工具调用 1 次</summary>

- `shell` Get-Content project_log/actual_progress.md -Encoding UTF8 -TotalCount 25; "-----"; Get-Content project_log/development_log.md -Encoding UTF8

</details>

<details><summary>工具调用 2 次</summary>

- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\actual_progress.md
- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\development_log.md

</details>

<details><summary>工具调用 4 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\actual_progress.md
- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\development_log.md
- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\lessons_learned.md
- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\readme.md

</details>

<details><summary>工具调用 2 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\readme.md
- `shell` Get-ChildItem skill -Recurse -Directory -Filter __pycache__ | Remove-Item -Recurse -Force; $env:PYTHONDONTWRITEBYTECODE='1'; python -m pytes

</details>

### 模型回答（2026-10-30 14:01）

我做了一个通用的 PYNQ Skill，以及一套能控制变量的验证工具。Skill 自带的工具在离线测试里全部通过；**真正用 agent 做的对照实验和上板验证都还没跑**，所以现在还不能说这个 Skill 能提升效果。

## 1. Skill：`skill/pynq-overlay-workflow/`

`SKILL.md` 把工作分成五段，每段都有能直接判断过没过的检查：**工件 → 加载 → 寄存器 → 数据搬运 → 证据**。内容对应图里的四项要求：

| 图中要求 | 对应内容 |
|---|---|
| Overlay 加载与校验、`register_map` 用法 | 用哈希证明 bit 和 hwh 是同一次生成的，校验通过才下载；加载后核对 IP 列表、地址、ID 寄存器和时钟；说明 `register_map` 什么时候有、什么时候只能直接读写寄存器 |
| DMA 搬运与缓存一致性、出错定位 | 每次等待都有超时；数据送进硬件前刷缓存（flush），读回前作废缓存（invalidate）；结果按硬件实际收到的长度取；出错时先确认 DMA 停了再释放缓冲；附一张"现象 → 原因 → 先查什么"的表 |
| 从接口契约生成调用代码和测试骨架 | 用一份 JSON 描述寄存器，命令行生成驱动代码和 pytest 测试骨架 |
| 黄金参考比对、性能与资源报告 | 比对出错时会提示可能原因（全 0、读到上一次的旧数据、字节顺序反了、整体错位、只有尾部错）；性能分首次调用和预热后分别统计；从 Vivado 报告里读资源和时序，每个数字都标明是实测、模拟还是没测 |

"不和本题绑定"的做法：没有任何 Ascon 地址或长度，三个示例分别是 AXI GPIO、HLS 向量加法和 AXI DMA；hwh 解析用本仓库真实的 XC7Z020 工件和一份 ZynqMP 结构的样例测过。这份样例是我手写的，不是 Vivado 生成的。

经验来源是项目里真实踩过的坑，PYNQ 的具体行为（例如 DMA 驱动的 `wait()` 没有超时、会一直卡住）我对照 PYNQ v2.7.0 源码核实过。

## 2. 验证方案：`skill/ab_eval_pynq/README.md`

针对你们的两个困境：

- **加不加 Skill 没区别**：原因是题目太简单，模型本来就会，两组都满分，比不出差别。新题目在提示词里把"要做到什么"写清楚，两组都知道；但每题藏着 6–8 个陷阱场景，考的是"怎么做才真的对"。例如：hwh 是旧的、HLS 核读一次就清零的完成位（ap_done）、DMA 等不到包结束信号（TLAST）时 `wait()` 永远不返回、地址只写了低 32 位、缓存没刷。
- **同一 agent 测试无法控制变量**：每次试验都是一个新的 `opencode run`，在仓库外的新目录里跑（不然会读到上层的 `AGENTS.md`；脚本发现目录在仓库里会直接拒绝）。三组只差 Skill 文件和一条权限规则：
  - 有 Skill；
  - 无 Skill（权限明确拒绝加载）；
  - 安慰剂组：一份长度相当、只讲代码风格的 Skill，用来区分"Skill 的技术内容有用"和"只是多给了一段文字"。
  
  其他条件全部相同：同一模型，各组都禁网络、禁读目录外文件、默认禁 shell。试验顺序随机打乱；评分完全自动，用一个模拟的 PYNQ 运行生成的代码；统计用精确置换检验。每组至少跑 5 次，推荐 8 次，因为每组 2 次时即使两组完全分开 p 也只有 0.33。

## 3. 已经跑过的检查（Windows，Python 3.13）

| 检查 | 结果 |
|---|---|
| Skill 工具的单元测试 | 47 个全部通过，包括本仓库真实的 release 工件和 Vivado 资源报告 |
| 变异测试（故意往工具里改出 13 种典型错误，看测试能不能发现） | 13/13 被发现。第一次跑时有一种错误没被发现，原因是我测试里的模拟 HLS 核写错了，修好后重跑通过 |
| 评分器能不能区分好坏代码 | 标准写法在四道题上全部满分；常见写法得 3/6、0/6、3/6、0/8，失分都在预先设计的陷阱上 |
| 整条流程（生成试验 → 评分 → 统计） | 用参考答案代替 agent 输出跑通了。这只是检查流程，**不是 Skill 的效果数据** |
| 真实 agent 对照实验 | 还没跑 |
| 上板验证 | 还没跑 |

另外修了一个会让结论失真的问题：Windows PowerShell 5 默认把 UTF-8 中文按 GBK 读。这会把乱码题目发给 agent，已在生成的运行脚本里改为显式 UTF-8 读取。

## 4. 下一步

1. 按 `skill/ab_eval_pynq/README.md` 第 3 节执行：`make_trials.py --root <仓库外的目录> --reps 5 --model <你们用的模型>` → 运行生成的 `run_all.ps1` → `grade.py` → `stats.py`。先用 `opencode run --help` 确认本机命令行的用法，这个我在这里没法验证。全部跑完是 60 次 `opencode run`。时间不够的话，先跑陷阱最多的 T3（DMA）和 T1（overlay），三组各 5 次。
2. 对外宣称效果前，请一位没读过 Skill 的队友另写 1–2 道题，只正式跑一次，跑完不再根据结果改 Skill，避免 Skill 只是针对这几道题调好的。
3. 上板时至少用一个非 Ascon 的 overlay，例如 PYNQ 自带 base overlay 里的 AXI GPIO。

`skill/readme.md` 和 `project_log/` 下的三个日志已更新。没有改 RTL、release 和现有 PYNQ 代码，也没有 commit。

## 用户提示（2026-10-30 14:04）

你先将这个skill单独上传至main中，交由我队友进行验证

<details><summary>工具调用 1 次</summary>

- `shell` git branch --show-current; git remote -v; git diff --cached --name-only; git fetch origin 2>&1 | Select-Object -Last 3; git status -sb | Sel

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-ChildItem skill/pynq-overlay-workflow -Recurse -Directory -Filter __pycache__ | Remove-Item -Recurse -Force; git add -- skill/pynq-overl

</details>

### 模型回答（2026-10-30 14:04）

暂存区只有这 22 个 Skill 文件，空白检查通过（CRLF 提示来自本机 `autocrlf` 设置，不影响内容）。提交并推送：

<details><summary>工具调用 1 次</summary>

- `shell` git commit -q -m "feat(skill): 新增通用 PYNQ Skill pynq-overlay-workflow（L1 离线测试通过，待队友验证）" -m "五段门禁流程（工件/加载/寄存器契约/数据通路/证据）、错误定位表、标准库工具包与 47 个离线测

</details>

### 模型回答（2026-10-30 14:05）

推送成功（PowerShell 显示的 exit 1 只是因为 git 把进度信息写到了 stderr）。最后确认提交里只有 Skill 文件：

<details><summary>工具调用 1 次</summary>

- `shell` git show --stat --format="%H" HEAD | Select-Object -Last 3; git ls-remote origin refs/heads/main

</details>

### 模型回答（2026-10-30 14:05）

Skill 已推送到 `main`，提交是 `7bc1abf`，远端 `main` 已经指向这个提交。这次提交只有 `skill/pynq-overlay-workflow/` 下的 22 个文件，你们其他未提交的改动都没动。

**这次没有上传的内容**（还在本地，未提交）：
- 验证工具 `skill/ab_eval_pynq/`：评分器、题库、生成试验和统计的脚本、安慰剂 Skill、验证方案 README。
- `skill/readme.md` 里新增的 Skill 说明。
- `project_log/` 下三个日志的更新。

**队友拿到后可以先这样验证：**
1. `git pull`。
2. 运行离线测试：`python -m pytest skill/pynq-overlay-workflow/tests -q`，预期 47 个全部通过。需要 Python 3.8 以上和 pytest，不需要 `pynq`。有两个测试会读仓库里的真实板卡工件，缺文件时会自动跳过，不算失败。
3. 安装给 agent 用：把这个目录复制到 OpenCode 的 skills 目录，项目级是 `.opencode/skills/pynq-overlay-workflow/`，全局是 `~/.config/opencode/skills/`。
   - **如果要做有/无 Skill 的对照实验，不要装到全局目录**，否则"无 Skill"那组也能加载到它，对照就不成立了。

如果队友要做有/无/安慰剂三组的对照实验，需要用到 `skill/ab_eval_pynq/`。要的话我可以把它单独再提交、推送一次。

## 用户提示（2026-10-30 14:17）

我这边一个队友去做对照实验，请你先把skill/ab_eval_pynq/提交一次

<details><summary>工具调用 1 次</summary>

- `shell` git fetch origin 2>&1 | Out-Null; git status -sb | Select-Object -First 1; git diff --cached --name-only; Get-ChildItem skill/ab_eval_pynq -

</details>

### 模型回答（2026-10-30 14:17）

暂存区只有 `skill/ab_eval_pynq/` 的 19 个文件，空白检查通过。提交并推送：

<details><summary>工具调用 1 次</summary>

- `shell` git commit -q -m "feat(skill-eval): 新增 pynq-overlay-workflow 受控对照实验工具 ab_eval_pynq" -m "with/without/placebo 三组隔离试验生成、假 PYNQ 隐藏场景判分、置换检验统计与变

</details>

### 模型回答（2026-10-30 14:17）

对照实验工具已推送到 `main`，提交是 `4d3128a`。这次提交只有 `skill/ab_eval_pynq/` 下的 19 个文件，你们其他未提交的改动没有动。

队友 `git pull` 后，按 `skill/ab_eval_pynq/README.md` 第 3 节操作：

1. **先确认工具本身没问题**（不需要板卡和 agent）：
   - `python -m pytest skill/pynq-overlay-workflow/tests -q`，预期 47 个全部通过。
   - `python skill/ab_eval_pynq/harness/skill_mutation_check.py`，预期 13/13 被发现。
   - 评分器自检：`python skill/ab_eval_pynq/harness/grade.py --task t3_dma --solution skill/ab_eval_pynq/harness/selftest/t3_dma/good`，再把末尾的 `good` 换成 `naive` 跑一次。预期 good 满分，naive 在陷阱场景上失败。
   - 评分器自检需要 numpy。naive 版本有个场景会卡住，评分器 20 秒后自动终止并记为"卡死"，属于正常现象。
2. **生成试验目录，必须放在仓库外面**：`python skill/ab_eval_pynq/harness/make_trials.py --root D:\ab_trials\run1 --reps 5 --model <provider/model>`。三组必须用同一个模型。目录放在仓库里时脚本会直接拒绝。
3. **执行**：先用 `opencode run --help` 确认本机命令行用法，这个我没法在这边验证。然后运行生成的 `run_all.ps1`，一共 60 次 `opencode run`。
4. **评分和统计**：先运行 `grade.py --root D:\ab_trials\run1`，再运行 `stats.py D:\ab_trials\run1\results.csv`。

**队友需要注意的四点：**
- **不要把 Skill 装到全局目录** `~/.config/opencode/skills`。"无 Skill"那组虽然在权限上拒绝加载，但最好不留这个隐患。
- **默认所有组都禁用 shell**。原因是开了 shell 后，agent 能直接读到仓库里的 Skill，隔离就失效了。如果想让 agent 自己跑测试，只能在没有本仓库的机器或账户上加 `--allow-shell`。
- **原始数据全部保留**，包括失败的试验和"有 Skill 组却没加载 Skill"的试验（可以从交付文件首行有没有 `skill-canary` 标记看出来）。不要删掉或挑选。
- **结果在模拟的 PYNQ 上得到，只能标为 simulated**，不能写成上板通过。

`skill/readme.md` 和 `project_log/` 下三个日志的更新仍然只在本地，没有提交。

## 用户提示（2026-10-30 15:07）

请你把有关skill的全部内容提交一下，包括README因为我要给我队友看，尽量全面，但是不要污染到仓库

### 模型回答（2026-10-30 15:07）

先看剩下和 Skill 有关的改动里，哪些是我写的、哪些是别人原本就没提交的，避免把无关内容混进去：

<details><summary>工具调用 1 次</summary>

- `shell` git status --short -- skill docs/skill_test_guide_20261030.md project_log; "---- readme diff"; git diff --stat -- skill/readme.md skill/rtl-

</details>

<details><summary>工具调用 1 次</summary>

- `shell` git diff -- skill/readme.md skill/rtl-design-discipline/SKILL.md | Out-File -Encoding utf8 $env:TEMP\opencode\skilldiff.txt; Get-Content -En

</details>

<details><summary>工具调用 1 次</summary>

- `read` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\readme.md

</details>

<details><summary>工具调用 1 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\skill\readme.md

</details>

### 模型回答（2026-10-30 15:07）

再让测试指导表与新 Skill 保持一致（它原先写着"通用 PYNQ 工具未实现"）：

<details><summary>工具调用 2 次</summary>

- `edit` C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\docs\skill_test_guide_20261030.md
- `shell` git add -- skill/readme.md skill/rtl-design-discipline/SKILL.md docs/skill_test_guide_20261030.md 2>&1 | Out-Null; git diff --cached --name-

</details>

### 模型回答（2026-10-30 15:08）

Only these three files are staged and the whitespace check passes. Committing and pushing:

<details><summary>工具调用 1 次</summary>

- `shell` git commit -q -m "docs(skill): 同步 Skill 目录说明、RTL Skill 措辞修订与 Skill 测试指导表" -m "skill/readme.md 增加目录一览与队友快速上手；rtl-design-discipline 去除未经验证的绝对化

</details>

### 模型回答（2026-10-30 15:08）

推送成功。注意到远端从 `f70ddc8` 前进，而不是我上次推送的 `4d3128a`，确认一下中间那个提交的来历：

<details><summary>工具调用 1 次</summary>

- `shell` git log --oneline -5; git show --stat --format="%h %an %ad %s" f70ddc8 | Select-Object -First 8

</details>

### 模型回答（2026-10-30 15:08）

Skill 相关的剩余内容已经推送到 `main`，提交是 `b2f035b`。至此和 Skill 有关的内容都已上传，仓库里只多了下面这些文件：

| 提交 | 内容 |
|---|---|
| `7bc1abf` | `skill/pynq-overlay-workflow/`：Skill 本体、参考文档、工具代码、离线测试 |
| `4d3128a` | `skill/ab_eval_pynq/`：对照实验工具，验证方案写在它的 `README.md` 里 |
| `b2f035b` | 下面三个文件 |

`b2f035b` 里的三个文件：
- **`skill/readme.md`**：Skill 目录的总说明。这次新增了"目录一览"（说明哪些要装给 agent、哪些只给做实验的人用）和"队友快速上手"（自检命令、安装方法、对照实验从哪看）。还修正了原来"通用 PYNQ Skill 仍未实现"这句已经过时的话，并保留了你们原有的一行交付说明。
- **`skill/rtl-design-discipline/SKILL.md`**：这处修订不是我写的，是工作区里原本没提交的 RTL Skill 改动。内容是把"if-else 一定综合成更深逻辑"这类没有验证过的绝对说法改成严谨表述。因为属于 Skill 内容，按你的要求一起提交了，请你确认可以。
- **`docs/skill_test_guide_20261030.md`**：Skill 测试指导表，原本没有提交。我补了一段，说明 PYNQ Skill 要按 `skill/ab_eval_pynq/README.md` 验证，不按这张表的第 2–3 节。

**为了不污染仓库，故意没有提交的：**
- **`project_log/` 下三个日志**：我写的 Skill 记录和其他人 300 多行与 Skill 无关的进度混在同一批未提交改动里，一起提交会把别人的工作带进来。如果需要，可以只摘出 Skill 相关的段落单独提交。
- 其他未跟踪的板卡工程、仿真、数据目录一律没动，也没有提交缓存或生成文件。

另外，我两次推送之间远端多了两个别人的提交（`5eb64a5`、`f70ddc8`，pynq-puf / pynq-puf3），本地已经包含它们。这次推送没有冲突，也没有覆盖任何人的提交。

队友现在 `git pull` 后，从 `skill/readme.md` 的"队友快速上手"开始看就行。
