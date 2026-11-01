# Ross 与工程 Skills 评估

2026-10-17；V07；owner TBD。先完成V06阶段性提交，再进行本评估。
稳定检查点为 `2b48a8a730267787b399fe06304ae5e2b53ff203`，已推送
`origin/fix/ascon-key-lifecycle`，草稿 [PR #4](https://github.com/HChenZ/amd_fpga_2026/pull/4)。
**100 MHz timing not met**：WNS=-0.177 ns、TNS=-2.968 ns、31个setup失败端点。
本评估没有执行第三轮实现、Strategy Sweep、工程升级或板卡编程。

## 实际环境与Ross状态

| 项 | 实际核验 |
|---|---|
| Vivado | `E:/2025.2/Vivado/bin/vivado.bat -version`，2025.2 / SW build6299465 |
| Codex | 原生Windows桌面26.1007.9446.0；CLI0.162.0-alpha.17.2 |
| WSL | Ubuntu为WSL2；本次核验时处于Stopped，当前Codex和PowerShell不在WSL内 |
| 用户MCP配置 | `%USERPROFILE%/.codex/config.toml`；node_repl启用，cua_repl禁用；没有vivado/ross条目 |
| 工程MCP配置 | 当前及原工作区均无`.codex/config.toml`；App连接器另由应用管理 |
| 已有Ross安装 | PATH、用户下载目录、常见VS Code扩展目录及Codex配置未发现Windows Server/VSIX；未做全盘扫描 |
| 官方Server | 下载页列出2026.9.1 Windows独立exe；本会话未获得二进制，未安装/注册Ross |
| 实际阻塞 | 官方account.amd.com下载入口返回BIG-IP错误19，无法建立浏览器会话；不是已证实的Vivado版本不兼容 |
| 替代发布核查 | 官方GitHub release资产仅源码zip/tar.gz，未找到独立Server二进制替代下载 |
| 实测MCP工具/查询 | `not_measured`；没有运行Ross Server、打开checkpoint或通过MCP查询时序/资源 |

上述安装状态只覆盖列明的位置和配置，不据此声称机器任何位置都没有相关文件。
现有Tcl构建、RTL、XPR、XDC、IP、时钟、实现策略和旧报告保持不变。
没有修改全局MCP配置、启动未认证网络接口或开放公网端口。

官方来源：[AMD下载页](https://www.amd.com/en/support/downloads/ross-agentic-ai.html)、
[Ross FAQ](https://github.com/Xilinx/ross-ai-assistant/blob/2cdc9eef1b6b5b17fa45f5e4d468e5483a1c92de/docs/faq.md)、
[Codex接入步骤](https://github.com/Xilinx/ross-ai-assistant/blob/2cdc9eef1b6b5b17fa45f5e4d468e5483a1c92de/docs/getting-started/vivado-mcp.md)。
官方仓库审查提交为 `2cdc9eef1b6b5b17fa45f5e4d468e5483a1c92de`，MIT。
FAQ说明MCP以标准Tcl通信，2020.2及以后具有架构兼容性；完整测试基线为2026.1。
这不能替代在2025.2上的真实连接验证。

## Ross功能选择

| 功能/Skill | 版本与适用边界 | 本项目决定 |
|---|---|---|
| MCP start/execute/status、timing/utilization Tcl | 官方基础接口可作2025.2兼容性候选；本机未实测 | 获得官方二进制后，只读checkpoint副本试验 |
| vivado-simulate-rtl | SKILL明确验证2025.2和2026.1，依赖MCP/Python及相应模拟器 | 适合作为后续仿真候选，本次不安装/执行 |
| vivado-rtl-lint | 当前版本具有2026.1之前报告解析分支；不能一概认定只支持2026.1 | 待MCP与命令兼容验证；不重跑已有综合 |
| vivado-rtl-elaboration-analysis | 以已有Synth诊断和实际RTL为主，无明确最低版本 | 可参考日志分析方法，不能替代RTL功能证明 |
| vivado-revision-control | 无明确最低版本，包含导出/重建写操作 | 可参考；本次不替换已验证的恢复工程/Tcl入口 |
| vivado-timing-methodology-checks | SKILL明确Requires Vivado2026.1+ | 2025.2不按该Skill自动执行；保留已验证的Tcl报告流程 |
| vivado-ip-configurator | 要求2026.1、Vivado MCP和文档MCP | 本次不适用，不修改IP |
| hw-ila-debug / hw-vio-debug | 要求2026.1+、实际硬件及对应debug core | 板卡未知，不适用 |
| HLS / Vitis AI / segmented configuration | 分别面向HLS、NPU或其他器件流程 | 当前手写RTL、RV32和XC7Z020任务不需要 |

版本判断以各SKILL为准，不能仅看Ross整体版本。当前未安装Ross插件或独立Skills，避免无MCP时
误触发自动修改流程。[Skill目录](https://github.com/Xilinx/ross-ai-assistant/tree/2cdc9eef1b6b5b17fa45f5e4d468e5483a1c92de/skills)。

## 获得官方Server后的最小试验

先在浏览器完成AMD下载会话，取得官方Windows独立Server并核对发布校验信息；不再装VSIX。
按官方Codex CLI文档登记stdio Server，显式指定`VIVADO_PATH`为现有2025.2路径。
只允许list/start/execute/status等本次所需工具，排除cleanup、remote和硬件操作。
注意execute本身能写工程，工具名允许列表不能保证Tcl只读。

试验必须使用新的临时目录和routed checkpoint副本，不打开原XPR；启动时设置随机认证key，
保持`external=false`与loopback，不能照抄官方示例中的`key none`。先检查实际工具列表和
`version -short`，再执行`open_checkpoint`、`report_timing_summary`、`report_utilization`。
新结果仅写试验目录；按原报告的阶段和分析选项逐项核对WNS/TNS/资源，退出前不保存项目。
当前没有Server，因此上述步骤均是待验计划，不是PASS证据。

如新配置需要重新加载，退出当前Codex会话，重新打开桌面应用/新CLI会话，检查`/mcp`列表；
发现工具缺失或版本不支持即停止Ross试验。工程仍使用现有Tcl，不升级至2026.1。
[OpenAI MCP配置](https://developers.openai.com/codex/mcp)。

## Matt Pocock Skills

审查来源：[官方仓库](https://github.com/mattpocock/skills)、[作者说明](https://www.aihero.dev/skills)。
锁定 `49dd158d1076134a641b33efb035946536778336`，MIT；只安装以下四个目录，
没有安装完整插件、marketplace、hooks或执行第三方仓库脚本。

| Skill | 实际安装与权限/依赖审查 | 实际验证 |
|---|---|---|
| code-review | Markdown双轴审查；要求两个独立review agent、固定比较点及规范/需求来源 | 对origin/main...2b48a8a完成规范/需求两路只读审查 |
| diagnosing-bugs | 诊断/复现方法，含bash人工反馈模板；需日志脱敏，不能自动推定Windows脚本可用 | 文件和引用检查；未启动新的缺陷诊断流程/辅助脚本 |
| tdd | 公共接口的测试方法；接口待定时引用codebase-design，编写新测试前要求约定边界 | 文件和引用检查；未因此重构算法或新增大型测试 |
| pr | PR正文模板，无运行时二进制依赖 | 用于PR4的控制流、前后证据及合并风险说明 |

使用OpenAI自带Skill Installer，以固定提交选择`skills/engineering/{code-review,diagnosing-bugs,tdd,pr}`，
安装到`%USERPROFILE%/.codex/skills/`，未和插件重复加载。四个目录共12个文件与审查副本逐字节一致。
通过本机Codex新建stdio app-server调用`skills/list`：四个Skill均enabled=true、解析错误0；
没有发送模型turn或建立网络控制服务。当前聊天如尚未刷新目录，下一轮/重启Codex可使用。
[OpenAI Skills说明](https://developers.openai.com/codex/skills)。

通用Skill提供审查、调试和测试组织方法；HDL TestBench/独立黄金参考证明功能，Vivado STA/资源
报告证明指定约束下的物理实现，实际板卡测试证明板上行为。这四类证据不能互相替代。
TDD的“公共接口为主”不能取消本项目为证明ZEROIZE而检查内部敏感寄存器的必要白盒断言；
仓库安全与RTL规则优先。现有回归和冻结范围也优先于Skill中的通用重构建议。

## 有限审查与后续优先级

完整双轴结果见 [分支审查](ascon_branch_review.md)。需求轴0个新缺陷；规范轴发现1个P2证据门禁
问题，已以5个小型测试修复。它不改变密码学RTL或已有物理报告，原始实现快照完整且已核对。
安装和发现证据见`data/ascon/results/tool_evaluation/`。

板型/原理图/时钟/电气核验可立即推进；下一独立工程任务优先分析CPU/cache地址和hold使能路径，
再决定局部RTL时序改动。板型确定后完成板级约束、DRC/复位、UART与Ascon固件加载适配。
Strategy Sweep排在这些有依据的工作之后，仅在单独授权和资源预算下做有限比较；本次不执行。
