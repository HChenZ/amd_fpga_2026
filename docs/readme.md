# 文档适用范围索引

更新：2026-11-01。当前程序不强制统一成PUF3；先按 [版本入口](version_entrypoints.md) 选择对象，
再按 [全部版本清单](version_inventory_20261101.md) 追历史、共享依赖和包。

| 类别 | 阅读方式 |
|---|---|
| project_intro_20261101 / project_overview / architecture / interfaces | 当前PUF3与旧v1的职责、能力和限制；明确列出的历史段落仍按日期解读 |
| technical_rules / development_workflow / agent_workflow | 工程纪律与版本选择规则，不自动授权修改或提交 |
| ascon_standard_baseline | Final标准/参考/KAT来源，通用算法依据，不是某一个overlay的板测 |
| ascon_key_management / ascon_timing_review / ascon_ppa_comparison | 当时源快照的安全/时序/PPA证据；后续成功不回写旧失败，也不套用到新源 |
| freeze_checkpoint_20261018 / freeze_checkpoint_20261027 | 历史芯片级/PL-only/keys3冻结索引，非当前PUF3留档 |
| timing_* / backend_placement_campaign / cpu_timing_architecture_plan | 各日期策略/架构探索，非当前一键构建或继续优化授权 |
| advanced_* / dma_puf_implementation_plan / puf_min_explore | 独立DMA/PUF v2/MIN实验，非PUF3；注意PUF v2旧候选INVALID |
| repository_* / cicc1000023_* / vivado_project_diff | 原始仓库/恢复资产审计，保留当时缺口语境，不作为今天“没有IP/没有板测”的结论 |
| current_status_20261029 / project_abstract | 已标注的旧快照/简介；当前看提交计划和project_intro_20261101 |
| tech_report/README | 指明最终独立LaTeX/PDF入口；其下旧Markdown流水线不用来重建最终稿 |
| tech_report/evidence/README | 当前C组清单、D02、装配与冻结步骤，不运行旧build_report.py |

原始JSON/log、生成manifest、包内文档、锁定参考、Skill实验固定材料保留字节，不为说明更新重写。
旧ZIP名字带final不代表最新；当前证据/源码留档见 `submission/current_evidence.json` 和 `submission/freeze_manifest.md`。
当前文档可能晚于冻结包，新说明不会自动写回旧ZIP；需要新快照时再独立核对装配。
