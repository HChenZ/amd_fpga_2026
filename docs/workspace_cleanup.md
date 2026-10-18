# V10 工作区清理与清理后复验

2026-10-18；owner TBD。用户先确认清理废弃文件/可再生缓存，随后确认
**保留最终同版 RTL 的双策略 RPT**，删除旧报告及无用 BAT/JSON/TXT，并重新检验数据一致性。

**最新决定：**复验期间另一个会话恢复/重生成了6个旧路径。用户确认“暂时保留并行产物”，
因此这些文件不再次删除；功能数据复验已一致，最终留存收口延期到并行任务结束。

## 已删除

- 根目录过期时序指南/错误结论文档、`apply_timing_fix.bat/.sh`、两份过期执行状态文档、
  两份 `dfx_runtime.txt`。旧 apply 脚本会覆盖 dcache 并重置共享 sweep，不能再作为入口。
- 9 个旧报告目录：`ascon_key_lifecycle`、`ascon_timing_r1/r2`、三套 `dcache_pipe_*`、
  `strategy_sweep_20261017`、`timing_acb_baseline`、`timing_acb_lint`。
- 不再被最终检查器使用的 fix_r1/A/A+C/dcache 中间 JSON 和配套日志、A+C 中间 ISA 结果、
  旧策略汇总 JSON/CSV。旧结果不会因此变成 PASS；之前记录的失败结论保留在文档中。
- 明确停止的自有实验目录中的 XSim 输出、Vivado `.cache/.hw/.Xil`、Python bytecode 和
  未释放的参考 DLL 临时目录。不清空 `build/local`，不清理共享 sweep 或用途不明的用户工程。

共 **564 个文件、18,684,110 bytes（约17.82 MiB）**；其中 312 个旧 RPT、66 个中间 JSON、
48 个 TXT、4 个 BAT（包含 XSim 自动生成脚本）。目录/逐文件 hash 和清理授权记录在
`build/metadata/cleanup_20261018.json`。被用户明确要求裁剪的历史原始报告不再保证本地可复核；
不得继续将旧文档中的路径当作现存文件。

## 保留

- `build/reports/timing_acb_20261018/`：最终综合 RPT 2 份及双策略最终 RPT 各4份，共10份。
  保留 `build_context.txt`、`source_hashes.json`、端点 CSV、`result.txt` 等被最终检查实际使用的元数据。
- `build/reports/cicc1000023_archive/` 是原始恢复归档，不属于本次实验的旧报告，按已确认范围保留。
- 全部生产 RTL/固件、KAT/参考实现、恢复 baseline、两个最终 routed DCP、生产源快照。
- 最终功能 JSON/log、ISA 控制与最终候选结果、XSim 复核日志、`key_cases.h/.mem`。
  它们是当前结果复核/重跑的输入，不属于“无用 JSON/TXT”。
- `ascon/ASCON.xpr` 及关联缓存用途未完全确认；其他 Vivado 会话/共享 sweep 不操作。

## 辅助脚本调整

- `.gitignore` 增加根目录和 ascon 目录的 `dfx_runtime.txt`，避免重新污染工作区。
- 三个历史汇总器增加“旧报告已清理”的提前退出提示，防止误生成空 sweep 结果或覆写历史数据：
  `build/aggregate_strategy_sweep.py`、`sim/ascon/summarize_key_review.py`、
  `sim/ascon/summarize_timing_review.py`。这些脚本保留用于重新生成对应旧报告后的历史复现，
  不能混用当前结果伪造旧版本证据。
- 新增 `sim/ascon/verify_cleanup.py`：真实重编译/仿真，不仅重读已有 PASS。
  本次清理没有修改 RTL、固件、时钟/XDC 或 IP 功能配置。

## 删除后复验（数据一致；留存收口暂缓）

```powershell
$env:PYTHONDONTWRITEBYTECODE='1'
python sim/ascon/verify_cleanup.py --cc-prefix C:/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf- --label cleanup_v10
```

复验包括8项整机 sw/hw/ise/security/hold/reset、MMIO/ISE生命周期、5项单元、50项ISA，
逐项比较清理前后的有效固件二进制、测试输出/周期数及源码hash；最后核实清理前冻结的231个
生产源/最终报告/结果/DCP文件hash不变。ISA预期仍49 PASS/1个既有ma_data失败，不能改成全绿。

真实重编译/仿真已完成：

| 检查 | 清理前后对比 |
|---|---|
| sw/hw/ise、三模式 security、ISE hold/reset 共8项 | 全部PASS，源码hash/有效固件bin/测试输出和周期逐项相同 |
| MMIO/ISE生命周期 | PASS，检查结果与源码hash相同 |
| CPU单元5项（含乘法1259例） | 全PASS，测试源相同 |
| ISA全部50项 | 同为49 PASS、ma_data 1 FAIL，汇总逐字段相同 |
| 保留的231个源/最终报告/输入/结果/DCP | hash全部相同 |

周期仍为 sw enc16B=17353、hw full MMIO=670、ISE=2496；最终双策略WNS仍+0.001/+0.007ns。

**完整复验脚本实际exit 1，原始FAIL记录保留不改写**：失败仅在最后“删除目标不得重新出现”
这一留存检查，数据一致性检查全部已过。不能把这次综合FAIL隐去或把ISA改写成全绿。
原始记录：`data/ascon/results/cleanup_v10_verification.json`，本轮日志 `build/local/cleanup_v10/`。
授权变更和复验结果判读记录在 `build/metadata/cleanup_20261018.json`。

按用户最新确认暂时保留的6个路径：

- `dfx_runtime.txt`（Vivado重新生成）；
- `build/reports/ascon_key_lifecycle/`、`ascon_timing_r1/`、`ascon_timing_r2/`（31文件与删除前相同）；
- `build/reports/strategy_sweep_20261017/`（并行会话重新导出了报告）；
- `data/ascon/results/strategy_sweep_20261017/`（并行重新生成的汇总）。

不删除并行新增的 PPA 文档、PYNQ 源码或重新导出脚本，也不停止其他会话。
“已删除564个文件”描述执行过的删除操作，不再等同于当前净删除量或目录仅剩最终报告。
没有重新运行布局布线；STA一致性由保留的最终报告/DCP/源码hash以及独立解析器核对。

未 commit/push，未上板。下一接收任务仍为 B03/V01/I08 的板级核验。
