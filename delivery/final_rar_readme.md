# 最终RAR交付（2026-11-02）

下载：[RISC-V轻量密码加速SoC_最终交付.rar](RISC-V轻量密码加速SoC_最终交付.rar)。

- 源码基准：当前main的 `cfa3817799f0c8fb44a18f4f114226a229f019d3`，不是旧puf3_project.zip或旧整仓快照。
- 大小7,025,851字节（约6.70 MiB），RAR5格式；367个文件，唯一顶层目录 `RISC-V轻量密码加速SoC/`。
- SHA-256：`e216016471330cf3f4c2ab33cd2465e3c7a069389ee82e6fd15b6a8056e1f4da`。
- [机器校验记录](final_rar_manifest.json)、[逐文件SHA-256](final_rar_files.json)、[RAR校验文件](final_rar_sha256.txt)。
- 包内根README由 [final_readme.md](final_readme.md) 提供，代码入口由 [final_code_readme.md](final_code_readme.md) 提供；并非直接复制仓库旧README。

## 装配范围

code保留CPU/Ascon/ISE/MMIO/RO-PUF/DNA、PUF3 Tcl与变体RTL、固件及共享支持、主机驱动和Notebook、仿真测试与官方KAT。
candidate下bit/hwh/bin/coe/elf、manifest和原报告全部原字节保留。
共享IP按原层级保留axi_bram_ctrl_0/blk_mem_gen_0 XCI及ascon_keys.coe；共享RO hook、pblock和两套固件支持不可删。
为host单测复制六项原归档周期fixture，逐项标注来源；这些是历史模拟样本，不冒充当前板测。
旧v1公共API/Notebook保留为共享单测兼容依赖，根README明确只用PUF3 Notebook上板；历史独立项目不入包。

技术报告为排版修复后的85页，PDF SHA-256为 `c3a474d8d9a98d9e1a08034a47a6531ef8d6be72cf70c31ee87f1584a5ff0e0e`。
LaTeX与图件从同一最新版technical_report.zip提取，先校验该ZIP的source_manifest及包内PDF与正式PDF字节一致，未改报告正文。
Skill目录按当前Git跟踪源复制，独立ZIP也从当前源生成；不复用旧包。ZIP SHA-256为
`75a3aef79af0ada98c64baa42ae3aed9a30f8de6676a0160b7b39c65d61fe505`，全部安装文件与展开目录逐字节一致。
原四包、原manifest条目和整仓冻结快照不重写；总manifest仅新增final_rar项。

## 校验结果与边界

RAR创建、RAR test、实际解压均exit0；RAR5魔数正确。解压后所有367文件与打包前一致，根README全部相对链接存在。
源集56生产输入、7候选构建支持和5候选工件检查通过，Icarus展开exit0；所有candidate报告也逐文件比对。
主机单测61项通过；独立Skill 61 passed/3 skipped（依赖其他实物工程的可选项），CLI帮助exit0。
测试前后各执行一次完整清单验证，366个清单成员全部匹配，清单本身另与打包前比对；无源码修改。
扫描未发现高置信私钥/令牌格式；不包含.git、虚拟环境、Vivado缓存、个人Agent配置或无关交付ZIP。
必须保留的原源码/报告内已有历史开发机路径不做篡改，根README说明运行时使用PATH和本地快照的做法。

没有执行固件重编、Vivado综合/实现或实板测试。没有声称完成干净环境硬件端到端复现。
新版README修正原入口中旧ZIP仍含当前全部源码、code子目录与ASCON_REPO、Git元数据缺失、报告独立编译与完整证据核验的区别。
PUF可靠性、RO签核、PT/AD各16B和其他未完成边界保留。

## 工具与重建

本机无WinRAR/rar.exe，使用 [RARLAB官方RAR for Linux x64 7.23](https://www.rarlab.com/download.htm)（试用许可）在WSL Ubuntu执行；工具不随交付包分发。
下载来源 `https://www.rarlab.com/rar/rarlinux-x64-723.tar.gz`。Windows安装WinRAR后也可使用其rar.exe。
重建脚本只读生产输入，写新临时装配目录和delivery；不会执行综合。已有同名RAR时主动停止，避免覆盖旧包。

```powershell
python -B -X utf8 tools/package_final_rar.py --rar 'C:/Program Files/WinRAR/Rar.exe'
```

或在Windows主机使用已准备好的WSL官方二进制：

```powershell
python -B -X utf8 tools/package_final_rar.py --wsl-rar /absolute/linux/path/to/rar
```

脚本需要Python、PyMuPDF、pytest、Icarus及对应RAR工具；未将外部工具打包。
打包输出时间等元数据可能改变RAR哈希，重建必须使用同次生成的manifest，不沿用本说明中的旧数值。
