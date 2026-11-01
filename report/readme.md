# 报告与提交材料

## 当前交付（2026-11-02）

- 技术报告：[独立ZIP](../delivery/technical_report.zip)含当前PDF与可编辑LaTeX/图件；CPU措辞已去内部编号，数据保持PUF3。
- 海报：poster/中队友最新双语PPTX/PNG完整保留。
- 讲解网页：历史日志记录过project_explainer.html，但当前工作区、Git快照及整理备份均未找到该文件；不声称已入库或已清理其文本，需原制作会话补交原件。
- 工程源码与Skill分别压缩，见delivery/README.md；旧证据包不作附件，原始记录仍保存在archive/evidence。
- 下文带日期状态是整理前记录，旧llm_collab工具已隔离到archive/history/report，原始会话归档保存。

## 整理前的阶段说明（保留原语境）

更新：2026-11-01（10-29 初版）。

2026-11-01：D03 的可编辑 AMD 模板中英两页海报（含官方校徽）已完成，见 [poster/readme.md](poster/readme.md)、
[PPTX](poster/ascon_soc_poster.pptx)、[中文预览](poster/ascon_soc_poster.png) 与 [英文预览](poster/ascon_soc_poster_en.png)。学校/成员由用户确认，
周期表取原始 JSON；报告、视频和最终包不因海报完成而自动验收。

当前与旧入口按 `docs/version_entrypoints.md` 区分。视频脚本是PUF3，旧v1的9项错误门禁只能作标注的历史对照。
本轮只更新说明，程序/PDF/原数据/已发布包不变；当前包仍是18:38快照，新说明未自动装入该包。

- D03 最终报告：独立 LaTeX 工程 `docs/tech_report/amd_fpga_2026_latex_final/amd_fpga_2026_report/`，
  PDF 为 `output/pdf/final_report.pdf`（已入库；LaTeX 源与截图随证据包提供，不单独入库）。
  主演示为 PUF3 overlay，唯一板测主采样 `data/pynq_puf3/notebook_20261031_114512/result.json`。
  `docs/tech_report/report.md` 等旧 Markdown 报告流水线为旧 release 叙事，已被取代。
- D01 架构图随最终报告；`docs/architecture.md` 为早期架构说明。
- D02 性能表在最终报告表 1-1、表 3-13/3-14，数值由 `docs/tech_report/evidence/check_benchmark_tables.py`
  与报告自带 `review_evidence.py` 从原始 JSON/rpt 重算核对，不手填。
- PYNQ v1 release（`pynq-svc-v1`）的 benchmark 与 V03 错误/恢复门禁在 `data/pynq/notebook_20261031_112052/`、
  `data/pynq/error_gate_20261031_112812/`，在报告中只作历史对照，不代表 PUF3。
- D04 分镜与旁白脚本 `report/demo_video_script.md` 已按 PUF3 主演示更新；实机视频与最终哈希索引仍待录制和归档。
- 双语PPT海报已完成，见上方入口。V04冻结留档已于11-01 18:39生成（源码92159b9），但原宽范围验收未全关闭，不能把留档PASS写成“核心全部通过”。

按 10-29 授权，11-01 提交并冻结（原 11-02 D05、11-03 D06、11-04 提交的安排作废）。保留 source/工具/测量版本，
让图表可追溯；临时转换文件放 build/tmp。

2026-10-30：`llm_collab/` 已收录大模型协作原始记录。`python -X utf8 report/llm_collab/export_sessions.py`
从本机 OpenCode/Claude Code/Codex 会话库只读导出到 `llm_collab/sessions/`，索引与统计见 `llm_collab/index.md`；
报告正文引用其中的代表性案例。公开或提交前须人工复核隐私信息；队友设备上的会话需各自导出补充。

LLM 协作记录至少覆盖任务要求、读取依据、授权范围、输出文件、验证、自我纠错、未完成项和人工审核结论。本轮活动可由 project_log/development_log.md 追踪；不把摘要伪称完整聊天原始记录，正式提交前按核实后的比赛要求整理可分享记录。
