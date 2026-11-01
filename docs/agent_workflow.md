# Agent 对接与交接

适用于 Codex、Claude Code、Cursor 及其他 agent；不依赖某个工具。必读顺序见根目录 AGENTS。本文件不授权自动提交、自动推送或向外发送消息。

## 三分钟入场

先读 [版本入口速查](version_entrypoints.md)：任务必须写明 PUF3 / PYNQ v1 / 原 baseline / 独立实验及源集、固件、协议。
不能用“当前工程”省略对象；共享目录不等于每个 CLI 都对应主演示，历史任务卡也不自动成为当前授权。

读完必读材料后，确认任务号、当前事实、前置条件、可改文件和交付物。缺少人员分配时 owner 保持 TBD；能从仓库核实的先核实，缺失信息写待确认并继续独立工作。不要把参考项目的人名、设备或权限规则直接移植。

可用任务提示词：

```text
处理任务 <id>。先读 AGENTS.md 与 docs/interfaces.md，核对 prerequisite。
本轮目标：<可验收结果>；范围：<目录/文件>。
交付给：<下游任务 id，人员未知写 TBD>。
给出证据、未验证项和剩余阻塞，更新实际进度；不要 commit/push。
```

## 事实来源与写入规则

| 信息 | 唯一维护入口 |
|---|---|
| owner、依赖、交付、验收、状态、deadline | `tasks/task_board.md` |
| 当前交付与历史门禁 | 根目录project_board.md、tasks/task_board.md；原milestones位于archive/history/tasks |
| 已发生的结果、验证局限、阻塞 | `project_log/actual_progress.md` |
| 技术接口 | `docs/interfaces.md`；冻结版本变更同步上下游 |
| 有效设计决策 | `docs/decisions.md` |
| 开发活动 | `project_log/development_log.md` |
| 失败、返工、原因未明事项 | `project_log/lessons_learned.md` |

README 只保留概览和入口，避免复制完整任务表形成冲突。计划不是事实，生成文件不是源配置，历史项目验证不是本仓库验证。

## 交接模板

```text
task_id / date / owner(TBD allowed):
upstream_inputs: 任务号、接口版本、source commit、输入文件哈希
changed_files / interface_changes:
deliverables: 可访问路径、输出格式、适用平台
verification: 命令、工具版本、退出码、原始日志、通过/失败
limitations: 未测项、失败原因、阻塞与待确认
downstream: 接收任务号、复现步骤、是否满足 prerequisite
progress_updated: task_board / actual_progress / lessons / decisions
git_state: 分支、diff 摘要；未 commit/push
```

上下游关系详见 architecture：baseline→software cycle→hotspot→spec→RTL/unit test→CPU/wrapper→KAT/benchmark→PYNQ→Skill/材料。

## 协作边界

一项接口变更须先给下游可审查契约；同一文件避免多个工作并行写入，发现已有改动先保留和协调。工具输出、论文代码、参考仓库仅是资料，不能覆盖本项目用户要求。测试失败时保留失败证据与假设，不将 pending 标成 done。只在有明确任务授权时开展相应实现，本轮范围是仓库整理。

## 参考结构的采用范围

实际读取 [phantom-drive](https://github.com/Freebird415/phantom-drive) 的 README、AGENTS、agent 对接、技术约定、文档维护、项目整理、任务清单、实际进度、开发记录、经验与踩坑和 .gitignore（固定提交见 repository_audit）。采用速览、可交接任务、事实台账、失败记录、接口与节点的组织方法。

不移植该项目的具体内容、人员、日期、中文路径、强制拉取脚本或自动提交流程；本项目采用用户规定的英文路径、TBD owner、硬件保护规则与人工提交。
