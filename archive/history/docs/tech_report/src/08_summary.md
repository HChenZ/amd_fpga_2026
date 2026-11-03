## 9 总结与交付边界

### 9.1 完成度与判据矩阵

| 工作项 | 当前状态 | 证据与边界 |
|---|---|---|
| RV32 平台与三方案运行 | 已有实板证据 | 当前 pynq-svc-v1 在同一 overlay 下切换 SW/HW/ISE |
| Final 标准一致性（host） | 1089 组通过 | 完整 host 结果不等于完整板级结果 |
| 当前板级容量内 KAT | 三模式各 289/289 | PT/AD 各 0–16 B，错误 Tag 各 289/289 |
| 当前 warm benchmark | 已执行 | KAT #529、预热 5 次、每档 30 次，原始 cycles 与墙钟齐全 |
| Notebook 从头顺序执行 | 已有运行结果 | warm benchmark 已执行本体尚未归档；不能写成未执行 |
| 板级错误恢复 | 9/9 checks PASS | 7/7 reset 恢复，每次三模式 KAT 通过 |
| 连续请求 | 已验证有限次数 | 每模式 50 次加密与 50 次解密；非小时级验证 |
| 当前实现时序 / DRC | 已有报告 | WNS +0.034 ns、TNS 0、DRC 0 Error/0 Critical；Warning 非零 |
| 独立 RO-PUF/DNA 原型 | 已实现并有一次板级自检通过 | v3 quality=128/128，同次重建状态通过；非 PYNQ release，见扩展原型章节 |
| 完整 1089 组板测 | NOT_RUN | 800 组超接口容量；本稿不承诺全量板级支持 |
| 板上 ISA 抽样 | NOT_RUN | 历史仿真 49/50，ma_data 因非对齐访存失败；不称全套 ISA 通过 |
| RV64、完整异常与抢占矩阵 | 未验收 | 不作为当前 RV32 bare-metal 演示的已验证能力 |
| 小时级资源泄漏与冷启动重复性 | not_measured | 无 RSS/FD 长时曲线，不以有限次数请求替代 |
| 独立 FCLK 与完整实物取证 | 部分缺失 | 已有正面照片；芯片完整丝印、跳线与 SD 镜像等仍待归档 |
| 实际交付 Skill | rtl-design-discipline 与 pynq-overlay-workflow 已成形 | 后者工具层 47 项测试、13/13 变异检出通过；智能体对照与实板未运行，不称效果已验证（见 §2.5.3） |
| clean-clone / 最终包 | 未完成 | 已能使用 release 不等于已在干净环境端到端重建 |

### 9.2 本轮收口顺序

首先固定当前 release 身份与测试范围，使每项结果对应工件、原始输入、测量边界与记录日期。
按项目方 2026-10-29 最新安排，11 月 1 日提交并冻结；10 月 30 日先验证实际交付 Skill，
随后整理实物与镜像说明、已执行 Notebook、报告/PPT/实板视频，10 月 31 日核验发布包与演示。
长时稳定性、独立频率及额外跨平台/通用性实验为非阻塞后续项，未做则保留未测标注。
完整 clean-clone 若未完成也如实记录，不用包哈希校验代替源码重建。
功能扩展须另行立项，在已有版本可复现之后评估，不列为本轮成果或必须兑现的功能承诺。

### 9.3 心得体会

实现可运行与结论可复核是不同目标。标准 KAT、真实 CPU 仿真与实板测试各自覆盖不同问题，
不能用某一层通过替代另一层验收；相同文件名也不能证明工件属于同一构建。
因此，发布身份、逐文件哈希、source_dirty 和源集选择应与原始样本一并保存。

性能比较首先是测量边界的比较。当前固定 16 B 输入下 MMIO 与 ISE 均降低了固件调用周期，
但 PS 侧调用仍包含 Python 与通信开销，响应时间没有获得同倍数改善。
保留这一区别，比仅展示最大的周期加速比更有解释力。

验证框架同样需要负向用例。错误长度、过期 epoch、重复请求及 FIFO overflow 的拒绝与恢复，
为演示链的健壮性提供了有限但可复查的证据；它们不构成无限时稳定性、完整 ISA 合规或安全认证证明。
报告应保留已知失败与未测项，不以文字更新代替工程验证。

## 附录 A 术语与缩写 {.unnumbered}

| 缩写 | 全称与含义 |
|---|---|
| AEAD | Authenticated Encryption with Associated Data，认证加密 |
| AD | Associated Data，关联数据 |
| ISE | Instruction Set Extension，本文的状态读写与置换定制指令 |
| MMIO | Memory-Mapped I/O，存储器映射访问 |
| KAT | Known-Answer Test，已知答案测试 |
| WNS / TNS | Worst Negative Slack / Total Negative Slack |
| WHS / THS | Worst Hold Slack / Total Hold Slack |
| DRC | Design Rule Check |
| COE | BRAM 初值文件 |
| mcycle | RV32 的 64-bit 周期来源，CSR 0xB00/0xB80 |
| warm | 经过预热的执行状态，不等于首次调用或长期平均 |

## 附录 B 地址映射与指令编码 {.unnumbered}

### B.1 SoC 地址映射

