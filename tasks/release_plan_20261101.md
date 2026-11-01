# 11-01 提交计划与实际进度

> 2026-11-02 最新交付安排：工程当前/历史源码隔离并分别压缩，独立Skill与技术报告另包；
> 原始证据留仓库归档，不提交旧证据包附件。入口project_board.md、delivery/README.md；下方旧装配计划保留当时语境。

更新 2026-11-01（初版 10-29）；owner 全为 TBD，由项目方分配。日期来源为本轮用户确认，不是官方规则推断。

11-01 口径变更：最终报告（`docs/tech_report/amd_fpga_2026_latex_final/`）以 **PUF3 overlay 为主演示**，
板测一律采用 10-31 最新一版；PYNQ v1 release（`pynq-svc-v1`）在报告中作历史对照。下表按此更新。

说明层收口见 `docs/version_entrypoints.md`：当前与旧入口明确分责，程序默认行为不改；原始结果、已执行 Notebook、
candidate/PDF/包内快照保留字节。下表“当前文档”不意味着这些说明已写回历史包。

## 已经实现的工程

| 层 | 当前成果 | 证据与限制 |
|---|---|---|
| RV32 + Ascon | SW/MMIO/ISE 已实现，真实 CPU 与板级运行 | 不称完整 ISA 合规；历史 ma_data 失败保留 |
| PUF3 overlay（主演示） | 三模式+PUF v1 单 bit（ID `PQF3`，固件 `pynq-svc-puf3`）；10-31 实板 PASS：三模式各 289/289 KAT 与坏 Tag 拒绝；#529 各档 30 次 enc 21862/1369/3895（HW 15.969×、ISE 5.613×），dec 22562/1213/4288（18.600×、5.262×）；mcycle 估测 99.9723 MHz；quality 127、会话内重建 5/5 | `data/pynq_puf3/notebook_20261031_114512/`；LUT18674/FF32002/BRAM34.5/DSP4，已约束路径 WNS+0.104；RO 计数器域未签核、跨上电 not_measured、REF/MASK/RAW/DNA 可读；墙钟只有 summary；PUF3 未跑完整错误门禁 |
| PYNQ v1 release（历史对照） | overlay/API/Notebook，PT/AD 各 ≤16B；10-31 重测 #529：enc 23342/1439/3995，dec 24005/1388/4385；错误门禁 9/9、7/7 reset | `data/pynq/notebook_20261031_112052/`、`error_gate_20261031_112812/`；WNS+0.034，LUT14269/FF19691；门禁结果属 pynq-svc-v1，不代表 PUF3 |
| 独立 PUF 原型 | 256 RO、DNA、P12 派生、MMIO，v3 quality128/128，重建状态通过 | 早期独立工程；调试输入可读，未证明保密隔离；RO 时序未全闭合 |
| Skill | `skill/pynq-overlay-workflow`：最新已归档 L1 离线 64 passed、变异16/16；L2 60+5 次受控实验（simulated）；L3 实板 preflight/Ascon/GPIO/DMA 全 PASS | `data/skill/l3_20261031_063709/`；L3 Ascon 对象为旧 PYNQ v1，不是 PUF3；with vs placebo 不显著、留出任务未复现；后续 S04/gen 修复仅离线；DMA 吞吐未测 |

## 提交前执行表

状态更新于 2026-11-01。

| 顺序 | 工作 | 完成标准 | 建议时间 | 状态（11-01） |
|---|---|---|---|---|
| 1 | 统一报告与简介 | 当前/历史指标不混用，PUF 按原型表述，旧 CRC/重传等错误移除 | 10-29 晚 | 报告/简介数据已对齐；后续版本审计发现目录说明仍有旧状态，本轮补齐当前/旧入口范围与历史提示，不改变各程序默认行为；旧 Markdown 报告流水线不用作最终稿 |
| 2 | 实际 Skill 最小测试 | 确认提交哪一个 Skill，至少一项完整任务运行与可复查结果 | 10-30 上午 | 完成：提交 `pynq-overlay-workflow`，L1–L3 证据见上表 |
| 3 | 演示复验 | hash 配套，Notebook/CLI smoke 真实 PASS，保存 log/JSON | 10-30 | 完成：PUF3 10-31 Notebook；PYNQ v1 10-31 Notebook/错误门禁；Skill L3 10-31 |
| 4 | 视频/PPT/照片 | 当前三模式演示；独立原型用单独日志/镜像，不假装同一 overlay | 10-30/31 | 部分：视频脚本 `report/demo_video_script.md` 已完成（主版+3 分钟版），11-01 已按 PUF3 主演示与 10-31 数据重写；实机视频未录、PPT 未见 |
| 5 | 交付包检查 | PDF/源码/图/证据/依赖/许可/操作入口齐，干净解包哈希正确 | 10-31 | 当前冻结包为 18:38 的267文件版本（current_evidence.json），PDF build_20261101_174743/603c625a…；D02 64/64、报告194/194；18:39已生成冻结清单（源码92159b9）与源码包。之后版本复核/说明更新未写回旧包；需要新快照时再核对/装配。旧包保留不改，平台附件要求待核 |
| 6 | 人工确认与提交 | 团队信息、平台要求、文件大小/命名、上传成功回执 | 11-01 | 待办 |

必要修复可在提交前进行，但不为宣传数字修改已测样本；代码变化须验证，新 bit/固件须重新绑定证据。
本轮无需实现 DMA、多块硬件或独立核 PPA。稳定性与额外通用性可后续开展，不阻塞提交。

## Skill 的范围决策

10-31 决策更新：提交的 Skill 为 `skill/pynq-overlay-workflow/`（说明见 `skill/readme.md`），
其 loader/register/golden/report collector 已实现并按 S01–S05 验收（看板 done）。
`skill/rtl-design-discipline/SKILL.md` 保留为工程辅助 Skill，不作为主交付。
（10-29 原文：当时通用 PYNQ loader 等未实现，建议先交 RTL discipline；该前提已不成立。）

完整原 baseline、RV64、异常矩阵与 clean-clone 仍是未验收研发项；它们不因本轮范围调整变为已完成。
