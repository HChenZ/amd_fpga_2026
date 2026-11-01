# 当前提交候选入口

项目方安排：2026-11-01 提交并冻结。`current_evidence.json` 指向最近一次装配并校验的证据包及 ZIP 哈希。
`evidence/` 为此前生成的历史包，保留原样，不作为本轮最新版。

> **2026-11-01 状态**：最终报告已改为独立 LaTeX 工程
> `docs/tech_report/amd_fpga_2026_latex_final/amd_fpga_2026_report/`（PDF：`output/pdf/final_report.pdf`），
> 主演示为 PUF3，板测主采样 `data/pynq_puf3/notebook_20261031_114512/result.json`。
> 此前 `evidence_20261101_20261031_*` 三个包与 `freeze_manifest.*` 收录的是旧 `report.md`/`latex/main.pdf`
> 和 10-29/10-30 板测，**已作废**，仅作历史保留；报告定稿后按下方顺序重新装配与冻结。

Git 中只保存证据包目录。ZIP 和历史包 `evidence/` 不入库，只留在本机；`current_evidence.json`
里记录了 ZIP 哈希、报告构建记录、报告 PDF 哈希和板测主采样路径。

本目录的证据包包含最终报告（PDF + LaTeX 源 + 报告核对记录）、报告核对过的全部原件、原始测量和精选实现报告，
不是完整工程源码/全部比赛材料。

报告位置与板测来源统一在 `docs/tech_report/evidence/build_evidence.py` 顶部维护
（`REPORT_DIR`/`REPORT_PDF`/`BENCH`/`GATE`/`PUF3_RUN`）。装配门禁要求：报告最近一次构建
（`validation/build_*/summary.json`）为 PASS，当前 PDF、报告源与证据输入和该构建记录一致，
报告自带核对与 D02 均以 `PUF3_RUN` 为板测结果，报告引用的仓库文件全部存在并随包。

`freeze_manifest.md`/`.json` 是冻结留档（V04）：记录冻结源码提交、交付工件哈希与板测绑定、
证据包 ZIP 与报告 PDF 哈希、已知限制。完整源码包 `source_<commit>.zip` 由 `git archive` 生成，只含已跟踪文件，
不入库。报告定稿后的重新生成顺序：

```sh
# 1. 报告侧（队友）：重建并通过报告自带核对
python -X utf8 docs/tech_report/amd_fpga_2026_latex_final/amd_fpga_2026_report/build_review.py
# 2. 证据侧
python -X utf8 docs/tech_report/evidence/build_evidence.py          # C 组清单
python -X utf8 docs/tech_report/evidence/check_benchmark_tables.py  # D02，对最终报告
python -X utf8 docs/tech_report/evidence/assemble.py --check-only   # 只跑门禁，不写包
python -X utf8 docs/tech_report/evidence/assemble.py                # 证据包 + ZIP 自检
# 3. 提交报告工程、证据包目录与日志，使工作区干净
python -X utf8 docs/tech_report/evidence/freeze_manifest.py         # 冻结清单 + 源码包
```

PPT、视频、团队信息、平台附件要求与人工上传回执仍由项目方确认。
不要自动 commit/push 或上传；包内存在未实测项说明不表示其已经通过。
