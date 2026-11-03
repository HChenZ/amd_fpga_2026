# 原始证据与快照归档

仓库保留原始资料，但交付附件是工程源码、Skill、技术报告，不再要求提交旧证据包。

| 文件 | 内容 |
|---|---|
| raw_records_20261102.zip | 原始host/ISA/实现/高级实验/恢复/Skill/会话及历史说明，逐项SHA-256，不改内容 |
| submission_snapshot_20261101.zip | 清理前最后一个完整提交快照，保留原ZIP字节，仅供追溯，不是新源码交付 |
| entry_documents_before_cleanup.zip | 清理前入口文档原件，供追溯描述调整 |
| historical_artifacts_20261102.zip | 旧工程candidate/release/work中的78个生成工件原件，含逐文件SHA-256 |
| prior_snapshot_variants_20261102.zip | 前一仓库快照中未被其他归档覆盖的72种原字节，包括旧提交差异与整理前措辞；不重复全部旧展开包 |
| source_delivery_checks_20261102.zip | 本次分包的解包host/Skill/固件/elaboration工具输出、干净源树重分包检查与报告独立编译日志；不作为比赛附件 |
| index.json | 归档哈希、记录数与中性路径迁移说明 |

源目录旧重复展开包/更早ZIP在本机archive/local_only或Git历史，不再占用当前入口。
原件可能含当时路径/内部标记，不能为对外措辞而篡改。ZIP成员名使用中性路径别名，成员内容hash保持原样。
历史Skill预检Notebook的原执行输出也完整存于raw_records；历史源码只保留明确标注的source副本，不伪称新执行。
第三方许可与实际来源保留，不据整理后的简称宣称来源被改变或完全从零开发。

需在完整仓库重建报告原件摘录时运行 `python tools/restore_records.py`，只恢复本机忽略副本，
已有文件字节不同则拒绝覆盖；不重新生成测试结果，不改归档状态。
