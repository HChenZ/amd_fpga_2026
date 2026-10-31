# 11-01 提交计划与实际进度

更新 2026-10-31（初版 10-29）；owner 全为 TBD，由项目方分配。日期来源为本轮用户确认，不是官方规则推断。

## 已经实现的工程

| 层 | 当前成果 | 证据与限制 |
|---|---|---|
| RV32 + Ascon | SW/MMIO/ISE 已实现，真实 CPU 与板级运行 | 不称完整 ISA 合规；历史 ma_data 失败保留 |
| PYNQ 主线 | overlay/API/Notebook，PT/AD 各 ≤16B | 三模式各 289 KAT/坏 Tag 拒绝；非 1089 板测 |
| 性能 | #529 各档 30 次：enc 23342/1439/3995，dec 24005/1388/4385 | CPU 周期与 PS 4.262–5.216 ms 分列 |
| 恢复 | 9/9 checks、7/7 reset、每模式 50 次加解密往返 | 不代替小时级或断电稳定性 |
| 当前实现 | Vivado2025.2，pynq_wrapper，WNS+0.034；LUT14269/FF19691/BRAM34.5/DSP4 | DRC0 Error/0 Critical，Warning 非零 |
| 独立 PUF 原型 | 256 RO、DNA、P12 派生、MMIO，v3 quality128/128，重建状态通过 | 非当前 PYNQ；调试输入可读，未证明保密隔离；RO 时序未全闭合 |
| pynq_puf3 扩展 overlay | 三模式+PUF v1 单 bit（ID `PQF3`），实板 Notebook PASS：三模式各 289/289 KAT 与坏 Tag 拒绝；FCLK0 实测 99.997 MHz；enroll quality 127、会话内重建 5/5 | `data/pynq_puf3/notebook_20261030_144328/`；跨上电 not_measured、RO 域时序未签核、REF/MASK/RAW/DNA 可读；不替代主线 release |
| Skill | `skill/pynq-overlay-workflow`：L1 离线 63 passed；L2 60+5 次受控实验（simulated）；L3 实板 preflight/Ascon/GPIO/DMA 全 PASS | `data/skill/l3_20261031_063709/`；with vs placebo 不显著、留出任务未复现；L3 验证版本 7bc1abf，S04 后续新增仅离线；DMA 吞吐未测 |

## 提交前执行表

状态更新于 2026-10-31。

| 顺序 | 工作 | 完成标准 | 建议时间 | 状态（10-31） |
|---|---|---|---|---|
| 1 | 统一报告与简介 | 当前/历史指标不混用，PUF 按原型表述，旧 CRC/重传等错误移除 | 10-29 晚 | 队友更新报告中；终稿后须重建 PDF 并重新装配证据包 |
| 2 | 实际 Skill 最小测试 | 确认提交哪一个 Skill，至少一项完整任务运行与可复查结果 | 10-30 上午 | 完成：提交 `pynq-overlay-workflow`，L1–L3 证据见上表 |
| 3 | 演示复验 | hash 配套，Notebook/CLI smoke 真实 PASS，保存 log/JSON | 10-30 | 完成：主线 10-29 Notebook/错误门禁；pynq_puf3 10-30 Notebook；Skill L3 10-31 |
| 4 | 视频/PPT/照片 | 当前三模式演示；独立原型用单独日志/镜像，不假装同一 overlay | 10-30/31 | 部分：视频脚本 `report/demo_video_script.md` 已完成（主版+3 分钟版）；实机视频未录、PPT 未见 |
| 5 | 交付包检查 | PDF/源码/图/证据/依赖/许可/操作入口齐，干净解包哈希正确 | 10-31 | 部分：证据包 10-31 重新装配（含 X-1～X-8），见 `submission/current_evidence.json`；D02 数值核对 15/15；冻结清单与本机源码包（git archive）见 `submission/freeze_manifest.md`；报告终稿后需重跑核对与装配；平台对源码/附件的要求待核 |
| 6 | 人工确认与提交 | 团队信息、平台要求、文件大小/命名、上传成功回执 | 11-01 | 待办 |

必要修复可在提交前进行，但不为宣传数字修改已测样本；代码变化须验证，新 bit/固件须重新绑定证据。
本轮无需实现 DMA、多块硬件或独立核 PPA。稳定性与额外通用性可后续开展，不阻塞提交。

## Skill 的范围决策

10-31 决策更新：提交的 Skill 为 `skill/pynq-overlay-workflow/`（说明见 `skill/readme.md`），
其 loader/register/golden/report collector 已实现并按 S01–S05 验收（看板 done）。
`skill/rtl-design-discipline/SKILL.md` 保留为工程辅助 Skill，不作为主交付。
（10-29 原文：当时通用 PYNQ loader 等未实现，建议先交 RTL discipline；该前提已不成立。）

完整原 baseline、RV64、异常矩阵与 clean-clone 仍是未验收研发项；它们不因本轮范围调整变为已完成。
