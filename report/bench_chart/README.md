# Ascon 性能对比图

本目录从 PUF3 实板 `result.json` 生成可编辑的 draw.io 页面，避免手工抄写性能数值。
视觉风格采用参考图的纯黑背景、深蓝分组框、白色文字和低饱和强调色。

## 生成

在仓库根目录运行：

```powershell
python -X utf8 report/bench_chart/generate_bench_chart.py
```

默认输入：

```text
data/pynq_puf3/notebook_20261031_114512/result.json
```

默认输出：

- `bench_chart.drawio`：可直接用 draw.io / diagrams.net 打开并继续修改。
- `bench_chart_preview.svg`：与 draw.io 页面同源的预览。
- `bench_chart_preview.png`：1920×1080 PNG 预览，便于快速查看或放入剪辑软件。

draw.io 页面和 SVG 画布均为 1920×1080，元素坐标、字号和间距按同一比例缩放。

指定其它实板结果：

```powershell
python -X utf8 report/bench_chart/generate_bench_chart.py `
  --result data/pynq_puf3/notebook_<时间>/result.json `
  --output report/bench_chart/bench_chart.drawio `
  --svg report/bench_chart/bench_chart_preview.svg
```

可选的 PNG 预览：

```powershell
rsvg-convert -w 1920 -h 1080 `
  -o report/bench_chart/bench_chart_preview.png `
  report/bench_chart/bench_chart_preview.svg
```

## 图中内容

- 加密、解密两个面板。
- SW、MMIO、ISE 三模式中位周期。
- MMIO/ISE 相对 SW 的加密、解密加速比。
- KAT #529、PT/AD 长度、warmup 和 repetitions。
- `RV32 固件 AEAD mcycle` 测量边界。
- 原始 result.json 路径。

脚本只读取结果并生成图形，不修改 `result.json`、RTL、固件或 Vivado 工程。
