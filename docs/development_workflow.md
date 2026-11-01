# 开发与复现流程

2026-11-02：源码/历史源码、Skill、技术报告分开交付，当前入口为project_board.md；旧构建和研究工具位于archive/history。
本轮用户已授权提交/push，须先校验独立源码包；原始证据归档保留，不把新源码压缩当成新板测通过。

2026-10-29 更新：项目方改为 **11-01 提交并冻结**；旧日期作历史计划，不约束本轮。
现有功能保持可演示，额外稳定性/通用性与完整 clean-clone 未做就记未测，不自动等同交付失败。
当前实际验收与排期见 `tasks/release_plan_20261101.md`。

2026-11-01 补充：先按 [版本入口](version_entrypoints.md) 区分当前 PUF3、旧 v1、原 baseline 和独立实验。
PUF3 不等于“直接把 src/rtl 全加进工程”；旧程序的默认行为保留，不通过全局改 ID/路径制造版本统一。
说明层收口不重建候选、不回写历史数据；源码/工件变化仍需对应验证。

## 开工与分支

先读 AGENTS 和任务前置条件，运行 `git status --short`、`git branch --show-current`、`git log -5 --oneline`。保留未提交修改；不要用自动 pull/reset/clean 覆盖工作区。确需同步时在无冲突的隔离分支/工作树处理，不把参考仓库的强制同步脚本带入本项目。

| 分支 | 范围 |
|---|---|
| `feat/ascon-sw` | Cxx 标准软件 |
| `feat/ascon-ise` | Ixx 指令与 RTL |
| `feat/pynq` | Yxx 与通用 Skill |
| `feat/puf` / `feat/boot-auth` | 通过 P0/P1 门禁后才创建功能工作 |
| `docs/*` / `fix/*` | 文档与可验证修复 |

`main` 只接收有相应验证证据的变更。原 baseline 独立复现仍有缺口，不能据此否认当前 PUF3 已有实板。
`docs/repository-foundation` 与“原工程/RTL未变”是恢复阶段记录，不是当前分支/全仓现状；实际分支以 git 查询为准。

## 单个任务

1. 核对 prerequisite，owner 未分配写 TBD；确定本轮文件范围和接收任务。
2. 阅读/更新接口；重大选型写 decisions，禁止双方独立猜接口。
3. 在源文件或 Tcl/IP 配置上修改；临时构建放被忽略目录，精选证据复制至受控目录。
4. 运行与改动相称的验证，记录命令、退出码、版本和原始输出；RTL 必须配套功能验证。
5. 更新 task_board、actual_progress，失败写 lessons_learned；提交 review-ready diff 与验证局限。
6. **默认不执行commit/push，明确授权除外**。本轮11-02用户已授权，在校验后正常提交/推送，不force push。标题与正文按用户偏好写中文，列任务号、验证与边界。

## baseline 恢复顺序（B02/B03/B04）

1. 原baseline研究线已隔离在archive/history，原始来源/资产记录保留在archive/evidence；不要把旧恢复脚本当成当前PUF3构建入口。
2. 使用 `board/vivado_zynq7000_xc7z020_baseline/` 的真实 XPR/三个 XCI/XDC/COE，Vivado 2025.2 打开并重生成 IP；保留原 imports 快照。增量 DCP 依赖已最小移除，原 Kintex 工程保留。
3. B03 核验实际 XC7Z020 板卡、revision、时钟、复位、UART、DDR、引脚、电压和 image；在恢复的真实 XC7Z020 入口核验；若需适配其他板型再单独配置，不能只替换 part 字符串。
4. B04 核对已恢复 startup/linker/Makefile；按脚本隔离还原原文件名，取得精确 FreeRTOS kernel 与 bootloader 源，检查旧 TB 层次及扁平化链接，再验证内存布局与固件加载；程序入口与复位 PC/BRAM 映射一致。`RAM_INIT_FILE` 参数存在不代表加载链路已实现。
5. 运行基础 ISA、外设、中断、Cache/AXI 测试与 mcycle sanity，再综合/实现/上板；记录失败与 timing/resource 摘要。
6. 用 Tcl + 明确依赖在干净 checkout 重建，核对结果，形成可回归 baseline 标识后才批准 ISE 集成。

## 验收与证据存放

| 类型 | 位置 / 判定 |
|---|---|
| 构建入口 | 当前 PUF3：board 下专用 build.tcl + pynq_svc_puf/build.py；build/ 下旧实验脚本各有源快照，非统一入口 |
| Vivado 摘要 | `build/reports/` 中精选 synthesis/implementation/utilization/timing；原始 runs 不入库 |
| 复现元数据 | `build/metadata/`，版本/part/top/命令/source hash/IP 配置来源 |
| KAT / benchmark | `data/` 的版本化 JSON/CSV/文本及原始记录，不只截图 |
| 板级运行 | `board/`，固件/overlay 对应哈希和运行说明；大体积二进制由发布清单管理 |
| 验证代码 | `sim/`；波形是临时产物，结论和必要诊断摘要保留 |
| 报告与协作 | `report/`，可追溯图表、演示材料与用户批准范围/agent 自我纠错记录 |

D05 的完整验收必须在干净机器或干净 clone 实跑；检查源代码、IP、工具版本、固件、overlay、reference/KAT 均无本机绝对路径依赖，执行软件与 ISE KAT、benchmark、demo，形成完整日志和哈希清单。环境不可用只能记 blocked，不能算通过。原 11-02 日期已被 10-29 的 11-01 提交安排取代，D05 未测但不阻塞本次提交。

## generated 文件管理

`.gitignore` 不忽略整个 build，也不泛化忽略 CSV/JSON/Tcl/XDC/XCI/BD/COE/MEM。缓存、runs、临时 waveform 与私有工具目录忽略；需要留存的摘要先导出到 `build/reports/` 或 `data/`。foundation 收口已从索引/工作区移除原先跟踪的 `.cache/wt/project.wpc` 与 `.hw/*.lpr`；它们不属于 579 个恢复资产。ignore 本身不会清理已有跟踪项。

旧日期的原阶段门禁见 [历史milestones](../archive/history/tasks/milestones.md)，当前交付以根目录project_board.md为准。
