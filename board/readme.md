# 板级工程与运行

board 下有三个工程目录 + 一个板卡资料目录：

| 入口 | 角色 |
|---|---|
| [vivado_zynq7000_xc7z020_baseline](vivado_zynq7000_xc7z020_baseline/readme.md) | 真正的 CICC1000023 XC7Z020 baseline；B02 的重建验证入口，XPR/XCI/XDC/COE/imports 已恢复 |
| [vivado_zynq7000_xc7z020_ascon](vivado_zynq7000_xc7z020_ascon/readme.md) | **上板工程（2026-10-27 起）**：当前 `src/rtl` + `src/rtl/ascon` 的独立工程，三套 COE（sw/ise/hw）已实测通过，WNS +0.087 ns |
| [vivado_kintex7_legacy](vivado_kintex7_legacy/readme.md) | 原 tracked Kintex 工程经 git mv 归并的唯一历史入口；仍缺三个 IP，不作为目标板构建入口 |
| [atk_navigator_7020](atk_navigator_7020/readme.md) | 板卡资料与交接（厂家 XDC/引脚核验、P5 串口跳线、PYNQ 镜像缺口），**不是 Vivado 工程** |

foundation 收口逐文件比较后移出未跟踪副本，再 git mv 原工程；原路径不再存在。baseline 的 XPR/XDC 字节未修改，相对引用仍有效。两项旧 .cache/.hw 生成元数据已清理。

baseline 目录只包含 37 个源/配置资产和 readme，未放入 bitstream/DCP/runs/cache/临时日志/批量 ELF/HEX；历史报告另存 build/reports/cicc1000023_archive。详见 [收口检查](../docs/repository_foundation_closeout.md) 与 [恢复审计](../docs/cicc1000023_recovery_audit.md)。

## 当前上板事实（2026-10-27）

- 板卡：正点原子 领航者 ZYNQ7020（底板 V3.9 / 核心板 2V5），`xc7z020clg400-1`，12V DC，JTAG 下载（ATK-U18 / FT232H），USB-UART CH340
- 独立工程 [vivado_zynq7000_xc7z020_ascon](vivado_zynq7000_xc7z020_ascon/readme.md)：综合 `Vivado Synthesis Defaults` + 实现 `Performance_ExploreWithRemap`，三轮均 **WNS +0.087 ns / TNS 0 / 0 失败端点 / DRC 0 Error**
- 板上 warm 16B 加密：软件 **20806 cyc** → ISE **2570 cyc（8.10×）** → MMIO **688 cyc（30.2×）**；三套 KAT 全 PASS
- 证据索引见 [上板冻结检查点](../docs/freeze_checkpoint_20261027.md)

仍 pending：IO delay 未约束、板上 ISA 抽样、PS7/PYNQ 链路（厂家镜像缺失）、芯片丝印速度等级未现场核对。
