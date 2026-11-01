# 板级工程与运行

更新：2026-11-01。`board/` 现有 **11 个工程家族 + 1 个板卡资料目录**。
先读 [版本入口速查](../docs/version_entrypoints.md)；下表“历史/实验”不表示可以删除，
PUF3 仍复用旧目录中的 IP/启动支持。本次只更新说明，不改程序默认行为或工件。

| 入口 | 角色 |
|---|---|
| [vivado_zynq7000_xc7z020_pynq_puf3](vivado_zynq7000_xc7z020_pynq_puf3/readme.md) | **当前主演示**：PQF3 / pynq-svc-puf3，三模式 + PUF v1；板测入口 `src/pynq_puf3/pynq_puf3_board_test.ipynb` |
| [vivado_zynq7000_xc7z020_pynq](vivado_zynq7000_xc7z020_pynq/readme.md) | **旧 PYNQ v1**：无 PUF，pynq-svc-v1；历史 benchmark/9项错误门禁与 Skill L3 对象，不是 PUF3 |
| [vivado_zynq7000_xc7z020_pynq_puf](vivado_zynq7000_xc7z020_pynq_puf/readme.md) | 旧 PUF-only overlay：PFU1，keys_rv32 ASCII 自检；不提供三模式服务 |
| [vivado_zynq7000_xc7z020_pynq_dma_cpu](vivado_zynq7000_xc7z020_pynq_dma_cpu/readme.md) | 独立 CPU-DMA 实验，最终候选 80 MHz、离线验证，未板测 |
| [vivado_zynq7000_xc7z020_dma_direct](vivado_zynq7000_xc7z020_dma_direct/readme.md) | 无 RV32 的 HW_DIRECT 多块 DMA 实验，不作主演示，未板测 |
| [vivado_zynq7000_xc7z020_axi_dma_loopback](vivado_zynq7000_xc7z020_axi_dma_loopback/readme.md) | **Skill L3 非 Ascon 回环工件**，不是 PUF3 的 DMA 功能 |
| [vivado_zynq7000_xc7z020_puf_v2](vivado_zynq7000_xc7z020_puf_v2/readme.md) | 独立 PUF v2；旧 candidate 已 INVALID，禁止上板，不能替换 PUF3 |
| [vivado_zynq7000_xc7z020_puf_min](vivado_zynq7000_xc7z020_puf_min/readme.md) | 独立最小 PUF 探索，PS 做注册/重建/密码，无 RV32，不作主演示 |
| [vivado_zynq7000_xc7z020_baseline](vivado_zynq7000_xc7z020_baseline/readme.md) | 真正的 CICC1000023 XC7Z020 baseline；B02 的重建验证入口，XPR/XCI/XDC/COE/imports 已恢复 |
| [vivado_zynq7000_xc7z020_ascon](vivado_zynq7000_xc7z020_ascon/readme.md) | **历史 PL-only/JTAG 上板**：三套 COE/bit，之后有 keys3 阶段；PUF3 复用其 AXI BRAM/blk_mem_gen XCI，不可整目录删除 |
| [vivado_kintex7_legacy](vivado_kintex7_legacy/readme.md) | 原 tracked Kintex 工程经 git mv 归并的唯一历史入口；仍缺三个 IP，不作为目标板构建入口 |
| [atk_navigator_7020](atk_navigator_7020/readme.md) | 板卡资料与交接，**不是 Vivado 工程**；文中镜像缺失等 pending 是当时快照，后来 PYNQ/PUF3 已上板 |

foundation 收口逐文件比较后移出未跟踪副本，再 git mv 原工程；原路径不再存在。baseline 的 XPR/XDC 字节未修改，相对引用仍有效。两项旧 .cache/.hw 生成元数据已清理。

baseline 目录只包含 37 个源/配置资产和 readme，未放入 bitstream/DCP/runs/cache/临时日志/批量 ELF/HEX；历史报告另存 build/reports/cicc1000023_archive。详见 [收口检查](../docs/repository_foundation_closeout.md) 与 [恢复审计](../docs/cicc1000023_recovery_audit.md)。

## 当前 PUF3 入口

- 使用 `vivado_zynq7000_xc7z020_pynq_puf3/candidate/` 下同批 bit/hwh/固件与 manifest；PQF3=0x33465150。
- 10-31 原始结果：`data/pynq_puf3/notebook_20261031_114512/result.json`；三模式各 289 KAT/坏 Tag 拒绝。
- PUF3 构建明确替换 `soc_top.v` 与 `key_mmio.v`；不直接用 src/rtl/soc_top.v 的自动锁钥旧实现。
- 发布/报告以 `submission/current_evidence.json` 为准。PUF3 只有会话内 PUF 功能证据，RO 域未签核。

## 历史上板事实（2026-10-27，非 PUF3）

- 板卡：正点原子 领航者 ZYNQ7020（底板 V3.9 / 核心板 2V5），`xc7z020clg400-1`，12V DC，JTAG 下载（ATK-U18 / FT232H），USB-UART CH340
- 独立工程 [vivado_zynq7000_xc7z020_ascon](vivado_zynq7000_xc7z020_ascon/readme.md)：综合 `Vivado Synthesis Defaults` + 实现 `Performance_ExploreWithRemap`，三轮均 **WNS +0.087 ns / TNS 0 / 0 失败端点 / DRC 0 Error**
- 板上 warm 16B 加密：软件 **20806 cyc** → ISE **2570 cyc（8.10×）** → MMIO **688 cyc（30.2×）**；三套 KAT 全 PASS
- 证据索引见 [上板冻结检查点](../docs/freeze_checkpoint_20261027.md)

10-27 当时 pending：IO delay、板上 ISA、PS7/PYNQ 镜像、丝印速度等级。
后续 PYNQ/PUF3 已上板，IO 约束覆盖另有变体；真实 IO 延迟与完整丝印/速度等级等边界仍未闭合。
