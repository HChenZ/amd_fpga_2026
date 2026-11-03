# 项目概览

当前仓库布局已按2026-11-02交付整理：PUF3及共享依赖留根目录，独立历史源码在archive/history，
原始记录在archive/evidence。先从project_board.md与delivery/README.md导航，下面阶段性计划不自动成为新授权。

更新：2026-11-01。比赛与目标时间按用户本轮要求建档；未独立确认的官方规则不作推断。

## 当前状态摘要

当前/旧入口明确分责，见 [版本速查](version_entrypoints.md)；本页描述当前状态，不意味着所有程序已改成PUF3。
原baseline与独立实验的历史范围保留，说明更新不重新证明它们或回写已发布包。

- 最终报告（`report/technical/amd_fpga_2026_latex_final/`，PDF 已入库）以 **PUF3 overlay** 为主演示：
  同一 bitstream 集成 SW/MMIO/ISE 三模式与 RO-PUF/DNA 硬件密钥通路；PYNQ v1 release 作历史对照。
- P0 核心功能已有实板证据：NIST Final software、SW/MMIO/ISE、容量内 KAT、错误 Tag、
  mcycle benchmark、PPA/时序报告。
- P1 主链已有实板证据：overlay、AXI-Lite/UART mailbox、Python API、Notebook、benchmark；
  V03 错误/恢复门禁 9/9 仅在 PYNQ v1（pynq-svc-v1）上通过，PUF3 未完整重跑。
- 通用 Skill S01–S05 已 done（L1/L2/L3）。
- P0/P1 仍未全部关闭：B03 实物证据、原 CICC baseline、完整 RV32/RV64/异常矩阵、clean-clone（D05）。
- PUF3 的 PUF 部分只有会话内功能证据，不等于 PUF 稳定性、保密性或安全启动验收。

当前提交状态见 [release_plan_20261101](../../tasks/release_plan_20261101.md)、
[submission/README](../../submission/README.md) 与 [task_board](../../tasks/task_board.md)；
[current_status_20261029](../../archive/history/docs/current_status_20261029.md) 为历史快照。

## 背景与目标

CPU采用RV32五级流水线结构，集成NIST SP 800-232 Final Ascon-AEAD128软件、MMIO与定制指令路径，在XC7Z020平台由PS/PYNQ控制与展示。当前板型为正点原子领航者ZYNQ7020，完整芯片丝印/速度等级等未测边界保留。

## 优先级与完成定义

| 级别 | 范围 | 完成证据 |
|---|---|---|
| P0 | baseline 复现；标准软件和可信 KAT；RISC-V 运行与 mcycle；permutation 热点分析；ISE spec/RTL/TestBench/decode/execute；inline asm/intrinsic；软件与 ISE 对比 | 同一输入集 KAT、有效/无效 tag 测试；两种程序的反汇编、执行与原始周期记录；cycles、cycles/byte、代码量、LUT/FF/BRAM/DSP/Fmax；可重建脚本 |
| P1 | PS 经 AXI-Lite/UART mailbox 控制 PL CPU；Python 输入 key/nonce/AD/plaintext，返回 ciphertext/tag/cycles；黄金参考比对、Jupyter、自动报告、通用 Skill | 目标板独立启动并运行 demo；软件与 ISE 自动测试/计时；二者输出一致且匹配锁定的可信参考；Skill 在非 Ascon 示例上验证 |
| P2 | RO PUF、enrollment/reconstruction/stability、PUF-derived key、镜像认证/完整性原型 | P0/P1 全部稳定后有条件立项；提供可靠性和失败数据；不宣称完整安全启动链 |

P2 不影响核心交付日期。任何 P0/P1 回归或 10-21 节点未达到，P2 保持 `gated`；冻结前来不及验证则 `deferred`。

## 当前事实与待定事项

主演示 PUF3 overlay（`pynq_puf3_wrapper`，控制 ID PQF3，固件 `pynq-svc-puf3`）FCLK0 配置 100 MHz，
2026-10-31 在目标板完成三模式各 289/289 容量内 KAT 与坏 Tag 拒绝、KAT #529 30 次 benchmark
（加密 21862/1369/3895 cycles，15.969×/5.613×；解密 22562/1213/4288，18.600×/5.262×）以及会话内
PUF enroll（127/128）/reconstruct×5/HWKEY 流程；原始结果见
[result.json](../../data/pynq_puf3/notebook_20261031_114512/result.json)。资源 LUT 18674/FF 32002/BRAM 34.5/DSP 4，
已约束路径 WNS +0.104 ns。跨电源周期、温度/BER/熵/唯一性和 RO 计数器域时序签核仍为 `not_measured`。

历史对照 PYNQ v1 release 使用独立 `pynq_wrapper`、PS7 GP0 两个 AXI-Lite 窗口和 AXI-Lite FIFO ↔ RV32
UART mailbox；10-31 重测 KAT #529 benchmark（23342/1439/3995）与 9/9 错误/恢复门禁，原始数据在
`data/pynq/notebook_20261031_112052/` 与 `data/pynq/error_gate_20261031_112812/`；
[validation_20261029](../../archive/history/board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md) 为旧v1首测记录。

原始 CICC XC7Z020 baseline 仍与 PYNQ release 分开。B04 仍缺准确 FreeRTOS
kernel/bootloader 来源；RV32/RV64 完整回归、板上 ISA 抽样和 800 组超 16B 容量 KAT
仍不能宣称通过。

待定/未完成：B03完整实物证据、实机视频（D04）、clean-clone（D05）、原宽范围冻结验收与人工提交。
冻结留档已于11-01 18:39生成；留档脚本PASS不等于原P0/P1宽范围全部验收。
全部人员 owner 仍为 TBD。

## 工程交付边界

- baseline 源码保留原字节；Kintex 已经授权 rename 为唯一 legacy 入口；`ascon/` 作为既有软件目录，README 建立映射。
- docs 管规范，tasks 管任务与日期，project_log 管发生过的事实和证据。
- 原始测量与 KAT 放 data，构建脚本和精选报告放 build，上板入口放 board，材料放 report。
- 最终复现覆盖 source→firmware/IP→bitstream/overlay→KAT→benchmark→报告，不仅是能打开 XPR。

入口：[当前看板](../../project_board.md)、[任务](../../tasks/task_board.md)、[历史节点](../../archive/history/tasks/milestones.md)。
