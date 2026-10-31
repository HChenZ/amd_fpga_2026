# 当前报告证据包

`build_evidence.py` 读取现有工件，校验 release/板测哈希，复算 KAT 与 benchmark，并生成
manifest.md、sha256sums.txt、appendix_c_raw.md。文件缺失或哈希不符返回非零。
当前分组包含 PYNQ release/实现/板测、host 验证、历史 PL-only 对照及独立 PUF 原型；三者不混用。

从仓库根运行：

```sh
python -X utf8 docs/tech_report/evidence/build_evidence.py
python -X utf8 docs/tech_report/build_report.py
python -X utf8 docs/tech_report/evidence/assemble.py
```

assemble.py 创建全新包，保留仓库相对路径与校验表。旧 submission/evidence 为历史版本，
不应再用旧 assemble.sh 的内容替代当前报告；该 shell 入口现在只转调 Python。
当前报告涉及本地备份的 PL-only 原件，必须实际打包给评审，不能假定 Git 链接能访问。
未提交文件也不自动存在于远程仓库。提交动作由项目方控制。
