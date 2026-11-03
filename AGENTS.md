# Agent 项目入口

## 2026-11-02 本轮最新交付授权

- 用户明确要求：当前PUF3与必需依赖、隔离历史源码分别压缩，另提供独立Skill和技术报告；不以旧证据包作为交付附件。
- 仓库仍保留原始记录（archive/evidence）和历史源码（archive/history），从project_board.md快速导航。
- 当前RTL/固件算法和已验证candidate保持不变；对外CPU描述只写RV32五级流水线结构，去掉内部编号，不改第三方版权/许可和原始记录。
- 原始档案中保留的旧标识与Git历史不伪造清除；当前维护源码/网页/报告和交付文件名另行扫描。
- 本轮用户已明确授权提交并push；不得force push或丢弃队友改动。原下文日期/入口描述按其历史时点解读。
- 11-02 按赛题 3.3.5.4 推荐结构，原顶层 `docs/` 并入 `report/`：`docs/tech_report/` → `report/technical/`，其余说明 → `report/design/`，复现指南 → `report/reproduce_from_zero.md`；大模型协作记录 `report/llm_collab/`（含会话原文）入库。目录对照见 README.md；project_log 与原始记录中的旧 `docs/` 路径按历史时点解读。

## 当前交付安排（2026-10-29 用户最新授权，优先于下文历史计划）

- **2026-11-01 提交并冻结**，取代原 10-27/10-28 冻结与 11-04 提交安排；这是项目方安排，不推断官方赛期。
- 主线为 RV32/PYNQ 短消息 SW/MMIO/ISE。**2026-11-01 更新**：最终报告
  （`report/technical/amd_fpga_2026_latex_final/`）以 PUF3 overlay（三模式 + RO-PUF/DNA 密钥通路同一 bit，
  板测 `data/pynq_puf3/notebook_20261031_114512/`）为主演示，PYNQ v1 release 作历史对照；PUF 部分仅有会话内
  功能证据，跨上电/RO 时序签核等未测边界必须保留。
- 10-30 队友先验证实际交付 Skill；小时级稳定性、完整通用性/跨平台与独立核/大消息实验不阻塞本次提交。
- 原始失败与未测边界保留；不能因缩减交付范围把未完成任务改为通过。现有代码/证据不删除，不自动 commit/push。
- 当前交付先看 `project_board.md`；原阶段顺序见 `tasks/release_plan_20261101.md`，历史Skill执行表位于 `archive/history/docs/skill_test_guide_20261030.md`。
- 版本选择先读 `report/design/version_entrypoints.md`：保留旧入口的默认行为与历史证据，不把 v1 CLI、Skill L3 或独立 DMA/PUF v2 结果改写为 PUF3 结果；本轮说明收口不授权修改 PUF3/公共 RTL。

项目：RISC-V Lightweight Cryptography SoC with ASCON ISE。CPU 采用 RV32 五级流水线结构，目标 XC7Z020CLG400-1；主线是标准 Ascon-AEAD128 软件、ISE 与 MMIO 加速及 PYNQ 展示，主演示为集成 PUF 密钥通路的 PUF3 overlay。历史项目集中在 archive/history，原始证据保留在 archive/evidence。

## 必读顺序

1. `AGENTS.md`
2. `README.md`
3. `report/design/project_overview.md`
4. `report/design/technical_rules.md`
5. `tasks/task_board.md`
6. `project_log/actual_progress.md`
7. `project_log/lessons_learned.md`

修改前再读 `report/design/interfaces.md` 及相关目录的 `readme.md`；协作/交接读 `report/design/agent_workflow.md`，构建读 `report/design/repository_audit.md` 与 `report/design/development_workflow.md`。

## 立即知道的事实

- CPU在src/rtl，算法在ascon；独立旧工程已隔离到archive/history/board。当前board仅保留PUF3、其共享IP配置来源和板卡资料，职责见board/readme.md。
- 原 XPR 实际 part 为 `xc7k325tlffv676-2L`，不是目标 Zynq。这些资料在初始 Git HEAD 缺失（not_in_current_repo），现已从 ZIP 找到并选择恢复到独立 baseline/firmware/sim；不要继续表述为 not_available。
- 原始 XC7Z020 baseline 已隔离到 archive/history/board；它不是当前 PUF3 演示入口。原件与来源保留，不凭换行差异选择哪个 RTL 更新，不改第三方版权/许可。
- `csr_file.v:mcycle` 是周期来源；`cpi_cnt.v` 是事件计数，不能替代总周期。
- Ascon 软件存在不等于符合最终标准，须看锁定 KAT。初始快照“ascon_round.v 只有 ror”已过时：当前含 round，P8/P12/ISE 与容量内板测已有证据；模块存在仍不能替代对应版本的验证。
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
13. 当前按上方 2026-10-29 授权执行：11-01 提交并冻结；新增实验不阻塞已定义交付。11-01 起最终报告主演示为 PUF3 overlay（见上），PYNQ v1 release 及其 9/9 错误门禁只作历史对照，不得记为 PUF3 通过项。

## 交付最小格式

任务号、改动文件、接口变化、验证命令/版本/退出码/证据、未验证内容、阻塞、下一接收任务。owner 未分配则写 TBD。原 baseline 独立复现是遗留研究线；当前为 PUF3 提交/文档收口，不顺手开始大规模 Ascon、板卡迁移或编译器实现。
