# D11：聊天导出与报告说明修订（2026-11-03）

owner TBD；接口无变化。按用户截图逐项核对 delivery/technical_report.zip（原 SHA-256 623b1857…），
直接修改包内 latex/readme.md 与 README.md；[实际包内说明副本](package_readme.md)、[校验记录](check.json)。
修正85页/当前排版版本、旧证据与版本入口、归档构建脚本路径、Python3.14.3、已提交状态；
命令使用 <tectonic路径>，补 DejaVu Sans Mono 2.37 的字体安装/静默回退说明。保留带日期的历史修图记录和原编号。

仅重打独立报告ZIP，更新其source_manifest及delivery/manifest.json条目。62成员中仅两份Markdown与清单改变，
61个文件SHA-256与ZIP CRC通过；其余59成员字节一致，PDF仍85页且与跟踪PDF一致。
其他3个ZIP、RAR及整仓冻结快照保留原字节/清单，不含本次说明更新。未重编PDF，未重跑194项证据、RTL/固件/Vivado或板测。

使用 Python 3.14.3：

```powershell
python -X utf8 report/llm_collab/export_sessions.py --tool codex --full-text
```

本机新增5个Codex会话（10-28、11-01、11-02两份、11-03当前会话），连同原有21个记录共26个。
所选会话按cwd过滤，提示词/可见回答不截断；不输出隐藏推理或系统/开发者指令，工具调用为摘要，附件图片不内嵌。
当前会话只截至导出时；其他设备/未保存聊天不在范围内。旧21份Markdown不改；网页/其他工具记录不冒充本次完整导出。
导出器保留其他设备/工具记录及索引，支持无时间戳文件名，工具摘要同步打码。

验证命令（本机临时脚本留于ignored目录；交付不依赖该目录）：

```powershell
python -X utf8 build/tmp/chat_report_fix_20261103/update_report.py
python -X utf8 build/tmp/chat_report_fix_20261103/verify.py
git diff --check
```

均exit0。包内逐成员哈希/CRC、当前PDF字节/页数、四ZIP总哈希及其他清单不变、26条索引链接通过。
隔离合成会话验证输入只读、保留旧导出/索引、过滤非可见消息与UI上下文、不截断长正文、工具摘要打码。
新增导出未发现高置信令牌/私钥格式。首次合成校验因缺时间戳生成问号文件名在Windows失败，已修正为unknown_date并复跑通过。

合并队友远端d5a985b及本地既有全貌图提交，日志冲突保留双方；入场5份未提交改动恢复并单独保留在工作区，
本次提交仅纳入D11增量。下一接收D03/D06，平台上传、全宽度复现与PUF未测边界维持原状态。
