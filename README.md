# RISC-V Ascon SoC — PUF3

当前工程采用 RV32 五级流水线 CPU，集成 Ascon-AEAD128 的软件、MMIO、定制指令三条路径，
并在同一 PUF3 overlay 中提供 RO-PUF/Device DNA 密钥通路。本文只描述架构与已验证结果，不作未经核实的独占原创或安全性声明。

## 三分钟找到项目

| 想了解什么 | 入口 |
|---|---|
| **项目总看板、当前/历史与交付清单** | [项目看板](project_board.md) |
| 当前 PUF3 工程 | [board 工程入口](board/readme.md) |
| 板上操作 | [PUF3 Notebook](src/pynq_puf3/readme.md) |
| 当前源码/构建依赖 | [源码说明](src/readme.md)、[构建说明](build/readme.md) |
| 独立 Skill | [Skill](skill/readme.md) |
| 技术报告、海报与材料状态 | [材料入口](report/readme.md) |
| 独立历史工程 | [archive/history](archive/history/README.md) |
| 原始测试/实现证据 | [archive/evidence](archive/evidence/README.md) |
| 三类交付的分别压缩 | [delivery](delivery/README.md) |

当前目录只放 PUF3、其共享依赖和维护文档；独立 DMA/PUF v2/MIN、原型和旧工具集中隔离。
历史源码的旧相对路径属于当时布局，不应直接当成当前构建命令；物理原件与 Git 历史保留，不改写失败为通过。

## 当前版本身份与实测范围

- 器件：正点原子领航者 ZYNQ7020，`xc7z020clg400-1`；Vivado 2025.2；top `pynq_puf3_wrapper`。
- 控制身份 **PQF3=0x33465150**，固件 **pynq-svc-puf3**；bit/hwh/固件配套位于 PUF3 candidate。
- 主采样：`data/pynq_puf3/notebook_20261031_114512/result.json`，三模式各289/289 KAT与289次坏Tag拒绝。
- KAT #529，PT16B/AD0，HWKEY关闭，预热5次/采样30次：加密 **21862/1369/3895 cycles**，HW/ISE为 **15.969×/5.613×**；
  解密22562/1213/4288，**18.600×/5.262×**。CPU周期不含PS/UART，墙钟另列。
- LUT18674/FF32002/BRAM34.5/DSP4；已约束路径WNS+0.104 ns，DRC0 Error/0 Critical；**RO计数器域未签核**。
- PUF只有会话内注册127/128、重建5/5、HWKEY切换与KAT恢复证据；跨上电/PVT/BER/熵/唯一性未测，诊断量可读。
- 旧v1的9/9错误门禁与Skill L3 Ascon不是PUF3完整错误矩阵；完整RV64/异常抢占、clean-clone等不冒充已验收。

交付为源码/Skill/报告，不再生成“证据包”作为比赛附件；仓库仍保存可追溯的原始记录归档。
源码、物理工件、历史记录、说明与交付ZIP的版本各自独立，以看板及交付清单定位。
