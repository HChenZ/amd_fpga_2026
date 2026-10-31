# 当前提交候选入口

项目方安排：2026-11-01 提交并冻结。`current_evidence.json` 指向本轮装配并校验的证据包及 ZIP 哈希。
`evidence/` 为此前生成的历史包，保留原样，不作为本轮最新版。

Git 中只保存证据包目录。ZIP 和历史包 `evidence/` 不入库，只留在本机。需要 ZIP 时，
运行 `python -X utf8 docs/tech_report/evidence/assemble.py` 重新装配；`current_evidence.json`
里记录了当时 ZIP 的哈希。

本目录的证据包包含报告、原始测量和精选实现报告，不是完整工程源码/全部比赛材料。

`freeze_manifest.md`/`.json` 是冻结留档（V04）：记录冻结源码提交、三套交付工件哈希与板测绑定、
证据包 ZIP 哈希、已知限制。完整源码包 `source_<commit>.zip` 由 `git archive` 生成，只含已跟踪文件，
不入库。重新生成顺序（要求工作区已提交干净）：

```sh
python -X utf8 docs/tech_report/evidence/check_benchmark_tables.py   # D02，报告改动后必跑
python -X utf8 docs/tech_report/evidence/assemble.py                 # 证据包
git commit ...                                                       # 提交证据包目录
python -X utf8 docs/tech_report/evidence/freeze_manifest.py          # 冻结清单 + 源码包
```
PPT、视频、团队信息、平台附件要求与人工上传回执仍由项目方确认。
不要自动 commit/push 或上传；包内存在未实测项说明不表示其已经通过。
