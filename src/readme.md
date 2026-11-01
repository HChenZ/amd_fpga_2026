# 设计源码

更新：2026-11-01。`rtl/` 是公共 CPU/SoC 与密码源，保持目录、文件名和工程引用；当前 RV32 ISE 已有仿真/实现/实板证据，
不是“尚未完成 ISE”。独立 AEAD、公共 RTL、应用固件和板端入口不是同一个版本概念。
已有算法软件保持在 `../ascon/`，不为目录整齐迁移。

| 路径 | 当前职责 |
|---|---|
| [pynq_puf3](pynq_puf3/readme.md) | 当前 PUF3 板测 Notebook，内嵌 PQF3 驱动 |
| [pynq](pynq/readme.md) | 公共 API/协议/参考与旧 v1 CLI；不是整个目录都为 PUF3 |
| [firmware](firmware/readme.md) | PUF3 固件、共享支持、旧自测、DMA/PUF v2 与原始资产分开 |
| [rtl](rtl/readme.md) | 公共源与应用变体选择；PUF3 的两个变体实际在 board 下 |

完整选择见 [版本入口](../docs/version_entrypoints.md)。下文日期为原历史规则，不重新启动开发。

修改前读 [interfaces](../docs/interfaces.md) 与 [technical_rules](../docs/technical_rules.md)。I02/I03/I05 交付 spec、RTL 与回归；10-07 单测、10-14 首版集成结果，10-27 功能冻结。普通新增文件用小写英文路径。

源配置入库；生成 RTL/IP 输出回到构建流程生成，不能在这里伪造缺失 IP。

已恢复 [CICC1000023 固件源](firmware/cicc1000023/readme.md)：CoreMark RV32/RV64、FreeRTOS 应用、RISC-V tests。原始文件名映射与哈希受控，构建前在 ignored 工作副本还原；尚缺精确 kernel/bootloader 依赖。

## 2026-10-16 key lifecycle review

The 10-16 [review](../docs/ascon_key_management.md) records lifecycle/handshake evidence for its source snapshot.
Its unknown-board/no-programming statement is historical; current PUF3 evidence and remaining gaps are linked above.
