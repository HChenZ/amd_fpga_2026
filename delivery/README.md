# 分别压缩的交付物

运行 `python tools/package_delivery.py` 创建以下四个ZIP：

1. **puf3_project.zip**：当前PUF3全部必需源码、共享支持、IP/约束、向量、已知工件hash参考及说明。
2. **historical_projects.zip**：隔离的历史独立源码与当前共享支持，和当前工程分开，不装原始证据包/缓存。
3. **pynq_overlay_workflow_skill.zip**：独立可安装Skill，含SKILL.md/工具/示例/参考/测试和许可，不依赖工程运行。
4. **technical_report.zip**：当前技术报告PDF、LaTeX编辑源与图件，附独立编译说明；不是旧final ZIP。

工程类因此有当前/历史两个独立压缩件，另外是一个Skill包和一个技术报告包。四个ZIP均入库供直接下载，
manifest.json记录版本/文件数/SHA-256。仓库仍保留所有原始证据归档，但不把这些归档塞进源码附件。
源码包不包含Vivado生成缓存、DCP/波形、完整证据包或真实密钥。

源码包解压后先按包内说明构建；已知bit/hash是原验证快照，不承诺新实现结果逐位相同。
包内容以逐文件清单为准，不由文件名final或mtime猜版本。此入口不上传比赛平台，也不自动commit/push。

完整仓库重打包不依赖忽略的结果副本：host测试fixture从原始归档读取，若没有本地LaTeX编辑树则从已跟踪的报告ZIP读取。
重新打包会更新ZIP时间戳/清单；校验时使用同次生成的manifest，不把旧hash配给新ZIP。

下载：[当前PUF3源码](puf3_project.zip) · [历史独立源码](historical_projects.zip) ·
[独立Skill](pynq_overlay_workflow_skill.zip) · [技术报告PDF与源](technical_report.zip) ·
[全部内容的单个ZIP](amd_fpga_2026_repo_snapshot.zip)（整仓快照，见文末）。

当前冻结源码：`124f5c7fc17374c343e28d0cf168bdcbffa1320a`。四包分别263/1484/28/62件（含各自清单），
SHA-256以[manifest.json](manifest.json)为准。验证见[机器记录](../build/metadata/source_delivery_check.json)：
解包host61、Skill61/3可选skip、固件BIN一致、56项生产输入/7项候选支持与共享hook/XCI检查通过；
另在没有忽略结果/报告编辑树的干净源树重打包后通过同样测试，报告ZIP内LaTeX单独编译77页。
干净源树比较只有checkout换行差异；这些检查不表示已重做Vivado/实板或跨平台字体复现。

2026-11-02 仓库按比赛推荐结构把 `docs/` 并入 `report/`（见根README目录对照）。前三个ZIP仍是 `124f5c7` 快照、**未重新打包**，
包内仍为旧 `docs/` 路径；`tools/package_delivery.py` 已改为读取新位置，下次重打包时包内路径随之更新。

**technical_report.zip 已于 2026-11-02 19:20 单独重打**（源码版本 `9433ff1`，manifest 中该项另记 source_revision/generated）：
报告修图、路径对齐与复现章节重写后为 83 页。复验见[机器记录](../build/metadata/report_repack_check.json)：
按新 manifest 运行 verify_delivery.py 四包全部 PASS（host61、Skill61/3 skip、固件 BIN 一致、elaboration），
包内 LaTeX 用 Tectonic 单独编译 exit0、83 页、无 Overfull/缺字/未定义引用，打包 PDF 与仓库跟踪 PDF 字节一致；
在 864520d 干净检出中恢复原件并放入包内 latex/ 后，review_evidence.py 194/194。上段 `source_delivery_check.json` 保留 01:20 的原始四包记录（当时报告 77 页）。

