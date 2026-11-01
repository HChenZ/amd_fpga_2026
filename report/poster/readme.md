# Ascon SoC poster

任务 D03，owner TBD，2026-11-01。本目录交付仿照用户指定 AMD 模板的一页横版、可编辑海报。

- `ascon_soc_poster.pptx`：正式 PPTX，960 × 540 pt，与源模板尺寸一致。
- `ascon_soc_poster.png`：PowerPoint 导出的 2400 × 1350 预览。
- `build_poster.ps1`：使用 Windows PowerPoint COM，在模板副本中修改；不会覆盖源模板。
- `verify_poster.py`：从原始 JSON 核对 KAT、周期、加速比、人员信息、可编辑表格和尺寸。
- `validation.json`、`text_fit.json`、`verification.json`：工具、源/产物哈希及检查结果。

学校与人员来自本轮用户：华南理工大学，熊雅琦、胡潇正、黄晨中。指导老师不填。
源模板内容仅作设计参考，示例学校、成员、无线电系统和黄色说明均不作为项目事实。
保留源模板 AMD 标识、三条分区线、三栏结构及黑白视觉；中文使用 Microsoft YaHei，英文辅助使用 Calibri。

## 数据来源

- 性能：`data/pynq/notebook_20261031_112052/pynq_warm_benchmark.json`，同次 run、KAT #529、PT=16 B、AD=0，预热 5 次，采样 30 次。
- 三模式各 289 组 KAT / 坏 Tag：同目录 `pynq_board_smoke.json`。
- 错误恢复：`data/pynq/error_gate_20261031_112812/pynq_board_error_gate.json`。
- 架构、ISE、资源与时序：`docs/tech_report/report.md` 及其中的原始报告摘录。
- Skill：`data/skill/l3_20261031_063709/40_summary.json`。
- 实物照片：`docs/tech_report/figs/board_photo.jpg`。

逐项出处与测量边界已写入 PPT 备注。周期为固件 AEAD 调用 `mcycle`，不含 PS/UART，不是 Python API 响应加速比。
100 MHz 为主线工程配置；主线独立频率与跨上电稳定性 `not_measured`。独立 PUF 结果不混入主线。
本次仅整理既有证据，未重跑硬件/RTL，也不代表 D03 报告、视频或整包全部完成。

## 重建与核验

需要 Windows、本机 Microsoft PowerPoint 16.0 和 Python 3（stdlib）。源模板由用户提供，未复制入仓库；哈希见 `validation.json`。

```powershell
./report/poster/build_poster.ps1 -TemplatePath 'F:\2026嵌入式大赛FPGA\海报\参考模板\AMD_poster_template.pptx'
python -X utf8 report/poster/verify_poster.py
```

本会话没有可调用的 `load_workspace_dependencies` 或 Artifact Session，因此采用本机 PowerPoint COM，未安装替代依赖。
已用 PowerPoint 导出并逐页检查；技能提供的 package integrity 与 layout geometry 检查均为 exit 0、0 finding。
未测试其他版本 Office、WPS、Google Slides 或印刷输出。重建需要用户原模板；核验既有 PPTX 不需要模板。
