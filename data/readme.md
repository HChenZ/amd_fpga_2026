# 测试向量与原始数据

更新：2026-11-01。已有标准 KAT、host/RTL/CPU、板测与 benchmark 数据，不再是空预留目录。

| 路径 | 对应对象 |
|---|---|
| `ascon/` | 锁定 Final 标准/完整 1089 KAT/参考派生向量；results 的 host、独立 RTL、历史 CPU/PL-only 与 ISA 证据各有版本 |
| `pynq_puf3/notebook_20261031_114512/` | **当前 PUF3 报告主采样**：三模式 KAT/benchmark/PUF，绑定 candidate bit/hwh/manifest |
| `pynq/` | 旧 PYNQ v1：10-28 全容量 KAT、10-31 benchmark/错误恢复；9/9 不属于 PUF3 |
| `skill/` | 独立 L2/L3/报告采集证据；L3 Ascon 是旧 v1，另有 GPIO/DMA 回环 |
| `advanced/` | 独立 CPU-DMA/HW_DIRECT/PUF v2/PUF-MIN 实验；不是 PUF3 多块或 DMA 板测 |
| `recovery/` | 原 CICC 恢复清单与原输入，不是新测量 |

C01 固定参考与 KAT hash；C03 保存完整比对结果，不以本地生成向量自证正确。
当前数据选择见 [版本入口](../docs/version_entrypoints.md)。旧数据移出工作树后仅存 Git 历史，不改写成新运行。

每个数据集附 provenance、schema、工具/固件/bitstream 哈希和采集命令；字段约定见 [interfaces](../docs/interfaces.md)。
不为说明同步修改原始 JSON/log、生成 manifest 或包内快照，CSV/JSON/KAT 文本不得被忽略。

公开 KAT 的固定 key/nonce 是测试数据；不收真实密钥。空输入 cycles/byte 为 N/A，未测指标为 null 并标原因，禁止填入示例数字冒充结果。

已增加 [recovery/cicc1000023](recovery/cicc1000023/readme.md)：归档全清单与哈希、恢复映射、RTL/XPR/XDC 差异、ELF 头部元数据及 3 个小输入；它们不是 Ascon KAT 或本轮性能数据。