**technical_report.zip 于 2026-11-02 20:28 再次单独重打**（源码版本 `cd0f3f3`）：第四部分新增 §4.3「AMD ROSS 使用心得」后为 85 页，
62 件、SHA-256 `e183bd4c…`，包内 PDF 与仓库跟踪 PDF 字节一致。复验见[机器记录](snapshot_and_report_check.json)：
verify_delivery.py 四包全部 PASS（含对 124f5c7 已清理的内部编号做名称、正文与 PDF 文字扫描，0 命中），
包内 LaTeX 用 Tectonic 单独编译 85 页、无 Overfull/缺字/未定义引用，逐页文字与跟踪 PDF 相同。上段 19:20 的记录保留不改。

## 全部内容的单个 ZIP（整仓快照）

[amd_fpga_2026_repo_snapshot.zip](amd_fpga_2026_repo_snapshot.zip)：93,496,023 B，SHA-256
`7f49b9e5bdc4e80cf5a4f131cf4c3989457eec05f2df670f6c0d594116ae51ec`（manifest.json 的 `repository_snapshot` 项），
解压为 `amd_fpga_2026/`，共 1680 项：

- 提交 `cd0f3f3` 的全部 1620 个受跟踪文件，按 Git blob 原字节打包，只排除本目录 `delivery/`。逐成员核对过：
  PUF3 源码、历史源码、Skill 三包是 124f5c7 旧快照，成员均可在本提交或 124f5c7 中找到相同内容（换行等价）；
  其中 63 个是此后更新过的说明文档与维护脚本的旧版（快照收录当前版本，无 RTL/固件/约束），余下只是
  package_delivery.py 按模板生成的 README.md、pytest.ini、source_package.md 与 source_manifest.json；快照也不能包含自身。
- 技术报告包中不受 Git 跟踪的 58 个 LaTeX 编辑源，按原路径放在
  `report/technical/amd_fpga_2026_latex_final/amd_fpga_2026_report/`，解压后可直接重建报告。
- `snapshot_readme.md`（范围、哪些步骤需要 Git）与 `snapshot_manifest.json`（逐文件 SHA-256，`from_report_package` 列出 LaTeX 源）。

解压后在 `amd_fpga_2026/` 中核对：

```sh
python -c "import json,hashlib,pathlib; m=json.load(open('snapshot_manifest.json',encoding='utf-8')); bad=[p for p,h in m['files'].items() if hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()!=h]; print(len(m['files']),'files, mismatches:',len(bad))"
```

复验（同一[机器记录](snapshot_and_report_check.json)）：解压结果与提交树、报告包逐字节一致，无 `.git`。在解压目录中，
源集身份 PASS 且 elaboration exit0、固件 BIN/COE 与 candidate 一致、协同仿真 54 步 PASS 且反例检出、原件恢复 2420 份；
恢复原件后 pytest 122 passed/3 skipped（未恢复时 test_cycle_sources 失败）、review_evidence 194/194，
build_review 重建 85 页、194/194 且逐页文字与跟踪 PDF 相同。
sim/ascon 校验链在无 `.git` 时停在 Git 来源查询（快照说明逐项列出），在 `cd0f3f3` 的干净 worktree 中复跑全部通过：
参考门 12936/0、RTL 回归 PASS、反例 4/0、主机 28661/0、失败契约 23965/0、test_harness OK。

边界：快照与公开仓库内容一致。本轮对快照内全部文件（含已跟踪 ZIP 归档的成员与 LaTeX 源）做了同样的内部编号扫描：
只在 `archive/evidence/` 的 4 个原始记录归档和 `report/llm_collab/` 的 1 份会话原文中出现，按原始记录原样保留；
其余文件（维护文档、源码、archive/history、报告与 LaTeX 源）中为 0。快照不是新的 Vivado 或实板验证。快照由一次性脚本按上述规则生成，不在
`tools/package_delivery.py` 中；重跑该脚本会整体重写 manifest.json（不保留 `repository_snapshot` 项），需重新登记。


2026-11-02 代码块排版修复：**当前 technical_report.zip 已再次单独更新，仍为85页**，指定长命令在PDF第58页为一行；所有代码块取消续行符号。仅其PDF、preamble.tex、编译说明与清单改变。当前SHA-256见manifest.json；[排版/包校验](../report/technical/validation/codeblock_layout_20261102/readme.md)。其他三个包及上面的整仓快照仍为历史版本，未覆盖或重打。
