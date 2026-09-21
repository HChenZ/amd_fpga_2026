# 原归档恢复证据

- `manifest.json`：579 个恢复资产的 ZIP/工作区来源、原始 SHA-256、落地 SHA-256、A/B/C/D 类别、原文件名映射与唯一 XPR 转换。
- `archive_inventory.csv`：全部 2855 个非目录 ZIP 条目的大小、SHA-256、分类与恢复位置；包含不恢复的编译/生成产物记录。
- `xpr_recovery.diff`：从原 XPR 到去除增量 DCP 依赖副本的完整差异。
- `smoke/`：两个历史 add HEX 和 bootloader COE；编译产物候选，不是本轮测试通过的证据。

归档 SHA-256：`f86c448e8923c6ddde4bca6f276f48ef00828af0849d4b5b28af85c95058af60`。读取全部成员 CRC 检查通过；本轮未将 ZIP 或 bitstream 复制进 Git。

分类 A=source；B=reproducible build input；C=compiled artifact；D=generated result/其他元数据。COE 虽由软件编译而来，但被原 BRAM 直接引用的一份同时是必须的 B 类重建输入。`D_selected_evidence` 仅指导出的少量历史报告，不是整个 generated 目录。

## foundation 分类口径

manifest 新增 foundation_category：A source 485；B build/config input 85；C test/reference data 3；D historical evidence 6，合计 579。A 包含测试源码、随源许可证/README；B 包含 formal Tcl、Makefile、文件表、转换脚本及初始化 COE；C 仅少量编译测试输入，不能称为本轮构建产物；D 仅精选历史报告/日志。

原 category 与 archive_inventory 保留上一轮“来源/编译/生成”分类，两种口径不可混用。legacy 两个 workspace 来源路径保留恢复时 provenance，并补记 source_revision；现在的 destination 经 git mv 保持不变。统计与路径范围见 [收口检查](../../../docs/repository_foundation_closeout.md)。
