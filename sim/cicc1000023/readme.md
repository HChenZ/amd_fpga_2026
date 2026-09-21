# CICC1000023 历史验证源

恢复 21 个模块 TestBench、2 个 RV32/RV64 add TestBench 示例，以及 JasperGold 的 43 个 assertion/bind/wrapper/Tcl/脚本输入。源字节不修改；没有恢复 jgproject、stage_logs、波形或批量编译输出。是否适用于当前接口必须逐项验证。

`python build/prepare_cicc1000023_sources.py --stage cicc1000023_sources` 可在 build/local 恢复原文件名；formal 的 `../rtl` 指向原 Zynq imports RTL 的隔离副本。该命令不调用 JasperGold 或任何清理脚本。

已发现的历史不匹配：add TB 访问 `dut.u_ram.mem_array`、`dut.u_cpu_core`，而本次恢复的 top 是 AXI wrapper；仅把 HEX 路径修好也不能直接运行。JasperGold 的全 CPU harness 有中断关闭等假设，不能把历史 summary 当完整 ISA/中断验证。本轮不偷偷重写 TB 或让空壳 RAM 通过测试。

V01 后续应记录每个 TB 的兼容性、命令、版本、结果与必要的显式适配；模块与系统级验证分开。本轮恢复 RTL 的 top elaboration 与 tb_bypass（7 项）、tb_regfile（15 项）功能仿真通过；命令与输出见 [验证元数据](../../build/metadata/cicc1000023_recovery_verification.json)。未宣称历史全套 TB 已通过。
