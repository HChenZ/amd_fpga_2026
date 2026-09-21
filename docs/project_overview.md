# 项目概览

更新：2026-09-21。比赛与目标时间按用户本轮要求建档；未独立确认的官方规则不作推断。

## 背景与目标

CICC1000023 已提供自研 RISC-V CPU 基础，本项目继续扩展，不重造 CPU。以 NIST SP 800-232 的 Ascon-AEAD128 为唯一主线 AEAD 标准，在 XC7Z020CLG400-1 上比较纯软件与 custom ISE，使用 Zynq PS/PYNQ 作控制和展示层。芯片型号不等于开发板型号，实物板卡及 image 待 B03 确认。

## 优先级与完成定义

| 级别 | 范围 | 完成证据 |
|---|---|---|
| P0 | baseline 复现；标准软件和可信 KAT；RISC-V 运行与 mcycle；permutation 热点分析；ISE spec/RTL/TestBench/decode/execute；inline asm/intrinsic；软件与 ISE 对比 | 同一输入集 KAT、有效/无效 tag 测试；两种程序的反汇编、执行与原始周期记录；cycles、cycles/byte、代码量、LUT/FF/BRAM/DSP/Fmax；可重建脚本 |
| P1 | PS 经 AXI/shared BRAM/mailbox 控制 PL CPU；Python 输入 key/nonce/AD/plaintext，返回 ciphertext/tag/cycles；黄金参考比对、Jupyter、自动报告、通用 Skill | 目标板独立启动并运行 demo；软件与 ISE 自动测试/计时；二者输出一致且匹配锁定的可信参考；Skill 在非 Ascon 示例上验证 |
| P2 | RO PUF、enrollment/reconstruction/stability、PUF-derived key、镜像认证/完整性原型 | P0/P1 全部稳定后有条件立项；提供可靠性和失败数据；不宣称完整安全启动链 |

P2 不影响核心交付日期。任何 P0/P1 回归或 10-21 节点未达到，P2 保持 `gated`；冻结前来不及验证则 `deferred`。

## 当前事实与待定事项

已有 CPU 和 Ascon 源码；Git HEAD 的 Kintex 工程保留。原始比赛 ZIP 中已找到 XC7Z020 XPR、3 个 IP、XDC/COE、固件/测试及历史报告，真实 baseline 已选择恢复到工作区但未提交。`top` elaboration 及两个模块 TB 已通过；Vivado/固件/板级复现仍待完成。FreeRTOS kernel 与 bootloader 源不在本次归档中，不能把其余已找到资料继续称作不存在。见 [恢复审计](cicc1000023_recovery_audit.md)。

待定：B03 的板卡身份/DDR/时钟/引脚/PYNQ image；C01 的参考提交与 KAT 哈希；I02 的指令粒度/编码/延迟；Y01 的共享内存协议；全部人员 owner。第一期默认围绕现有 RV32 配置评估，RV64 保留能力，切换须单独回归。

## 工程交付边界

- baseline 源码保留原字节；Kintex 已经授权 rename 为唯一 legacy 入口；`ascon/` 作为既有软件目录，README 建立映射。
- docs 管规范，tasks 管任务与日期，project_log 管发生过的事实和证据。
- 原始测量与 KAT 放 data，构建脚本和精选报告放 build，上板入口放 board，材料放 report。
- 最终复现覆盖 source→firmware/IP→bitstream/overlay→KAT→benchmark→报告，不仅是能打开 XPR。

入口：[审计](repository_audit.md)、[任务](../tasks/task_board.md)、[节点](../tasks/milestones.md)。
