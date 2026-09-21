# 测试向量与原始数据

当前没有已验 KAT 或 benchmark 数据。C01 固定官方/可信参考提交、算法/标准版本、路径、许可和 SHA-256；C03 保存完整比对结果，不以本地生成向量自证正确。C04/I07/Y05 交 cycle 与自动报告原始数据。

建议后续子目录：`kat/`、`benchmark/`、`reference/`，只在有真实交付时创建。每个数据集附 provenance、schema、工具/固件/bitstream 哈希和采集命令；字段约定见 [interfaces](../docs/interfaces.md)。CSV/JSON/KAT 文本不得被忽略。

公开 KAT 的固定 key/nonce 是测试数据；不收真实密钥。空输入 cycles/byte 为 N/A，未测指标为 null 并标原因，禁止填入示例数字冒充结果。

已增加 [recovery/cicc1000023](recovery/cicc1000023/readme.md)：归档全清单与哈希、恢复映射、RTL/XPR/XDC 差异、ELF 头部元数据及 3 个小输入；它们不是 Ascon KAT 或本轮性能数据。
