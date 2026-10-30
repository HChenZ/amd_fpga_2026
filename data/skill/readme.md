# Skill validation raw results

本目录保存 Skill 验证的原始数据和结构化结果，不保存模拟输出冒充的实板数据。

PYNQ L3 Notebook 默认创建：

```text
data/skill/l3_<yyyyMMdd_HHmmss>/
data/skill/l3_current_session.json
```

每个通过项必须记录 `claim_level`，真实板结果使用 `hardware_measured`；未执行使用
`not_measured`，离线模型结果使用 `simulated`。结果目录同时保留执行后的 Notebook、
原始 JSON/日志和文件哈希。
