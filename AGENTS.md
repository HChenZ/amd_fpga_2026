# Agent 项目入口

项目：RISC-V Lightweight Cryptography SoC with ASCON ISE。复用 CICC1000023 CPU，目标 XC7Z020CLG400-1；P0 是标准 Ascon-AEAD128 软件与 ISE 的真实加速验证，P1 是 PYNQ 展示与通用 Skill，P2 才是 PUF/启动认证。截止日期 2026-11-04。

## 必读顺序

1. `AGENTS.md`
2. `README.md`
3. `docs/project_overview.md`
4. `docs/technical_rules.md`
5. `tasks/task_board.md`
6. `project_log/actual_progress.md`
7. `project_log/lessons_learned.md`

修改前再读 `docs/interfaces.md` 及相关目录的 `readme.md`；协作/交接读 `docs/agent_workflow.md`，构建读 `docs/repository_audit.md` 与 `docs/development_workflow.md`。

## 立即知道的事实

- CPU 在 `src/rtl/`，已有软件在 `ascon/`，原 Kintex 经 git mv 统一到 `board/vivado_kintex7_legacy/`；board 仅保留该 legacy 与真实 Zynq baseline 两个工程。
- 原 XPR 实际 part 为 `xc7k325tlffv676-2L`，不是目标 Zynq。这些资料在初始 Git HEAD 缺失（not_in_current_repo），现已从 ZIP 找到并选择恢复到独立 baseline/firmware/sim；不要继续表述为 not_available。
- 真实 XC7Z020 入口为 `board/vivado_zynq7000_xc7z020_baseline/`，三个 XCI/XDC/COE 与 imports 均已恢复；读 `docs/cicc1000023_recovery_audit.md`。不得从零创建空工程替代原始 baseline，也不凭换行差异选择哪个 RTL 更新。
- `csr_file.v:mcycle` 是周期来源；`cpi_cnt.v` 是事件计数，不能替代总周期。
- Ascon 软件存在不等于已符合最终标准；`ascon_round.v` 只有 `ror`，不能视为完成的 permutation/ISE。
- 所有 owner 先为 `TBD`；不要从 Git 作者、聊天身份或参考项目猜负责人。

## 行为规则

1. 用户明确授权的任务范围优先；进入任务先检查 `git status`，保留他人未提交改动。
2. 不猜比赛规则。查可追溯原文，记录链接、版本/日期；未核实内容标为待核实。
3. 不破坏 baseline。未经验证不移动 Vivado、不批量改 RTL 名、不删旧代码、不改变关键 IP/工程路径；新配置采用独立入口。
4. 不修改 generated files 来“修复问题”；修源配置或构建脚本后重新生成。foundation 收口已按用户要求删除两项已跟踪 .cache/.hw 元数据；后续不重新纳入生成缓存。
5. Vivado 修改必须记录 tool version、part、top、IP 版本、约束、命令和报告；打开旧工程时防止自动升级覆盖。
6. RTL 修改必须有对应验证；baseline 回归未过不能标为可集成。只 elaboration 不能宣称功能通过。
7. 每个 custom instruction 必须有 spec、encoding、semantics、RTL test、software test、最终标准 KAT、cycle benchmark；多周期/旁路/异常行为不能留空。
8. 第一期使用 inline assembly/intrinsic；不改 GCC backend。通过反汇编与执行证据确认软件确实调用 ISE。
9. 实测、仿真、综合/实现结果和估计分开，缺失项用 `not_measured`；不得伪造 benchmark、PPA 或完成状态。
10. 不自行 commit/push、force push、丢弃改动或强制同步。推荐分支和验收流程见开发流程；本轮停在可审查的工作区改动。
11. 完成任务必须更新 `project_log/actual_progress.md`，同步任务状态；失败、返工与踩坑记入 `project_log/lessons_learned.md`，有效活动记入 development_log。
12. 比赛新增普通目录/文件名用英文小写、数字、下划线或连字符，扩展名可用点；用户指定的 README.md、AGENTS.md 和 Git 配置文件名是例外。保留已有工程名称。
13. P0/P1 稳定且 10-21 门禁通过才评估 PUF；10-27 功能冻结、10-28 code freeze，11-04 只提交。

## 交付最小格式

任务号、改动文件、接口变化、验证命令/版本/退出码/证据、未验证内容、阻塞、下一接收任务。owner 未分配则写 TBD。当前阶段恢复真实比赛 baseline；不顺手开始大规模 Ascon、板卡迁移或编译器实现。
