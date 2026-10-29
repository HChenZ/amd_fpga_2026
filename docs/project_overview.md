# 项目概览

更新：2026-10-29。比赛与目标时间按用户本轮要求建档；未独立确认的官方规则不作推断。

## 当前状态摘要

- P0 核心功能已有实板证据：NIST Final software、SW/MMIO/ISE、容量内 KAT、错误 Tag、
  mcycle benchmark、PPA/时序报告。
- P1 主链已有实板证据：overlay、AXI-Lite/UART mailbox、Python API、Notebook、
  benchmark、V03 错误/恢复门禁。
- P0/P1 仍未全部关闭：B03 实物证据、原 CICC baseline、完整 RV32/RV64/异常矩阵和
  P1 通用 Skill 仍未完成。
- D01-D06 材料、clean-clone 和最终包尚未完成。
- P2/PUF 不进入当前提交主线。

当前任务明细见 [current_status_20261029](current_status_20261029.md) 与
[task_board](../tasks/task_board.md)。

## 背景与目标

CICC1000023 已提供自研 RISC-V CPU 基础，本项目继续扩展，不重造 CPU。以 NIST SP 800-232 的 Ascon-AEAD128 为唯一主线 AEAD 标准，在 XC7Z020CLG400-1 上比较纯软件与 custom ISE，使用 Zynq PS/PYNQ 作控制和展示层。实物平台已确认运行在正点原子领航者 ZYNQ7020 上；完整丝印、速度等级、板卡 revision 和独立频率测量仍需 B03 留证。

## 优先级与完成定义

| 级别 | 范围 | 完成证据 |
|---|---|---|
| P0 | baseline 复现；标准软件和可信 KAT；RISC-V 运行与 mcycle；permutation 热点分析；ISE spec/RTL/TestBench/decode/execute；inline asm/intrinsic；软件与 ISE 对比 | 同一输入集 KAT、有效/无效 tag 测试；两种程序的反汇编、执行与原始周期记录；cycles、cycles/byte、代码量、LUT/FF/BRAM/DSP/Fmax；可重建脚本 |
| P1 | PS 经 AXI-Lite/UART mailbox 控制 PL CPU；Python 输入 key/nonce/AD/plaintext，返回 ciphertext/tag/cycles；黄金参考比对、Jupyter、自动报告、通用 Skill | 目标板独立启动并运行 demo；软件与 ISE 自动测试/计时；二者输出一致且匹配锁定的可信参考；Skill 在非 Ascon 示例上验证 |
| P2 | RO PUF、enrollment/reconstruction/stability、PUF-derived key、镜像认证/完整性原型 | P0/P1 全部稳定后有条件立项；提供可靠性和失败数据；不宣称完整安全启动链 |

P2 不影响核心交付日期。任何 P0/P1 回归或 10-21 节点未达到，P2 保持 `gated`；冻结前来不及验证则 `deferred`。

## 当前事实与待定事项

当前 PYNQ release 使用独立 `pynq_wrapper`、FCLK0 100 MHz、PS7 GP0 两个 AXI-Lite
窗口和 AXI-Lite FIFO ↔ RV32 UART mailbox。2026-10-29 完成三模式 smoke、KAT #529
30 次 warm benchmark 和 9/9 错误/恢复门禁，证据见
[validation_20261029](../board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md)。

原始 CICC XC7Z020 baseline 仍与 PYNQ release 分开。B04 仍缺准确 FreeRTOS
kernel/bootloader 来源；RV32/RV64 完整回归、板上 ISA 抽样和 800 组超 16B 容量 KAT
仍不能宣称通过。

待定/未完成：B03 完整实物证据、S01-S05 通用 Skill、D01-D06 材料与 clean-clone。
全部人员 owner 仍为 TBD。

## 工程交付边界

- baseline 源码保留原字节；Kintex 已经授权 rename 为唯一 legacy 入口；`ascon/` 作为既有软件目录，README 建立映射。
- docs 管规范，tasks 管任务与日期，project_log 管发生过的事实和证据。
- 原始测量与 KAT 放 data，构建脚本和精选报告放 build，上板入口放 board，材料放 report。
- 最终复现覆盖 source→firmware/IP→bitstream/overlay→KAT→benchmark→报告，不仅是能打开 XPR。

入口：[审计](repository_audit.md)、[任务](../tasks/task_board.md)、[节点](../tasks/milestones.md)。
