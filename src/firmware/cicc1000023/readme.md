# CICC1000023 固件源资产

恢复的 package：`coremark_rv32`、`coremark_rv64`、`freertos_demo`、`riscv_tests`。源文件内容与 ZIP 字节一致，保留原版权声明；排除编译 ELF/BIN/HEX、dump、object、cache、Zone.Identifier 和生成的 core.h。详见 [恢复清单](../../../data/recovery/cicc1000023/manifest.json)。

## 文件名与构建入口

为遵守新增路径的小写规范，仓库存储名统一小写；manifest 保存原文件名与原始 SHA-256。**不要直接在存储目录运行旧 Makefile**：旧脚本中的 `crt0.S`、`startup.S`、`FreeRTOSConfig.h` 和 `Makefrag` 对大小写有要求，`.S` 还控制预处理。

从仓库根目录执行：

```text
python build/prepare_cicc1000023_sources.py
python build/prepare_cicc1000023_sources.py --stage cicc1000023_sources
```

第二条仅在 ignored 的 build/local/cicc1000023_sources 恢复原文件名和原内容，不执行旧脚本，目标已存在则拒绝覆盖。之后可以在隔离副本评审/修复历史构建依赖；不得对恢复原件做未记录的自动修复。

## 可用性边界

| package | 已恢复 | 尚未闭环 |
|---|---|---|
| coremark_rv32 | 算法、port、UART、crt0、riscv.ld、Makefile、格式转换 | linker 起址 0x10001000；CPU 复位在 0x10000000。bootloader 只找到 COE，尚无源码/构建链；交叉工具链待配置 |
| coremark_rv64 | 同类 RV64 源及构建输入 | 需要 RV64 固件/CPU/存储配置一起验证，不把 32-bit BRAM 工程直接算 RV64 平台 |
| freertos_demo | 应用、CoreMark 集成、配置头、startup、linker、工具、应用契约测试 | Makefile 引用的 ../FreeRTOS-Kernel-main 未包含在此 ZIP；kernel 版本需取得。install-ram 写原作者绝对路径，禁止未经适配执行 |
| riscv_tests | ISA 汇编、全部 Makefrag、宏、env、Makefile.in、configure.ac、许可/README | 未恢复配置生成的绝对路径 Makefile；未引入 benchmarks/debug 等非本轮范围；需适配 IM/Zicsr 构建。部分 env 文件是扁平化链接文本，不能直接当有效 linker script |

已存入两个 add HEX 验收候选和一个 bootloader COE，均在 data/recovery/cicc1000023/smoke；这些是原归档编译产物，不是本轮构建结果。大批 ELF/HEX 保留在 ZIP，只以路径/哈希入清单。

没有运行固件重编译、CoreMark 性能测试或 FreeRTOS 上板；B04 仍需完成依赖锁定与实跑。更详细的 A/B/C/D 分类和目录映射见 [恢复审计](../../../docs/cicc1000023_recovery_audit.md)。
