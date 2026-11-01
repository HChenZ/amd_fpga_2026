# 系统架构

更新：2026-11-01。CPU/baseline 部分更新于 2026-09-21；“目标”段保留历史设计，
其中 PYNQ/ISE 主链现已有独立实现和实板证据。最终报告主演示为 PUF3 overlay（见下），
其 Block Design 与实现截图见最终报告图 2-10/2-11。

## 2026-10-29 已实现 PYNQ 拓扑

```mermaid
flowchart LR
    Jupyter["PYNQ / Jupyter"] --> API["AsconHost / MailboxBackend"]
    API --> AXI["PS7 GP0：AXI-Lite control + byte FIFO"]
    AXI --> UART["pynq_mbox ↔ RV32 UART MMIO"]
    UART --> FW["pynq_svc：SW / MMIO / ISE"]
    FW --> Result["ciphertext/tag/status/mcycle"]
    Result --> AXI
```

PYNQ v1 release（历史对照）为 `pynq_wrapper`，FCLK0=100 MHz；control `0x4000_0000`、mailbox
`0x4000_1000`，各 4 KiB。UART 是 uncached MMIO，无 shared cacheable buffer。
Y01-Y05/V03 实板验收见
[validation_20261029](../board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md)。

**主演示 PUF3 overlay**（`pynq_puf3_wrapper`，控制 ID PQF3 `0x33465150`，固件 `pynq-svc-puf3`）
沿用上图的 control/mailbox 地址与三模式服务链，增加 RO-PUF/DNA → `key_mmio` → Ascon MMIO 的
HWKEY 密钥选择及 Y01P/Y01K PUF v1 控制面。2026-10-31 实板结果
（`data/pynq_puf3/notebook_20261031_114512/result.json`）为 SW/HW/ISE 各 289/289 KAT 与坏 Tag 拒绝，
enroll quality 127、5 次 reconstruct 稳定，关闭 HWKEY 后标准 KAT 恢复。PUF helper 为会话内数据，
跨电源周期、RO 计数器域时序和可靠性统计不在本次证据内。

## 当前结构

```mermaid
flowchart TD
    Board["top_pl_bram：原 XPR 顶层"] --> Clock["clk_wiz_0（XCI 已恢复）"]
    Board --> Top["top：AXI4 master 端口"]
    Top --> SoC["soc_top"]
    SoC --> CPU["cpu_core：IF / ID / EX / MEM / WB"]
    CPU --> Cache["icache / dcache"]
    CPU --> CSR["csr_file：trap / interrupt / mcycle"]
    Cache --> Bus["bus_interconnect"]
    Bus --> Bridge["cpu_axi_bridge → axi_master"]
    Bridge --> BRAM["axi_bram_ctrl_0 → blk_mem_gen_0（XCI 已恢复）"]
    Bus --> MMIO["UART / GPIO / CLINT / CPI events"]
```

CPU 另含 bypass、stall_ctrl、predictor、multiplier、divider 和流水寄存器。`defines.v` 默认 XLEN=32，RAM_DEPTH=32768；复位 PC 为 `0x10000000`。模块名不必等于文件名，定位见审计。

`top_pl_bram` 约定 50 MHz 输入 XDC、名为 `clk_100m` 的内部时钟及 100 MHz UART 参数；
恢复的 clock XCI 确认 PLL 的 50→100 MHz 配置，BRAM XCI 为 32×32768 words（128 KiB），
初始化为 freertos_demo.coe。该段描述原始 baseline；另有独立 PYNQ block design，
不能把 baseline 的固件/时钟结论混入 PYNQ release。

## 目标结构与分工

```mermaid
flowchart LR
    Input["key / nonce / AD / plaintext"] --> Python["PS：PYNQ Python / Jupyter"]
    Python --> Transport["Y01：AXI / shared BRAM / mailbox"]
    Transport --> Firmware["PL 自研 CPU：software-only / ISE firmware"]
    Firmware --> ISE["I02-I05：decode / execute / Ascon ISE"]
    Firmware --> Result["ciphertext / tag / mcycle delta / status"]
    Result --> Python
    Python --> Golden["锁定版本的 C / Python reference"]
    Golden --> Report["KAT / speedup / report"]
```

- **CPU/RTL**：保持原 ISA 行为；新增 ISE 的读写寄存器、latency、旁路、stall/flush 和异常契约由 I02 定案。
- **软件**：相同 AEAD API 两种实现；先通过可信 KAT 再 benchmark；不改 GCC backend。
- **PS/PL**：已有 CPU AXI master 不等于 PS 控制接口已经存在。Y01 定地址、buffer 所有权、命令状态机、加载和复位机制。
- **测量**：RISC-V mcycle 测算法，PS 端计时测端到端；二者分列，不混成同一个加速比。
- **PPA**：同 part、约束、tool/IP 版本、实现策略对比，记录时序失败和资源代价。

下方“目标结构”是历史初稿。实物 PYNQ 拓扑以上方 2026-10-29 图为准；CPU ISE 的完整
I02/I05 契约、B03 实物证据和 D01 报告定稿仍需收口。

## 上下游交接

| 上游 | 交付 | 下游 / 门槛 |
|---|---|---|
| B02/B03/B04 | 可重建板级 baseline、固件加载、内存/时钟/计数器证据 | C04、I05、Y01 |
| C01/C03 | 参考版本、KAT hash、结果、AEAD API | I01/I04、V02、Y03/S03 |
| C04/I01 | 可重复周期测量与 hotspot | I02；不能凭猜测选指令 |
| I02/I04 | 编码与语义、单测、latency/异常规范 | I05/I06 |
| I05/I06/V02 | 两套可运行程序与正确性证据 | I07/I08、Y02-Y05 |
| Y01 | 已评审接口版本和板级平台约定 | Y02/Y03、S01/S02 |
| Y05/I08 | 原始测量、资源/时序摘要、环境元数据 | D02-D05、S04/S05 |

全部 owner 留 TBD；接口当前值与待定项集中在 [interfaces](interfaces.md)。
