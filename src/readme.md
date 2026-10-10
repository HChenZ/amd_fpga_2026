# 设计源码

现有 `rtl/` 是 CPU/SoC baseline，保持目录、文件名和工程引用。已有软件保持在 `../ascon/`，不为目录整齐迁移。`rtl/ascon/` 的standalone加解密与round/P8/P12已通过独立黄金回归；尚未完成CPU ISE，接口与边界见[RTL说明](rtl/ascon/readme.md)。

修改前读 [interfaces](../docs/interfaces.md) 与 [technical_rules](../docs/technical_rules.md)。I02/I03/I05 交付 spec、RTL 与回归；10-07 单测、10-14 首版集成结果，10-27 功能冻结。普通新增文件用小写英文路径。

源配置入库；生成 RTL/IP 输出回到构建流程生成，不能在这里伪造缺失 IP。

已恢复 [CICC1000023 固件源](firmware/cicc1000023/readme.md)：CoreMark RV32/RV64、FreeRTOS 应用、RISC-V tests。原始文件名映射与哈希受控，构建前在 ignored 工作副本还原；尚缺精确 kernel/bootloader 依赖。
