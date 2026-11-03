# 最后五阶段视频素材

本目录生成一个 1920×1080、纯黑背景、五页可编辑的 draw.io 文件：

1. `05`：PUF 注册、重建与 HWKEY
2. `06`：错误标签与拒绝语义
3. `07`：FPGA 实现、DRC/RO 和资源利用率
4. `08`：PYNQ Skill 与 L3 实板汇总
5. `09`：性能、PUF 输出与验证边界收束

## 生成

```powershell
python -X utf8 report/video_tail5/generate_tail5_storyboard.py
```

脚本读取：

```text
data/pynq_puf3/notebook_20261031_114512/result.json
C:\Nebula\HChenZ\2026 FPGA 创新设计赛道\视频素材
```

输出：

- `tail5_storyboard.drawio`：五页 draw.io 文件，图片以内嵌方式保存。
- `tail5_page_1.svg` 至 `tail5_page_5.svg`：逐页矢量预览。
- `tail5_page_1.png` 至 `tail5_page_5.png`：1920×1080 预览。
- `tail5_contact_sheet.png`：五页总览。

## 说明

- 页面使用纯黑背景、深蓝圆角面板、白色文字和低饱和金色/绿色强调。
- 页面不显示各分镜的起止时间。
- draw.io 内嵌的图片全部直接使用 `视频素材` 文件夹中的原始 PNG，不使用裁剪图或视频抽帧。
- PUF 安全字段按用户要求直接使用。
- `DRC.png` 用于展示 DRC 表；`DRC Error 0` 和 `Critical Warning 0` 的结论同时记录在
  `candidate/reports/gate.txt`。
- 收束页使用原始 `bench_chart.png` 与 `PUF  输出.png`。
