# PUF3 最终演示报告核对稿

任务 D01/D02/D03；owner TBD；2026-10-31。输出为 `output/pdf/final_report.pdf`。

## 本稿维护入口

这是队友交付的独立 LaTeX 编辑稿：`chapters/*.tex`、`figs/*.tex` 为正文/图件维护源。
封面、页眉、字体、版心、五部分结构沿用交付稿；删除重复插图后第三部分图号顺延，表号不变。
不要用上层 `docs/tech_report/build_report.py` 覆盖本目录；上层 Markdown 报告仍是旧 release 叙事。
原始 `amd_fpga_2026_latex_final.zip` 保留；本轮修改前副本位于仓库本机
`build/local/report_puf3_review/before_review.zip`。

## 核实后的主数据

唯一主采样：`data/pynq_puf3/notebook_20261031_114512/result.json`。
其 bit/hwh/manifest 哈希与 `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/` 一致。

| 项目 | SW | HW/MMIO | ISE |
|---|---:|---:|---:|
| 加密周期中位 | 21862 | 1369 | 3895 |
| 解密周期中位 | 22562 | 1213 | 4288 |
| 加密周期加速比 | 1.000 | 15.969 | 5.613 |
| 解密周期加速比 | 1.000 | 18.600 | 5.262 |
| 加密 PS 墙钟中位 ms | 5.130 | 4.403 | 4.385 |
| 解密 PS 墙钟中位 ms | 4.874 | 4.160 | 4.137 |

KAT #529、PT16/AD0、HWKEY 关闭、预热 5 次、每档 30 次；周期不含 PS/UART，也不含响应后的
rxbuf/txbuf 擦除。周期原始数组可复算；墙钟只有 summary，不能宣称保存了墙钟原始数组。

- 三模式各 289 个容量内 KAT/正确解密及 289 次坏 Tag 拒绝；不是 529 组。
- 控制 ID PQF3=`0x33465150`，固件 `pynq-svc-puf3`；22 条静态 custom-0 编码。
- 工件 `pynq_puf3.bit` 4045693 B / `pynq_puf3.hwh` 158472 B。
- Vivado 2025.2 / `pynq_puf3_wrapper` / `xc7z020clg400-1`；LUT 18674、FF 32002、BRAM 34.5、DSP 4。
- 已约束路径 WNS +0.104 / TNS 0 / WHS +0.041 / THS 0；0/73907 失败端点。
- DRC 0 Error/0 Critical；报告列 824 Warning；methodology 另有 TIMING-17 Critical 1000 条。
- RO 计数器域未签核：5120 无时钟引脚、15360 未约束最大延迟引脚、256 组合环；Slow/Fast 角均有负 slack。
- HWH/SLCR 推导 99.999999 MHz；10-31 mcycle/PS 时基估测 99.9723 MHz，非 Fmax/示波器测量；PYNQ 显示 150 不是真实频率。
- PUF quality=127/128、连续 5 次会话内重建、HWKEY 开关/官方 KAT 恢复通过；跨上电/PVT/BER/熵/唯一性未测。

## 重点更正与队友复查点

1. 摘要、表 1-1/2-9/3-13/3-14、图中数字、资源、时序、身份、构建/上板命令统一到 PUF3。
2. 真实 Block Design 放在图 2-10；Implemented Design 仅放在图 2-11，资源章节交叉引用。
   后补 Utilization 和 Wave 分别放在图 3-2、3-5。四张 PNG 原字节保存，自动核对 PDF 内像素相同且各出现一次。
3. 表 2-16 的全长度周期统计保留为 **旧 release 历史对照**：PUF3 没有归档逐 KAT 周期，不能套用。
4. 9/9 错误恢复、7 次 reset、每模式 50 次往返属于旧 `pynq-svc-v1`，不算 PUF3 通过。
5. HW 驱动没有发硬件 ZEROIZE；正文已区分“RTL 支持”“软件缓冲擦除”和“每调用硬件清零”。
   该处只修报告，不更改 RTL/固件或现有测量。
