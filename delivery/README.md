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
