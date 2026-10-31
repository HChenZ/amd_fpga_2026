# Skill validation raw results

本目录保存 Skill 验证的原始数据和结构化结果，不保存模拟输出冒充的实板数据。

PYNQ L3 Notebook 默认创建：

```text
data/skill/l3_<yyyyMMdd_HHmmss>/
data/skill/l3_current_session.json
```

每个通过项必须记录 `claim_level`，真实板结果使用 `hardware_measured`；未执行使用
`not_measured`，离线模型结果使用 `simulated`。结果目录同时保留执行后的 Notebook、
原始 JSON/日志和文件哈希。

`s04_report_dma_loopback/`：S04 报告采集的非 Ascon 示例输出（`report.md` + `report.json`，2026-10-31，离线生成）。
输入为 `board/vivado_zynq7000_xc7z020_axi_dma_loopback/candidate/reports/` 的 Vivado 报告与
`l3_20261031_063709/30_non_ascon_dma.json`；JSON 中记录各输入的绝对路径与 SHA-256。复现命令：

```powershell
python skill/pynq-overlay-workflow/scripts/pynq_skill_cli.py report `
  --schema skill/pynq-overlay-workflow/examples/report_schema.dma_loopback.json `
  --source util=board/vivado_zynq7000_xc7z020_axi_dma_loopback/candidate/reports/utilization.rpt `
  --source timing=board/vivado_zynq7000_xc7z020_axi_dma_loopback/candidate/reports/timing_summary.rpt `
  --source board=data/skill/l3_20261031_063709/30_non_ascon_dma.json `
  -o data/skill/s04_report_dma_loopback/report.md
```
