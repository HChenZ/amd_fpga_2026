# 技术报告 v0.9：当前证据对齐稿（已被最终报告取代）

## 2026-11-02 当前报告位置

本目录原为 `docs/tech_report/`，2026-11-02 按比赛推荐结构移到 `report/technical/`（层级深度不变）；
`validation/` 下的历史生成记录保持原字节，其中的 `docs/tech_report` 路径按生成时布局解读。
当前PDF：`amd_fpga_2026_latex_final/amd_fpga_2026_report/output/pdf/final_report.pdf`。
当前独立LaTeX/PDF与交付说明见report/readme.md、project_board.md和delivery/README.md。
可编辑源/图件与PDF打成delivery/technical_report.zip，最终PDF仍在原独立工程output/pdf路径。
CPU描述已去内部编号，实测数据不变，已重新编译并核对。下面v0.9流水线现隔离到archive/history/docs/tech_report，
原始记录另存archive/evidence；不得按旧路径覆盖当前稿。

2026-11-02 晚间再次重编（83 页）：按审阅意见修正图 2-1、2-2、2-4 的白底标注、穿框连线、压线文字与斜线，
同类问题顺带修正图 2-3、2-7、2-9、2-13、2-14、3-3；正文路径对齐当前仓库结构；§3.4 复现说明重写为仓库结构、
环境、离线验证判据、构建、上板判据、交付包/报告复核与边界七节，并引用干净检出离线复跑记录
`build/metadata/offline_reproduce_check.json`。性能/资源/时序数值不变；构建记录在本机忽略的
`amd_fpga_2026_latex_final/amd_fpga_2026_report/validation/`，可编辑源随 delivery/technical_report.zip 重新打包。
重建报告前先运行 `python tools/restore_records.py`，再执行该目录 readme.md 中的 build_review.py 命令。

**当前操作只按 [版本入口](../design/version_entrypoints.md) 与 [证据目录说明](../../archive/history/docs/tech_report/evidence/README.md)。**
下文旧“阅读/维护/构建入口”全部保留为v0.9历史，不是当前推荐命令；尤其不运行build_report.py覆盖最终报告。
旧压缩包名称含final/review也不代表当前PDF，选择依据是构建记录和submission/current_evidence.json。

> **2026-11-01：本目录的 Markdown/HTML/LaTeX 流水线（`report.md`、`src/`、`src_template/`、`latex/`、
> `build_report.py` 等）是 PYNQ v1 release 叙事的 v0.9 稿，已被取代，不再维护，数值不作为当前结论引用。**
> 最终报告是独立 LaTeX 工程 `amd_fpga_2026_latex_final/amd_fpga_2026_report/`，PDF 为
> `output/pdf/final_report.pdf`，主演示 PUF3 overlay，板测主采样
> `data/pynq_puf3/notebook_20261031_114512/result.json`；维护说明见该目录 `readme.md`。
> 证据装配与核对脚本在 `evidence/`（`build_evidence.py`、`check_benchmark_tables.py`、`assemble.py`、
> `freeze_manifest.py`），使用顺序见 `submission/README.md`。下文为 10-29 原文，保留作记录。

2026-10-29 更新；**11-01 提交并冻结**，以项目方最新安排为准。

## 阅读入口

- `latex/main.pdf`：本地编译的报告候选 PDF。
- `index.html`：离线正文审阅；`report.md`：同源拼接正文。
- `latex_project.zip`：Overleaf 上传包，主文件 main.tex，编译器 XeLaTeX。
- `../project_intro_20261101.md`：可直接使用的项目简介。
- `../skill_test_guide_20261030.md`：队友 Skill 执行表。
- `../../tasks/release_plan_20261101.md`：当前进度与提交计划。

主线为当前 PYNQ/RV32 短消息三模式；独立 RO-PUF/DNA 原型另章展示。
当前 PYNQ 加密 23342/1439/3995 cycles 与历史 PL-only 20806/688/2570 分列。
原型 v3 注册质量128/128、同次重建状态通过；不称完整保密隔离、跨上电可靠或安全启动。
尚无证据的 DMA、多块硬件性能及独立核 PPA 不列为成果；额外稳定性与通用性非提交阻塞。

## 维护入口

1. `src/*.md`：技术正文源；`src_template/new/*.md`：模板概述和软件模块补充源。
2. `evidence/build_evidence.py`：原始证据与统计复算，生成附录摘录及哈希清单。
3. `build_template_src.py`：重排五部分；保护外部证据文档的小节号，不按本稿重编号。
4. `build_site.py` / `build_latex.py`：生成正文、HTML、LaTeX。
5. `figs/*.tex`：图件源；照片 board_photo.jpg；预渲染 PDF 必须与源重新同步。

**不要手改** report.md、src_template 顶层四份 md、latex/chapters、图件 PDF 等生成物。
历史 gap/handoff/proposed_text_changes 与 patch_*.py 为旧审查资料，不是当前入口，不应再直接执行旧批量替换。

## 完整构建

从仓库根：

```sh
python -X utf8 docs/tech_report/build_report.py --tectonic <tectonic可执行文件>
```

已配置路径或 PATH 可省略参数。依赖 Python、pandoc、Tectonic（可访问所需 TeX 包缓存）、PyMuPDF。
构建顺序为证据→模板→HTML→图件→LaTeX→PDF→上传包→一致性检查。
每步非零停止，日志与输入/产物 SHA-256 写入 `validation/build_<时间>/summary.json`。
源在构建期间被其他会话修改时失败退出，须以最新源重新生成，不能交付混合版本。

只检查已有产物：

```sh
python -X utf8 docs/tech_report/verify_report.py
```

## 证据包

```sh
python -X utf8 docs/tech_report/evidence/assemble.py
```

新建 `submission/evidence_20261101_<时间>/` 及 ZIP，不覆盖旧包。包内保留仓库相对路径和逐文件哈希。
证据包不是完整工程源码快照或 clean-clone 成功证明；最终平台提交材料仍需团队信息、PPT/视频和人工确认。

## 审查边界

本轮复算已有数据并重建报告，没有重跑实板、Vivado、PUF 温压或 Skill 效果实验。
照片已存在但不能从照片判断当前加载镜像或芯片速度等级。warm benchmark JSON/log 已归档，执行后的本体仍待补；
error-gate 的已执行 Notebook 已归档。所有这些与“功能已运行”的结论分开。
