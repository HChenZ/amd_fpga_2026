# 设计与工程约定文档导航

当前入口从project_board.md和README.md开始。本目录原为顶层 `docs/`，2026-11-02 按比赛推荐结构并入 `report/design/`，
其余文件正文未改，仅更新了指向已移动文件的路径。

- [reproduce_from_zero.md](../reproduce_from_zero.md)：按当前PUF3入口从克隆、环境到离线验证、重建与上板；区分现成候选和新构建。
- project_intro_20261101.md / project_overview.md：项目简介与范围。
- architecture.md / interfaces.md：当前结构和协议，以及旧v1的兼容边界。
- technical_rules.md / development_workflow.md / agent_workflow.md：验证纪律和协作规则。
- version_entrypoints.md：当前入口与历史路径隔离说明。
- [../technical/](../technical/README.md)（原docs/tech_report/）：当前报告入口；独立LaTeX编辑树在本机，最终源/PDF另包交付。
- [../llm_collab/](../llm_collab/index.md)：大模型协作原始会话记录。

历史评审、时序/恢复/原型说明移到archive/history/docs，原始档案在archive/evidence。
中性名称用于避免把内部资产编号当产品来源；保留真实许可证、原始档案和Git历史，不据此宣称未经证实的原创或安全性。
