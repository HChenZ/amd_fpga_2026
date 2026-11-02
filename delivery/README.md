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
[独立Skill](pynq_overlay_workflow_skill.zip) · [技术报告PDF与源](technical_report.zip)。

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
