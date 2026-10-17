# 构建与复现

已恢复真实 XC7Z020 XPR、三个 IP XCI 和固件/测试源；尚未完成 Vivado/固件重建。历史报告在 reports/cicc1000023_archive，本轮模块测试证据在 metadata。B02/B04 继续关闭构建依赖与验证缺口。

## 存放约定

| 路径 | 内容 |
|---|---|
| 本目录中的受控脚本 | Tcl/构建/验证入口；待后续任务实现 |
| `reports/` | 精选 synthesis/implementation/timing/utilization 摘要 |
| `metadata/` | 工具/IP/source/part/top/约束/命令/哈希和复现记录 |
| `local/`、`tmp/`、`cache/`、`generated/`、`artifacts/` | 可丢弃输出，已 ignore |

不要把唯一证据留在被忽略的 runs 中；导出摘要和必要原始结果后再清理。KAT 与 benchmark CSV/JSON 放 data，不被全局 ignore。

## 第一阶段可复跑的静态检查（PowerShell）

在仓库根目录，安装可用的 Icarus Verilog 后执行：

```powershell
$auditOutput = Join-Path $env:TEMP 'amd-fpga-stage1-audit'
New-Item -ItemType Directory -Force -Path $auditOutput | Out-Null
$rtlFiles = @(Get-ChildItem src/rtl -File -Filter '*.v' | ForEach-Object FullName)
iverilog -g2012 -I src/rtl -s top -o (Join-Path $auditOutput 'top.vvp') @rtlFiles
# 检查 $LASTEXITCODE；本轮为 0，仅 elaboration。
iverilog -g2012 -I src/rtl -s top_pl_bram -o (Join-Path $auditOutput 'top_pl_bram.vvp') @rtlFiles
# 本轮为 4：缺 clk_wiz_0、axi_bram_ctrl_0、blk_mem_gen_0。
```

第一阶段未加 dummy IP、未运行 vvp。恢复阶段已运行两个模块 TB，结果另记。2026-09-21 使用 Icarus 12.0 devel；完整命令与输出见 [repository_audit](../docs/repository_audit.md)。Vivado/Vitis/RISC-V GCC 在本轮 PATH 未发现，这不表示磁盘上一定未安装。

## 下一步完整构建

按 [development_workflow](../docs/development_workflow.md) 恢复源依赖，记录 tool version，使用已恢复的真实目标配置验证综合/实现/上板。11-02 D05 从干净环境执行；在此之前不提供未经验证的“一键完整运行”命令。

## 恢复资产校验与原名工作副本

```powershell
python build/prepare_cicc1000023_sources.py
python build/prepare_cicc1000023_sources.py --stage cicc1000023_sources
```

第一条核对 579 个资产哈希；第二条只向不存在的 build/local 子目录还原原包大小写文件名与 formal 相对 RTL/少量 HEX 输入，不执行任何旧脚本。已有同名工作副本会被拒绝覆盖，可换一个新名称。源目录使用小写存储名，实际编译应在原名副本进行；kernel/bootloader/ISA harness 缺口见 [恢复审计](../docs/cicc1000023_recovery_audit.md)。

[本轮验证元数据](metadata/cicc1000023_recovery_verification.json) 留存恢复 RTL elaboration、tb_bypass、tb_regfile 的精确命令和输出。

恢复资产由 `.gitattributes` 禁止 Git 自动换行转换，以保持源字节及 manifest 哈希；普通文档不因此要求全仓统一行尾。

Git 行尾例外：两份 Kintex legacy XPR/XDC 在已有提交中的 blob 为 LF、恢复工作区为 CRLF；精确文件规则使用 text/eol=crlf 保留这一既有状态。从 ZIP 恢复的源资产仍使用 -text，禁止格式化；哈希校验依据工作区原始字节。

## 2026-10-16 key lifecycle review

Current software/MMIO/ISE runtime APIs, ZEROIZE, CPU handshake, test commands and build evidence: [review](../docs/ascon_key_management.md). Earlier dated status above is historical. Board model remains unknown; no programming performed.

The continuation's [100 MHz review](../docs/ascon_timing_review.md) retains each implementation round.
`build_ascon_review.tcl` accepts a build leaf, `fresh`/`resume`, and an optional report leaf;
fresh runs refuse to overwrite either an existing build or report directory.
