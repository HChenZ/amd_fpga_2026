> 2026-11-02 代码块排版修复（当前版本，85 页；本次构建记录见 report/technical/validation/codeblock_layout_20261102/build_summary.json）：保持原字号，代码字距缩至 90%，减少框内左右留白；优先在空格自动换行，取消左右续行符号。命令和技术内容不变；校验记录见 report/technical/validation/codeblock_layout_20261102。历史构建说明保留。

# PUF3 最终演示报告核对稿

> 2026-11-02 再次更新（85 页，build_20261102_194053）：第四部分新增 §4.3「AMD ROSS 使用心得」（表 4-1，
> 内容整理自 archive/history/docs/ross_usage_experience.md、ross_and_engineering_skills_evaluation.md、
> timing_acb_validation.md 与 lessons L68/L85/L87/L88/L91/L93，不含新测量）；§2.5.1 加交叉引用，参考文献补第 11 条
> ross-ai-assistant。其余数值不变，review_evidence 194/194，无 Overfull/版心溢出。
> review_evidence.py 的“recorded RTL/firmware input”核对同样改为 LF/CRLF 双向等价（候选 hash 按 Windows CRLF 记录，
> Linux 检出为 LF），在 LF 整仓快照与 CRLF 工作区中均 194/194。

> 2026-11-02 晚间更新（83 页）：按用户审阅修图——图 2-1 去掉旋转标注白底并让 AXI/BRAM 竖线离开 soc_top 框线；
> 图 2-2 重新布线，连线不再穿过模块/流水寄存器、标注不压线；图 2-4 扇出与状态机改为水平/竖直正交走线，
> 汇聚线不再越过首路输出，握手虚线箭头不压文字；同类问题顺带修正图 2-3、2-7、2-9、2-13、2-14（旧 run_tests.py 标注）
> 与图 3-3（-0.118 标注压零线）。正文路径按 11-02 仓库结构更新（docs/ → report/、历史工程 → archive/history/、
> 原始记录 → archive/evidence/raw_records_20261102.zip），§3.4 复现说明重写为仓库结构、环境、离线验证判据、
> 构建、上板判据、交付包/报告复核与边界七节，并记录 11-02 干净检出离线复跑（build/metadata/offline_reproduce_check.json）。
> 图 2-10 前加 \Needspace{300pt}：图 2-10 若在页底浮动，会与随后的 longtable（重置 \@colroom）及浮动图 2-11
> 叠到同一页并溢出版心、截掉表 2-14 后三行。性能/资源/时序数值不变，review_evidence 194/194 通过。
> 独立 TikZ 预览须用 11pt 基础字号，否则 \scriptsize 标注宽度偏小、看不出压线。
> review_evidence.py 的 ISE 截图源文件核对改为 LF/CRLF 等价比较（干净检出因换行转换曾误报 3 项），记录 hash 不变；
> 主仓库与 864520d 干净检出恢复原件后均 194/194。最终构建 validation/build_20261102_191808。

> 2026-11-02 本轮更新：CPU架构描述去掉内部资产编号后已重新编译，性能/资源/时序数据不改。
> 当前PDF与LaTeX/图件由delivery/technical_report.zip单独交付，以其manifest为准；下文旧构建hash仅为当时记录。
> 不是新板测/新RTL实现，原始记录另在archive/evidence，第三方许可不删除。

> 2026-11-01 历史说明：当时 PDF 为 build_20261101_174743（603c625a…，77 页），曾收进当日 18:38 证据包。
> 该历史版本不是当前交付；当前 PDF 为 2026-11-02 代码块排版修复后的 85 页版本，SHA-256
> `c3a474d8d9a98d9e1a08034a47a6531ef8d6be72cf70c31ee87f1584a5ff0e0e`。
> 当前包及逐文件哈希看 `delivery/manifest.json` 与包内 `source_manifest.json`；旧证据包入口已归档至
> `archive/evidence/current_evidence.json`，版本职责见 `report/design/version_entrypoints.md`。
> 2026-11-03 仅修订本说明和外层 README，不重编 PDF，不增加硬件验证结论。

任务 D01/D02/D03；owner TBD；2026-10-31。输出为 `output/pdf/final_report.pdf`。

## 本稿维护入口

这是队友交付的独立 LaTeX 编辑稿：`chapters/*.tex`、`figs/*.tex` 为正文/图件维护源。
封面、页眉、字体、版心、五部分结构沿用交付稿；删除重复插图后第三部分图号顺延，表号不变。
不要用归档脚本 `archive/history/docs/tech_report/build_report.py` 覆盖本目录；归档 Markdown 报告是旧 release 叙事。
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
python -X utf8 report/technical/amd_fpga_2026_latex_final/amd_fpga_2026_report/build_review.py --tectonic <tectonic路径>
```

（2026-11-02 起目录由 `docs/tech_report/` 移至 `report/technical/`；先运行 `python tools/restore_records.py`
恢复 data/ascon/results、build/reports、build/local 下的归档原件，否则 review_evidence.py 找不到历史输入。）

依赖 Python、Tectonic、PyMuPDF、Pillow，以及 **DejaVu Sans Mono** 字体。
`preamble.tex` 指定该代码字体；缺少时会回退默认字体且未必报错，长命令可能重新折行，无法复现既有版式。
请在编译前安装并确认字体可被编译器找到。排版复核环境使用 DejaVu Sans Mono 2.37。先验证原件并生成 `evidence/*.tex`，在独立目录编译，
核对正文/PDF/原图像素与构建期间源哈希，成功后才替换指定 PDF。
验证日志、输入与产物哈希在 `validation/build_*/`；`mutation_check.json` 记录把表中 1369 改为 1370
的隔离反例确实被拒绝。所有核对都只复核已有证据，没有新硬件实验。

历史证据核对环境为 Python 3.13.9、Tectonic 0.15.0（仅描述当时复核）。当前 PDF 的代码块排版修复使用
Python 3.14.3、Tectonic 0.15.0；194/194、字体/版式与逐页文字校验记录见完整仓库中的
`report/technical/validation/codeblock_layout_20261102/`（build_summary.json、check.json、readme.md）。
独立 ZIP 不附完整 validation 记录，不能把上述历史验证当作解包后已重新运行；
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

截至 2026-11-03，报告修图/复现说明、AMD ROSS 心得、代码块排版修复与最终 RAR 装配均已有提交并推送；
不能再把 10-31 的“未创建合并提交、未 push”写成当前状态。历史 Git 操作以 Git 日志及 project_log 为准。

当前独立报告包为 `delivery/technical_report.zip`，版本、大小及 SHA-256 以 `delivery/manifest.json`
的该包条目和包内 `source_manifest.json` 为准。当前一体 RAR、前三个 ZIP、整仓快照各自有冻结版本，
不是独立报告包更新后自动同步的副本；本次只重打独立报告 ZIP，RAR 与整仓快照保留原字节及原清单。

D06 每次更新交付包后须重算并校验清单。归档的旧证据包不会自动收录新报告；本说明修正不等于完成平台上传、
重新上板、clean-clone 全链验证或原未测边界验收。下一接收 D03/D06，owner TBD。
