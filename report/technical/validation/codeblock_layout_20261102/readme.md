# D03-CODE 技术报告代码块排版验证（2026-11-02）

owner TBD；接口变化：无。仅修改正式 ZIP 内 preamble.tex 的统一 codeblock 环境，所有正文、图件、证据摘录源逐字节不变。
保留 scriptsize / DejaVu Sans Mono / Scale=0.92；代码区 FakeStretch=0.9，framesep=0.8mm，左右外留白为 0。
breaklines=true、breakanywhere=false、breaksymbolleft/right={}、breakautoindent=false、breakindent=1em。
命令源码不加硬换行；超长命令仅在空格自动折行，以缩进表示同一命令的续行，不插入符号。

构建：Python 3.14 / Tectonic 0.15.0（TeX 包集 tlextras-2022.0r0）；本机补装原字体 DejaVu Sans Mono 2.37。
从正式 technical_report.zip 恢复编辑源、运行 python tools/restore_records.py 后执行：

```powershell
python -X utf8 report/technical/amd_fpga_2026_latex_final/amd_fpga_2026_report/build_review.py --tectonic build/local/tectonic/tectonic.exe
```

实际 --tectonic 使用隔离检出下的绝对路径，详见 build_summary.json；退出码 0，PDF review_evidence 194/194。
用 tools/package_delivery.py 的 write_zip 函数仅重打 technical_report.zip，更新该包 source_manifest 和 delivery/manifest.json 对应项。
重新解包，沿用 tools/verify_delivery.py 的 unpack 检查四包 SHA-256/CRC/逐成员 hash；独立 Tectonic 编译包内 main.tex exit0，85 页且逐页文字一致。
所有其他 ZIP/manifest 条目、历史 repository_snapshot 均不变。其历史 PDF 保持冻结，不表示包含本次修复。

新旧都是 85 页；23 个代码块，31 行可识别命令在源码中完整保留且可从 PDF 找到。
25 个含代码页面已渲染检查；重点 §3.4 为 PDF 57–62 页，指定命令在第58页完整一行。
新旧正文去掉空白、旧续行标记、页脚页码、目录和两种重复续表表头后，87189 个字符逐字一致。
原始全文比较不完全一致是目录页码及续表分页位置变化，check.json 同时保留原始比较 false，不隐瞒分页差异。
全部嵌入图片像素 digest/次数一致；代码文字边界检查无异常。旧符号在提取文本中为 ,→ 和 ⌋，新版无额外续行符号。
原稿与新版同环境对照：Overfull 0、缺字0、未定义引用0；Underfull 均64处，Fandol Script CJK提示均2处。
Tectonic 还保留原有 fontconfig、lineno 包编码和输入 PDF 1.7/输出1.5 提示；未修改正文/第三方包来消除已有提示。

完整 verify_delivery.py 的源集 elaboration、host、Skill检查退出0，在 cold_firmware 因缺少历史 xPack RISC-V GCC 退出1；
没有重跑/修改固件或把该阶段记为通过。报告范围校验（含四包哈希）全部通过，详见 check.json。
首次编译因原字体缺失被门禁拦截；补齐原字体后正式重编通过，失败日志留在本地 validation/build_20261102_212130。

修改前 PDF/ZIP 备份：E:/amd_fpga_2026_backups/report_layout_20261102/build/local/report_layout_backup/。
源版本 3efdf5525cb2a9fe4325ee21fb0b3273ca97b868，原 E:/amd_fpga_2026 的未提交5文件和本地分叉提交保持原状。
下一接收：D03/D06 使用新报告与 manifest；无新增技术结论，原实板未测边界不变。