| 窗口 | 基址 | 从设备 |
|---|---|---|
| MEM | 0x10000000 | 128 KiB AXI BRAM，统一代码数据空间 |
| CLINT | 0x12000000 | 定时器与软件中断 |
| UART | 0x20000000 | 当前 mailbox 的 RV32 uncached MMIO 端 |
| GPIO | 0x20010000 | LED 与按键事件 |
| ASCON | 0x30000000 | 当前 rtl_p0/ascon_mmio 的 AEAD 寄存器 |
| CPI | 0x60000000 | 指令与停顿等事件，不能相加替代总周期 |

### B.2 定制指令编码

主操作码 custom-0=0x0B、funct7=0；funct3=0/1/2/3 分别为 ascon.w/ascon.rd/ascon.p12/ascon.p8。
状态共 10 个 32-bit 字，按 s0 低/高至 s4 低/高排列；非法索引读零、写忽略。
索引取自寄存器值而非寄存器编号；具体接口与取消边界见 §3.4，不声称完整非法编码空间已验收。

### B.3 MMIO 加速器寄存器

当前寄存器为 CTRL(0x00)、STATUS(0x04)、ADLEN(0x08)、MLEN(0x0C)、KEY(0x10–1C)、
NONCE(0x20–2C)、TAGIN(0x30–3C)、AD_WDATA(0x40)、MSG_WDATA(0x44)、OUT_RDATA(0x48)、
TAGOUT(0x4C–58)。当前交付采用调用者写入的测试 key，具体规则见 §3.3。

### B.4 PYNQ AXI-Lite 窗口

| 窗口 | PS 基址 | 功能 |
|---|---|---|
| CONTROL | 0x40000000（4 KiB） | 复位、按键控制、LED/复位状态、ID、VERSION |
| MAILBOX | 0x40001000（4 KiB） | 字节 TX/RX FIFO、状态、overflow、计数、ID |

地址由当前 HWH 校验；不是 RV32 本地 MMIO 地址。详细定义见 §8.2。

## 附录 C 证据索引 {.unnumbered}

证据按版本与验证层级分组。`evidence/build_evidence.py` 自动生成工件哈希、原始报告摘录与
当前板测复算结果；缺文件或哈希不一致应返回失败，不用旧摘要填补。

| 结论 | 主要证据 |
|---|---|
| 当前 release 身份 | `board/vivado_zynq7000_xc7z020_pynq/release/manifest.json`、`sha256sums.txt` |
| 当前时序 / DRC / 资源 | `build/reports/pynq_final_20261028/` 的 timing.rpt、drc.rpt、utilization.rpt |
| 容量内 KAT | `data/pynq/board_20261028/pynq_board_full.json` |
| 当前 warm benchmark | `data/pynq/notebook_20261029_130920/` 的 identity、smoke、benchmark JSON/log |
| 错误恢复与执行 Notebook | `data/pynq/error_gate_20261029_134023/` |
| host 标准验证 | `data/ascon/results/host_validation.json`、`reference_gate.json` |
| 生产 C 认证失败契约 | `data/ascon/results/failure_contract.json` |
| 历史 PL-only 周期 | `data/ascon/results/board/uart_20261026_sw_and_ise.txt`、`uart_20261027_mmio.txt` |
| 历史 PL-only 实现 | `build/local/proj_backup_first_time_20261027/first_time.runs/impl_1/`，本地备份，不保证随 clone 可用 |
| 仿真回归 | `build/reports/pynq_final_20261028/smoke/summary.json`、`regression_final/summary.json` |
| 33 策略记录 | `data/ascon/results/strategy_sweep_20261017/strategy_sweep_summary.json` |
| 实物正面照片 | `docs/tech_report/figs/board_photo.jpg`；不据照片推断拍摄时运行镜像或芯片速度等级 |
| 独立 RO-PUF 原型 | `data/ascon/results/board/uart_20261027_keys3.txt`；`src/rtl/keys/`；`src/firmware/keys_rv32/main.c` |

本地备份与未跟踪报告不是远程仓库可访问性保证。提交前须提供实际材料快照及对应证据包，并验证链接与文件。

## 附录 D 参考文献 {.unnumbered}

1. NIST, *Ascon-Based Lightweight Cryptography Standards for Constrained Devices*, SP 800-232, Aug. 2025. DOI: 10.6028/NIST.SP.800-232.
2. C. Dobraunig et al., “Ascon v1.2: Lightweight Authenticated Encryption and Hashing,” *Journal of Cryptographic Engineering*, 2021（背景，不作 Final 向量来源）.
3. Ascon C reference implementation, `ascon/ascon-c`, commit `446347f2`，`crypto_aead/asconaead128/ref/`，CC0-1.0.
4. M. Meichlseder, *pyascon*, commit `ed24e54a`（锁定第二参考，Final 一致性由 KAT 验证）.
5. RISC-V International, *The RISC-V Instruction Set Manual*, Volumes I and II.
6. AMD/Xilinx, *Zynq-7000 SoC Technical Reference Manual*, UG585.
7. AMD/Xilinx, *Vivado Design Suite User Guide: Implementation*, UG904.
8. AMD/Xilinx, *Vivado Design Suite User Guide: Using Constraints*, UG903.
9. AMD/Xilinx, *Vivado Design Suite User Guide: Design Analysis and Closure Techniques*, UG906.
10. 全国大学生嵌入式芯片与系统设计竞赛 2026 FPGA 创新设计赛道《选题指南（AMD 自主选题初级组）》（比赛名称以实际报名及可追溯原件为准）.
