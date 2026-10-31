# 当前提交候选入口

项目方安排：2026-11-01 提交并冻结。`current_evidence.json` 指向本轮装配并校验的证据包及 ZIP 哈希。
`evidence/` 为此前生成的历史包，保留原样，不作为本轮最新版。

Git 中只保存证据包目录。ZIP 和历史包 `evidence/` 不入库，只留在本机。需要 ZIP 时，
运行 `python -X utf8 docs/tech_report/evidence/assemble.py` 重新装配；`current_evidence.json`
里记录了当时 ZIP 的哈希。

本目录的证据包包含报告、原始测量和精选实现报告，不是完整工程源码/全部比赛材料。
PPT、视频、团队信息、平台附件要求与人工上传回执仍由项目方确认。
不要自动 commit/push 或上传；包内存在未实测项说明不表示其已经通过。
