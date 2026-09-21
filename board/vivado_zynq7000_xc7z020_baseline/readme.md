# CICC1000023 原始 XC7Z020 baseline

来源：用户提供的 CICC1000023 技术数据 ZIP。此目录恢复真实原工程，不是新建空白工程。Vivado 2025.2，part `xc7z020clg400-1`，top `top_pl_bram`；保留原 `.srcs` 布局、31 个 RTL/header、3 个 XCI、`const.xdc` 与 `freertos_demo.coe`。

RTL/XCI/XDC/COE 均与 ZIP 字节一致。XPR 唯一内容调整是删除生成 DCP 的 File/IncrementalCheckpoint 引用并关闭 synth_1 的 AutoIncrementalCheckpoint；不导入旧 checkpoint、cache、runs 或 bitstream。完整差异在 [xpr_recovery.diff](../../data/recovery/cicc1000023/xpr_recovery.diff)，哈希及来源在 [manifest](../../data/recovery/cicc1000023/manifest.json)。

已静态核验 36 个 XPR File 路径及 XCI→COE 路径，不依赖仓库开发中的 src/rtl。XPR 的旧绝对 Project Path、ImportPath 为原作者元数据，实际源 File 指向本目录 .srcs；尚未用 Vivado 验证重定位打开行为。

原存储配置：32-bit × 32768 words（128 KiB），byte write enabled；初始化为 FreeRTOS demo，非 bootloader。clock wizard 使用 PLL，50 MHz 输入、100 MHz 输出。具体参数、历史实现报告及局限见 [恢复审计](../../docs/cicc1000023_recovery_audit.md)。

复现顺序：先运行 `python build/prepare_cicc1000023_sources.py` 校验哈希；确认 Vivado 2025.2 和目标器件支持后，在隔离构建工作区打开工程、重新生成 IP、进行非增量综合/实现，并重新保存 timing/utilization/DRC。现在只完成源资产恢复，未声明本机重新构建或上板通过。

本目录与 Kintex legacy 独立；不得把当前 Ascon RTL 自动混入原始 baseline。历史 100 MHz 时序报告不是当前 Ascon 或 ISE 的 benchmark，也不是实测 Fmax。
