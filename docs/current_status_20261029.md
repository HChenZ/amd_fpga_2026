# 当前状态（2026-10-31）

owner TBD。本文件是当前状态索引；发生事实以 `project_log/actual_progress.md`
为准，任务字段以 `tasks/task_board.md` 为准。历史计划文档保留原文并标注历史边界。

## 结论

核心 PYNQ 演示链已完成并有实板证据；独立 PUF3 变体新增单次上电功能证据，但项目任务尚未全部关闭：

- 已完成：NIST Final 标准/KAT、host 软件、CPU 上 SW/MMIO/ISE、PPA/时序证据、
  PYNQ overlay、Python API、Notebook、warm benchmark、容量内 KAT 和 V03 错误恢复门禁；
  `pynq-overlay-workflow` 已完成 L1、L2（simulated）和 L3 四段实板功能验证。
- 新增：PUF3 实板 SW/HW/ISE 各 289/289 容量内 KAT 与坏 Tag 拒绝；enroll quality
  127、5 次 reconstruct 稳定、HWKEY 开关及标准 KAT 恢复通过。
- 未完成：B03 实物证据、原始 CICC baseline 全复现、完整 RV32/RV64 与异常矩阵、
  Skill S04 report/collector 非 Ascon 示例、S05 独立复现/证据包、D01-D06 材料与 clean-clone。
- P2/PUF 仍为 `gated`；PUF3 证据限于单次上电功能，跨电源周期/可靠性/RO timing
  signoff 未测，在 P0/P1 未完整收口时不应宣称 P2 或安全启动完成。

## 最新实板证据

| 证据 | 结果 |
|---|---|
| 三模式容量内 KAT | SW/HW/ISE 各 289/289，错误 Tag 各 289/289 |
| PUF3 完整容量内 KAT | SW/HW/ISE 各 289/289，错误 Tag 各 289/289；结果见 [result.json](../data/pynq_puf3/notebook_20261030_144328/result.json) |
| Skill L3 | session `l3_20261031_063709` 四段 PASS；59 checks PASS、1 NOT_APPLICABLE、0 FAIL |
| PUF3 时钟 | SLCR 推算 99.999999 MHz；mcycle 实测 99.9971 MHz；PYNQ 2.7 显示 150 MHz 不作为实测值 |
| PUF3 PUF 流程 | enroll quality 127；5 次 reconstruct 稳定；HWKEY 开关、caller key 拒绝和关闭后 KAT 恢复通过 |
| Notebook smoke | SW/HW/ISE 各 6/6，错误 Tag 各 6/6 |
| warm benchmark KAT #529，16B/AD=0 | HW 加密 16.221×、解密 17.295×；ISE 加密 5.843×、解密 5.474× |
| V03 错误/恢复门禁 | 9/9 checks PASS，7/7 次 reset/epoch 恢复，三模式 KAT 每次恢复通过 |
| 连续请求 | 每模式 50 次加密+50 次解密，全部通过 |

详细结果与文件哈希见
[PYNQ validation 20261029](../board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md)。

## 未完成项

| 类别 | 任务 | 剩余工作 |
|---|---|---|
| baseline | B02/B03/B04 | 原 XC7Z020 baseline 独立重建；板卡完整实物证据；FreeRTOS kernel/bootloader |
| ISE | I02-I05、V01 | 完整 spec、RV64、异常/中断/flush、baseline 全回归 |
| KAT | C03 | 项目板端/接口 KAT 总数为 289 组；PUF3 独立变体已通过全部 289 组，不将超出当前接口的多块能力混入板端 KAT 结论 |
| PUF | P01-P04/P05 | PUF3 单次上电功能通过；跨电源周期、温度/BER/熵/唯一性、RO timing signoff 仍未测 |
| 接口 | Y01 | 当前 UART mailbox v1 已实板验收；动态固件 loader 不在当前实现范围 |
| Skill | S01-S05 | L1 PASS；L2（simulated）主指标 `with` 1.000 vs `without` 0.833（p=0.0425），`with` vs `placebo` p=0.2248 不显著，T5 未复现；L3 session `l3_20261031_063709` PASS（preflight/Ascon/GPIO/DMA）。S01–S03 可收口；S04 非 Ascon report collector、S05 独立复现与证据包仍待完成 |
| 材料 | D01-D06 | 架构图、benchmark 表、报告/PPT、视频、clean-clone、最终包 |

## 当前优先顺序

1. 完成 B03 实物照片、完整丝印/速度等级、SD 镜像与写卡、跳线和独立频率证据。
2. 收口 S04/S05 通用 Skill。当前状态：S01–S03、L1/L2/L3 已完成；L3 四段实板 PASS。
   下一步补 S04 非 Ascon report/collector 示例、S05 独立复现与归档；不要把 simulated
   结果写成板级通过。
3. 基于已有 JSON 完成 D02 benchmark 表和 D01 架构定稿。
4. 完成 D03 报告/PPT/LLM 记录、D04 视频。
5. 执行 D05 干净 clone、D06 最终包核验。

V10 清理项仍为 blocked，不影响当前功能主链。P01-P04 不应占用提交前窗口。
