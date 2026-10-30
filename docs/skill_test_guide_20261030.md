# 10-30 Skill 测试指导表

目标：先证明**实际提交的 Skill 能指导完成一项正确任务**，再考虑额外效果比较。
owner TBD；执行人由项目方指定。11-01 提交并冻结；长时间与跨平台实验非本轮阻塞。

## 0. 先确认测试对象（不要混淆两种 Skill）

当前已有 `skill/rtl-design-discipline/SKILL.md`，是指导 RTL 设计/评审的文本 Skill。
2026-10-30 新增 `skill/pynq-overlay-workflow/`（通用 PYNQ Skill，覆盖旧看板 S01–S04 的
loader/register/golden/collector），它的验证**不按本表第 2–3 节**，而按
`skill/ab_eval_pynq/README.md`（工具层测试 + 受控 with/without/placebo 对照 + 实板）。
仍不能用 Ascon Notebook 通过来证明这些通用工具已在实板上完成。
如果明天实际测另一份 Skill，先记录准确路径、版本和哈希，再执行对应流程。

## 1. 推荐执行顺序

| 顺序 | 建议时段 | 做什么 | 通过标准 | 必留证据 |
|---|---|---|---|---|
| 1 | 09:00–09:20 | 固定 Skill、输入需求和工具环境 | 文件可读取、无占位依赖；明确实际支持平台 | git HEAD/status、Skill SHA-256、模型/agent/工具版本 |
| 2 | 09:20–09:40 | 新会话按宿主真实方式加载 Skill | 能记录加载的路径/内容；不能只让 AI 口头说已加载 | 完整提示词与加载记录；宿主不支持安装时记为直接提供文本 |
| 3 | 09:40–10:30 | 做一个小型非密码 RTL 任务（下面示例） | 输出模块、寄存器清单、优先级和验证命令完整 | 需求、生成源、回答与每次修订 |
| 4 | 10:30–11:20 | 编译并跑独立自检 TB | 编译 exit0，正确性 PASS，错误返回非零 | 工具版本、完整 stdout/stderr、退出码、TB与seed |
| 5 | 11:20–11:40 | 故意加入一个错误检验 TB 是否敏感 | 错误变体应 FAIL；原文件不覆盖 | 错误补丁、失败日志及恢复后 PASS |
| 6 | 13:00–14:00 | 资源比较（仅若要声称优化效果） | 同工具/part/约束/策略，正确性先通过 | 两版源、综合报告、LUT/FF、是否推断 latch |
| 7 | 14:00–14:30 | 汇总与交接 | 仅声明实际测到的结论，失败保留 | 一页结论、原始文件清单、SHA-256 |
| 8 | 之后 | 录短视频/截图，放入提交包 | 能看清需求→输出→真实测试结果 | 视频及文件哈希 |

时间为建议，不是性能估计；前五步失败先修复，不为了赶时间删除失败用例。
不要求更改或重新实现现有 SoC，也不需要板卡参与文本 Skill 的 RTL 单元验证。

## 2. 最小测试需求（给 agent 的固定题目）

> 请按加载的 RTL design discipline 设计一个 8-bit 同步计数模块。端口 clk、rst_n、clear、
> enable、load、load_data[7:0]、count[7:0]。rst_n 为同步低有效复位。
> 优先级：复位 > clear > load > enable 递增 > 保持；255+1 回绕为0。
> 不增加额外流水级或状态。先列寄存器和下一值选择，再输出可编译 Verilog及验证计划。
> 验证计划必须包括所有控制组合、load 与 enable 同时为1、clear 与 load 同时为1、复位优先级、
> 回绕、保持和连续 load。不修改比赛工程。

这是一项非 Ascon 最小示例，不等于广泛通用性证明。独立 TB 由另一份明确参考规则计算 expected，
不要从生成 RTL 的表达式逐字复制参考模型。先遍历控制组合与边界，再加入固定 seed 的随机序列。
故障注入可把 load/enable 优先级故意调换；若 TB 仍 PASS，测试无效，先修 TB。

可在仓库根建立独立 `build/local/skill_test_20261030/` 执行：

```sh
iverilog -V
iverilog -g2012 -s tb_counter -o build/local/skill_test_20261030/test.vvp <generated_counter.v> <independent_tb.v>
vvp build/local/skill_test_20261030/test.vvp
```

`<...>` 是待生成文件，不是仓库已有脚本；TB 要有 watchdog 和失败 `$fatal(1, ...)`，退出码不能只靠文本判断。
若没有 Icarus，使用实际可用模拟器并保留等价命令，不为缺工具假报完成。

## 3. 如需比较“有 Skill / 无 Skill”

- 两个新会话使用同一模型/设置、同一需求；一组加载 Skill，另一组不加载。
- 两组使用同一独立 TB；记录所有返工，不挑选只对其中一组有利的输出。
- 语义正确性、可读性与 LUT/FF 分开比较。代码短不代表综合资源更少；资源相同也是有效结果。
- 未做综合就写“本轮验证功能与工作流，资源改善 not_measured”，不能写“节省 XX% LUT”。
- 不需要为了这个对照重新跑 SoC 实现；若跑综合，必须同 part、top 端口约束和工具设置。

## 4. 若明天测试对象是 PYNQ 工作流 Skill

先确认真实 Skill 文件存在；若只有 Notebook，结论只能是 Notebook 工作流通过。
使用正式 `release/` 和 `src/pynq/pynq_board_demo.ipynb`，按现有 notebook 从头执行，
不要凭本指南重造 bitstream，也不要改成模拟 backend 冒充硬件。

1. 记录板型、PYNQ/Python版本、source commit、bit/hwh/固件哈希。
2. 加载正式 overlay，确认服务 `simulated=false`、`selftest_mask=7`、PT/AD上限16B。
3. 运行三模式 smoke；需要性能展示时运行已有 warm benchmark。
4. 用 `pynq_board_error_gate.ipynb` 运行现有错误门禁，保留执行后的 Notebook。
5. 上传 JSON/log/identity/ipynb；只展示完成的功能，不能以 Ascon 固定地址示例证明通用寄存器助手已实现。

原始入口和操作以 `src/pynq/readme.md`、`board/vivado_zynq7000_xc7z020_pynq/readme.md` 为准。
如果实际底层 release 哈希不同，先停止混用已有性能值，保留新身份并重新测试。

## 5. 交接模板

保存到 `data/skill/results/20261030_<case>/`（普通文件名小写），不要只发截图：

```text
owner: TBD
skill_path / skill_sha256:
git_head / dirty_diff:
host / tool_versions / model:
input_prompt / source_files / reference_tb / seed:
commands / exit_codes / original_logs:
functional_result:
mutation_result:
resource_result: not_measured 或原始报告路径
supported_scope: 本次实际示例与平台
known_failures / limitations:
```

提交判据：至少一项完整可复查的实际运行；资源或额外通用性未测不阻塞，但必须从宣传结论中去掉。
当日下午把结果交给材料负责人，更新报告 Skill 行，不提前标 done。
