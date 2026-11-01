# 仿真与验证

更新：2026-11-01。先按对象选择入口，不把全仓所有回归称为 PUF3：

| 目录 | 对象 |
|---|---|
| [pynq_puf3](pynq_puf3/readme.md) | **PUF3 专用** RV32 固件 + mailbox/PUF 协同仿真与 autolock 反例 |
| [ascon](ascon/readme.md) | host/独立 RTL/单元与早期 CPU 自测；默认 CPU runner 已有缺依赖问题，见该页警告 |
| `pynq/`、[board](board/readme.md) | 旧 v1/rtl_p0 与通用板前工具，不是 PUF3 全回归 |
| [pynq_dma_cpu](pynq_dma_cpu/readme.md)、[ascon_dma](ascon_dma/readme.md) | 独立 CPU-DMA / HW_DIRECT 实验；全量目标 CPU 仿真不转记到 PUF3 |
| `keys/`、[keys_v2](keys_v2/readme.md)、[puf_soc_v2](puf_soc_v2/readme.md)、[puf_min](puf_min/readme.md) | 旧 PUF v1 或独立 v2/MIN；物理候选状态与行为仿真状态分别记录 |
| [cicc1000023](cicc1000023/readme.md) | 原始模块/ISA/formal 资产 |

完整范围与已知缺口见 [版本入口](../docs/version_entrypoints.md)。以下恢复/计划说明为早期背景，不能覆盖后续结果。

[CICC1000023 原始验证源](cicc1000023/readme.md) 已选择恢复：21 个模块 TB、2 个 ISA add 示例、43 个 formal 源/脚本。恢复 RTL 的 top elaboration 与 bypass/regfile 两个模块仿真通过；不是完整 CPU 回归。旧 ISA TB 层次、HEX 路径与正式验证假设须显式适配/审查。

B02/V01 后续交 baseline ISA/外设/Cache/AXI/中断/counter sanity，I04/V02 交 ISE 定向/随机/流水交互与最终标准 KAT，V03 交 PS/PL 端到端。每次留命令、版本、seed、退出码、通过/失败和证据路径，日期/依赖见 [任务看板](../tasks/task_board.md)。

临时波形/编译放 ignored build/local、sim/waves、sim/tmp；精选文本结果放受控目录，KAT/benchmark 数据放 data。模块仿真、全系统仿真、板级测试分别记录。
