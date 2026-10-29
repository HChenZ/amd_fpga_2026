# 当前状态（2026-10-29）

owner TBD。本文件是当前状态索引；发生事实以 `project_log/actual_progress.md`
为准，任务字段以 `tasks/task_board.md` 为准。历史计划文档保留原文并标注历史边界。

## 结论

核心 PYNQ 演示链已完成并有实板证据，但项目任务尚未全部关闭：

- 已完成：NIST Final 标准/KAT、host 软件、CPU 上 SW/MMIO/ISE、PPA/时序证据、
  PYNQ overlay、Python API、Notebook、warm benchmark、容量内 KAT 和 V03 错误恢复门禁。
- 未完成：B03 实物证据、原始 CICC baseline 全复现、完整 RV32/RV64 与异常矩阵、
  P1 通用 Skill、D01-D06 材料与 clean-clone。
- P2/PUF 仍为 `gated`；在 P0/P1 未完整收口且已过内部冻结节点时，不应继续开发。

## 最新实板证据

| 证据 | 结果 |
|---|---|
| 三模式容量内 KAT | SW/HW/ISE 各 289/289，错误 Tag 各 289/289 |
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
| KAT | C03 | 16B 容量内板端已过；800 组超容量仍未运行，不能宣称硬件 1,089 全过 |
| 接口 | Y01 | 当前 UART mailbox v1 已实板验收；动态固件 loader 不在当前实现范围 |
| Skill | S01-S05 | 通用 overlay/register/golden/collector Skill，非 Ascon 示例验证 |
| 材料 | D01-D06 | 架构图、benchmark 表、报告/PPT、视频、clean-clone、最终包 |

## 当前优先顺序

1. 完成 B03 实物照片、完整丝印/速度等级、SD 镜像与写卡、跳线和独立频率证据。
2. 完成 S01-S05 通用 Skill，并用非 Ascon 示例验证。
3. 基于已有 JSON 完成 D02 benchmark 表和 D01 架构定稿。
4. 完成 D03 报告/PPT/LLM 记录、D04 视频。
5. 执行 D05 干净 clone、D06 最终包核验。

V10 清理项仍为 blocked，不影响当前功能主链。P01-P04 不应占用提交前窗口。
