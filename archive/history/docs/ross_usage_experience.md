# AMD Ross 辅助设计套件使用心得

2026-10-31；owner TBD。依据本仓库 `project_log/`、`docs/ross_and_engineering_skills_evaluation.md`、
`docs/timing_acb_validation.md`、`docs/dcache_fix_checklist_en.md` 与
`board/vivado_zynq7000_xc7z020_puf_v2/methodology_resolution_report.md` 的已有记录整理，
不含新的测量。

## 1. 接入过程

| 日期 | 状态 | 证据 |
|---|---|---|
| 2026-10-17（V07） | 只做只读评估。官方下载入口返回 BIG-IP 错误 19，未取得 Server，MCP 时序/资源查询记为 `not_measured` | `docs/ross_and_engineering_skills_evaluation.md` |
| 2026-10-18（V08） | 本机已有 `vivado-mcp-server 2026.9.1`，以 stdio 方式登记到 OpenCode 全局配置，`VIVADO_PATH` 指向 Vivado 2025.2，实测可连接 | `project_log/actual_progress.md` V08 条目 |

此后 RTL lint、时序端点分析和长时间实现都通过 Ross MCP 完成。工程版本保持 Vivado 2025.2，未升级到 2026.1。

## 2. 实际用途与结果

| 场景 | 用法 | 结果 |
|---|---|---|
| dcache 修复后的 RTL 检查（V08） | `vivado-rtl-lint` Skill，与 HEAD 对照 | 2 条 WARNING（ASSIGN-1、ASSIGN-6），与 HEAD 完全相同，修复未引入新告警 |
| 时序瓶颈定位（V09） | 在独立目录打开 fix_r1 routed DCP 副本，导出全部 156 个失败端点 | ISE 93 / 乘法器 48 / dcache 11 / 其他 4，据此确定 A→C→B 修改顺序 |
| 双策略实现（V09） | MCP 执行 `source build/build_timing_acb.tcl` | exit 0，3895.571 s；PostRoute WNS=+0.001 ns，Remap WNS=+0.007 ns，TNS=0，四类失败端点全部归零 |
| DSP 寄存器打包核实 | 只读查询 Remap DCP | 4 个乘法 DSP 均 AREG/BREG=1，仅 1 个 PREG=1，以实测属性代替按编码意图推测 |
| PUF SoC 方法学检查 | 参考 timing-methodology Skill 的 TIMING-6/7/17 指引 | 逐项判定处置方式，未加豁免、全局 clock group 或成片 false path |

V09 的时序结果只表示既有 100 MHz 约束下 STA 通过，余量 1–7 ps；IO delay、电气、DRC 与实板仍需各自验收。

## 3. 优点

- **AI 能直接驱动 Vivado Tcl**：打开 checkpoint、查询路径、生成报告都可在对话中完成，“定位—修改—复验”的周期明显缩短。
- **能拿到完整数据**：通过 MCP 导出全部失败端点而非只看 top-20，才发现乘法器这一第二瓶颈（lessons L88）。
- **长任务可托管**：一个多小时的实现在 MCP 会话中运行，期间可并行处理其他工作。
- **Skill 带版本分支**：lint Skill 含 2026.1 之前版本的报告解析流程，在 2025.2 上仍可使用。

## 4. 踩过的坑

| 编号 | 现象 | 处理方法 |
|---|---|---|
| L91 | Ross MCP 按命令字符串做短时间去重；中途切换 project/top 后再发相同的 `close_project`/`launch_simulation` 可能被误跳过 | 检查返回值中的 SKIPPED；改用语义相同的显式参数重发；从真实 simulator transcript 核实本次 top 与终止 PASS |
| L85 | 批命令中一条失败（如无设计时 `close_design`），同批后续命令全部跳过，后续 lint 读到旧文件 | 每次 lint 使用独立会话/目录，核对日志中的文件路径 |
| L87 | 2025.2 不支持 lint Skill 的 `linterCsvFile` 参数（Synth 8-734） | 按 Skill 的 <2026.1 分支清空该参数，用 `.rpt` + `parse_lint_report.py` 生成 CSV |
| L68 | Ross 整体测试基线为 2026.1，各 Skill 最低版本不同；timing-methodology、ip-configurator、ILA/VIO 要求 2026.1+；2025.2 不接受 `report_methodology -json` | 以各 SKILL 声明为准，不凭整体版本一概判断；不兼容时保留原生文本报告流程 |
| — | 本机未配置 `amd-doc-search` MCP，无法检索文档 | 不熟悉的命令/IP 参数用 Vivado `help`、对象内省和报错信息确认，不凭印象猜测 |
| — | 多个 AI/人工 Vivado 会话并行时会抢同一隔离工程、顶掉 run，或恢复已删除的报告 | 每个任务独立会话与工作目录，核对 session_id 与进程 |
| — | `execute` 本身能写工程，工具白名单不能保证 Tcl 只读 | 分析一律在 DCP 副本或新目录中进行，不打开原始 XPR，退出时不保存工程 |

## 5. 总结

Ross 的主要价值是让 AI 直接驱动 Vivado，形成“查报告—定位—修改—复验”的闭环。在本项目中，它支撑了
dcache 修复后的 lint 对照、156 个失败端点分类以及最终 100 MHz 时序收敛的实现。

它是工具链的一环，不替代验证本身：功能正确性靠 TestBench、独立黄金参考与 KAT；物理实现以 post-route
报告为准；板上行为靠实板测试。由于版本差异（2025.2 对 2026.1）和 MCP 自身行为（命令去重、批命令中途失败），
每次 MCP 返回的结果都要对照真实日志和产物核实，不能只看返回文字。

10-17 因下载受阻未接入，相关指标记为 `not_measured`；10-18 接入后才有实测数据，报告引用时保持这一口径。
