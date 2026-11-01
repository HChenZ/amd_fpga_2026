# 当前报告证据包：版本与执行顺序

更新：2026-11-01。本目录程序不改默认行为，来源在 build_evidence.py 顶部统一维护。
PUF3 是主采样，C组的 PYNQ v1/PL-only 是历史对照，不是所有随包文件都属于 PUF3。
**不要运行旧 build_report.py 来生成最终稿**；上层 Markdown/v0.9 流水线已被独立 LaTeX 报告取代。

`build_evidence.py` 读取现有工件，校验 release/板测哈希，复算 KAT 与 benchmark，并生成
manifest.md、sha256sums.txt、appendix_c_raw.md。文件缺失或哈希不符返回非零。
build_evidence.py 只生成 C组清单/摘录，不生成最终报告。assemble.py 另收 PUF3、最终 PDF/LaTeX 源与构建核对记录。
check_benchmark_tables.py 核对最终报告和配套材料数字；assemble.py --check-only 不写新包。

从仓库根运行：

```sh
# 仅当报告编译输入改变时，先由报告侧重建；不需要改变时无需重复编译 PDF
python -X utf8 docs/tech_report/amd_fpga_2026_latex_final/amd_fpga_2026_report/build_review.py
python -X utf8 docs/tech_report/evidence/build_evidence.py
python -X utf8 docs/tech_report/evidence/check_benchmark_tables.py
python -X utf8 docs/tech_report/evidence/assemble.py --check-only
# 需要新交付快照时才装配，不自动提交或上传
python -X utf8 docs/tech_report/evidence/assemble.py
```

assemble.py 创建全新包，保留仓库相对路径与校验表。旧 submission/evidence 为历史版本，
不应再用旧 assemble.sh 的内容替代当前报告；该 shell 入口现在只转调 Python。
当前报告涉及本地备份的 PL-only 原件，必须实际打包给评审，不能假定 Git 链接能访问。
未提交文件也不自动存在于远程仓库。提交动作由项目方控制。
旧包/manifest/PDF 不因说明更新而回写；文档输入变化后需刷新派生清单与 D02 结果。
freeze_manifest.py 在已跟踪文件无改动时生成冻结清单/源码包；具体顺序见 submission/README.md。
当前与旧入口职责见 docs/version_entrypoints.md；本页不授权重建、覆盖候选或修改原始板测。
