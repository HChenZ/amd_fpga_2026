# 报告与提交材料

2026-11-01：D03 的可编辑 AMD 模板海报已完成，见 [poster/readme.md](poster/readme.md)、
[PPTX](poster/ascon_soc_poster.pptx) 与 [预览](poster/ascon_soc_poster.png)。学校/成员由用户确认，
周期表取原始 JSON；报告、视频和最终包不因海报完成而自动验收。下文为历史状态。

更新：2026-10-29。当前仍只预留正式报告目录，但原始证据已齐备：

- D01 架构初稿在 `docs/architecture.md`，PYNQ 实板拓扑已补充，报告定稿未完成。
- D02 性能表尚未生成；应直接引用
  `data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json`，不得手填。
- V03 错误/恢复证据在 `data/pynq/error_gate_20261029_134023/`。
- D03 报告/PPT/LLM 协作记录仍待完成；D04 分镜与旁白脚本
  `report/demo_video_script.md` 已完成，实机视频与最终哈希索引仍待录制和归档。
- V04 当前 blocked，完成前不能把材料写成“核心冻结验收全部通过”。

10-29～11-01 整理材料，11-02 D05 干净复现，11-03 D06 只修材料，11-04 正式提交。保留 source/工具/测量版本，让图表可追溯；临时转换文件放 build/tmp。

2026-10-30：`llm_collab/` 已收录大模型协作原始记录。`python -X utf8 report/llm_collab/export_sessions.py`
从本机 OpenCode/Claude Code/Codex 会话库只读导出到 `llm_collab/sessions/`，索引与统计见 `llm_collab/index.md`；
报告正文的 2.4 节引用其中的代表性案例。公开或提交前须人工复核隐私信息；队友设备上的会话需各自导出补充。

LLM 协作记录至少覆盖任务要求、读取依据、授权范围、输出文件、验证、自我纠错、未完成项和人工审核结论。本轮活动可由 project_log/development_log.md 追踪；不把摘要伪称完整聊天原始记录，正式提交前按核实后的比赛要求整理可分享记录。