6. 更新 HWKEY 选择、key_mmio 偏移、Y01P/Y01K（末 8 B 为发送时刻 mcycle）与 PUF 可观测性边界。
7. 附录 C 由当前原件重新生成；最新 Skill 离线为 64 项/16 个变异，L2/L3 对应较早版本。
8. 芯片完整丝印、小时级稳定性、完整 ISA/RV64/异常矩阵、clean-clone 等原有边界保留。

## 构建与验证

在完整仓库中执行（从仓库根）：

```powershell
python -X utf8 docs/tech_report/amd_fpga_2026_latex_final/amd_fpga_2026_report/build_review.py --tectonic C:/wenjian/toolchain/tectonic/tectonic.exe
```

依赖 Python、Tectonic、PyMuPDF、Pillow。先验证原件并生成 `evidence/*.tex`，在独立目录编译，
核对正文/PDF/原图像素与构建期间源哈希，成功后才替换指定 PDF。
验证日志、输入与产物哈希在 `validation/build_*/`；`mutation_check.json` 记录把表中 1369 改为 1370
的隔离反例确实被拒绝。所有核对都只复核已有证据，没有新硬件实验。

本轮验证：Python 3.13.9、Tectonic 0.15.0；证据/正文/PDF 核对通过（结果见 validation/evidence_check.json）；
PDF 原图像素核对通过；无未解析引用、缺字或 Overfull；页边界扫描和关键页人工视觉复核完成。

插图排版（`preamble.tex` 的 `\placefigure`）：按当前页剩余空间放图，放得下就原位；差一点就等比缩小
（不小于 62%）留在本页；仍放不下才浮到下一页顶部，本页由后文补满；已有待排图时后续图一并浮动以保持顺序。
编译日志中的 `FIGPLACE` 行记录每张图的决定。longtable 跨页处已补放置待排浮动图的步骤；标题后紧跟长表时用
`\Needspace{150pt}`。不要再加 `[H]` 或 `\FloatBarrier`，否则会重新出现图与正文之间的大片空白。

独立 LaTeX 包已包含 `evidence/*.tex`；可用原 `build.ps1`（latexmk + XeLaTeX）或 Overleaf/XeLaTeX 编译。
**独立包编译不等于重新核验仓库证据**；`review_evidence.py` 的原件核对需要完整仓库及相关历史本地报告。

## 已补齐的工程截图

- 图 3-2：已加入用户的 `Report Utilization.png`（保存为 `figs/vivado_utilization.png`），
  top、LUT 18674、FF 32002、BRAM 34.5、DSP 4 与原始报告一致。
  打开 `build/local/pynq_puf3/vivado/pynq_puf3.xpr` → Open Implemented Design → Reports → Report Utilization。
  原始报告为 `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/reports/utilization.rpt`。
- 图 3-5：已加入用户的 `Wave.png`（保存为 `figs/vivado_ise_waveform.png`）。
  当前工程已配置 `sim_ise_screenshot`，原 tb_key_ise 实际运行 1502 检查/0 错误，37390 ns finish；
  新日志在 `data/ascon/results/ise_screenshot_20261031/`，WDB/VCD 在 `build/local/pynq_puf3/ise_screenshot/`。
  图片显示 P8 start=380 ns、done=495 ns，ack=760 ns 在所示窗口外；不宣称截图展示了完整 P12/取消序列。
  Objects 1502/0 为仿真末态，Wave Value 是 150 ns 光标值。控制台红字是此前 `get_waves` 缺 patterns
  参数的查询错误，原图保留，并在图注解释其与 TB 自检结果的区别。
- 现场取证可补芯片完整丝印、板背面/跳线/SD 镜像信息。已有实物正面照片保留。

本稿四个工程截图位置均已补齐，无对应缺图占位；后续替换图片仍须更新哈希并重新编译。

## Git 与最终包

按用户要求 fetch 并以 `merge --no-commit --no-ff origin/main` 纳入远端 `c385a9d`；
本地 3 个未推送提交保留。actual_progress 顶部冲突已同时保留双方条目并标记解决；未创建合并提交、未 push。
本轮状态是可审查工作区，不是已完成 Git 合并提交。

`submission/current_evidence.json` 指向的旧证据包/冻结清单不会因本 PDF 重建而自动更新。
D03 队友终审后，D06 需要按新报告与 10-31 数据更新装配入口、重新核包和冻结，不能继续声称旧 ZIP 含本稿。
