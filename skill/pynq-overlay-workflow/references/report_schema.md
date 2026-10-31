# 报告指标 schema（`report_schema.*.json`）

指标是**配置出来的**，不是写死在报告代码里。换题目/换板卡只需换 schema 和数据文件。

```json
{
  "schema_version": 1,
  "title": "报告标题",
  "sources": {
    "util":  {"kind": "utilization", "evidence": "tool_report"},
    "board": {"kind": "json",        "evidence": "measured"}
  },
  "metrics": [
    {"name": "LUT", "unit": "cells", "source": "util", "path": "all.Slice LUTs.used", "required": true},
    {"name": "all passed", "source": "board", "path": "cases.*.ok", "agg": "all_true", "required": true},
    {"name": "peak", "unit": "MB/s", "value": 400, "evidence": "estimated", "basis": "100 MHz x 4 B"}
  ]
}
```

| 字段 | 规则 |
|---|---|
| `sources.<名>.kind` | `utilization`（Vivado `report_utilization`）、`timing`（`report_timing_summary`）、`json`（任意结果文件） |
| `sources.<名>.evidence` | 该来源数值的默认证据级别：`measured` 板上实测、`tool_report` Vivado 报告数值（不是板上测量）、`simulated` 模型/仿真、`estimated` 估算 |
| `metrics[].path` | 点号路径；数字索引列表；`*` 展开列表元素或字典值。`utilization` 来源可用 `all.<Site Type>.used/available/util_pct`、`header.design/device/design_state`；`timing` 来源可用 `wns_ns`、`tns_ns`、`whs_ns`、`ths_ns`、`timing_met` |
| `metrics[].agg` | 路径含 `*` 时必须给：`count`、`sum`、`min`、`max`、`mean`、`all_true` |
| `metrics[].value` | 常量指标；必须同时给 `evidence`；若为 `estimated` 必须给 `basis`（估算依据） |
| `metrics[].evidence` | 覆盖来源的默认级别（例如从 hwh 推出的参数标 `tool_report`） |
| `metrics[].required` | 必需指标取不到时，报告 Problems 中列出且 CLI 返回 1 |

缺失规则：来源文件未提供/不存在/无法解析，或路径取不到，该指标值为空、证据为 `not_measured`，
并在 note 中写明原因；**不会**被省略或补成 0。

命令行：

```powershell
python scripts/pynq_skill_cli.py report --schema examples/report_schema.dma_loopback.json `
  --source util=<utilization.rpt> --source timing=<timing_summary.rpt> --source board=<board_result.json> `
  -o report.md            # 同时写 report.json；必需指标缺失时 exit 1
```

示例 `examples/report_schema.dma_loopback.json` 对应本仓库的非 Ascon AXI DMA 回环 overlay：资源与时序取自
其 Vivado 报告（`tool_report`），传输次数/字节/比对结论取自实板结果（`measured`），吞吐量在该次实板运行中
未采集 → `not_measured`，理论流峰值为带依据的 `estimated`。
