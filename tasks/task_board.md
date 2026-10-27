# 任务看板

更新：2026-10-18。所有 owner 为 **TBD**，仅由项目方指派。截止日期为内部计划；依赖完成是开工/验收门槛，不能用到期日替代。日期以 Asia/Shanghai 为准。

编号：B=baseline/build，C=cryptography software，I=instruction extension，V=verification，Y=PYNQ，S=skill，P=PUF/security，D=documentation/release。

status：`todo` 未开始；`ready` 输入已齐、可开始执行；`in_progress` 已有工作未验收；`blocked` 有已知阻塞；`done` 有满足验收的证据；`gated` 未获前置门禁；`deferred` 明确移出本轮。done 仅表示任务本身完成，不表示整个系统可运行。事实与失败见 [实际进度](../project_log/actual_progress.md) 和 [经验](../project_log/lessons_learned.md)。

## baseline 与标准软件（P0）

| ID | task | owner | prerequisite | deliverable | acceptance criteria | deadline | status |
|---|---|---|---|---|---|---|---|
| B01 | baseline repo audit | TBD | 无 | docs/repository_audit.md | 完整树/模块/part/生成文件/路径问题/读取范围与静态检查证据；不改原工程 | 2026-09-23 | done |
| B02 | Rebuild and verify recovered XC7Z020 CICC baseline | TBD | B01；Vivado 2025.2 环境 | 原 XPR/XCI/XDC/COE 已恢复；尚需重建入口与新报告 | 明确版本、part、top；从已恢复 XCI 再生成 IP；独立 checkout 综合/实现与基线运行证据，无本机缓存依赖 | 2026-09-27 | in_progress |
| B03 | xc7z020 board sanity check | TBD | B01；上板阶段需 B02 | target part = xc7z020clg400-1 confirmed；板型=正点原子领航者ZYNQ7020、8 端口逐引脚核验、独立工程 `board/vivado_zynq7000_xc7z020_ascon` 已上板（三套 COE 均烧录运行） | target part 已确认；核验 physical board model / revision，时钟/复位/UART/LED/存储及 PYNQ 平台；独立配置上板 | 2026-09-28 | in_progress |
| B04 | baseline firmware build/load | TBD | B01；精确 FreeRTOS kernel/bootloader 依赖 | 已恢复部分启动/链接/构建源；待重编译/加载 | clean build 固件，入口/内存匹配；加载后可报告状态和 mcycle；不依赖未入库镜像 | 2026-09-28 | blocked |
| C01 | NIST SP800-232 reference | TBD | B01 | 规范/参考版本/许可清单与可信 KAT/hash | 固定 final 标准、C/Python reference 提交；区别旧版/draft；核对 IV、端序和 KAT 来源 | 2026-09-24 | done |
| C02 | Ascon-AEAD128 software port | TBD | C01；目标固件需 B04 | 既有 ascon 目录内标准 C 移植、API/构建入口 | 加解密 API、长度/错误规则明确；host 与目标编译通过；不将已有代码直接算完成 | 2026-09-28 | done |
| C03 | KAT | TBD | C02、C01 | host 全1,089 KAT、standalone RTL接口内289 KAT及认证失败验证；target待验 | 完整锁定可信 KAT 逐字节比对；空/边界/多块/AD；篡改 tag/ciphertext 拒绝；保留失败日志 | 2026-09-29 | in_progress |
| C04 | RISC-V software benchmark | TBD | C03、B02、B03、B04、V01 | 纯软件程序、mcycle 读取、原始 CSV/JSON | 自研 CPU 上运行且 KAT 正确；64-bit cycle 可靠读取；记录 flags/频率/Cache/中断/计时范围及代码量 | 2026-09-30 | done |

## ISE 与验证（P0）

| ID | task | owner | prerequisite | deliverable | acceptance criteria | deadline | status |
|---|---|---|---|---|---|---|---|
| I01 | hotspot analysis | TBD | C04 | permutation hotspot 与候选指令分析 | 基于真实周期/反汇编给出瓶颈、RV32 状态布局、预期收益与资源代价；估算独立标记 | 2026-10-01 | done |
| I02 | custom instruction spec | TBD | I01、C01 | docs 指令 spec/encoding/semantics 与测试矩阵 | 编码无冲突；输入/输出/端序/latency/stall/flush/异常及 RV32/64 边界明确 | 2026-10-03 | in_progress |
| I03 | RTL implementation | TBD | I02 | src/rtl 中 ISE RTL 与集成清单 | 与 spec 一致，参数/复位/握手明确定义；通过 elaboration 并提交给 I04 | 2026-10-06 | in_progress |
| I04 | unit test | TBD | I03、I02、C01 | sim TestBench/golden model/覆盖与结果 | 定向/随机/边界/重置/连续请求/延迟测试通过，报告 seed 和失败复现；与最终标准 permutation 对照 | 2026-10-07 | in_progress |
| I05 | CPU integration | TBD | I04、B02、V01 | decode/execute/旁路/控制接入与集成测试 | baseline 回归通过；数据相关、stall/flush、中断/异常与 ISE 交互通过；ISE-disabled 可运行 | 2026-10-11 | in_progress |
| I06 | inline asm/intrinsic | TBD | I02；联调需 I05 | 软件封装、调用测试和反汇编/执行证据 | 不改 GCC backend；寄存器约束正确，热点实际执行对应 opcode；无静默 fallback | 2026-10-12 | done |
| I07 | software vs ISE benchmark | TBD | I05、I06、V02、C04 | 两种程序与原始 benchmark/加速比 | 同平台同条件 KAT 正确；cycles/cycles-per-byte/代码量与原始数据齐全；第一版真实加速数据 | 2026-10-14 | done |
| I08 | PPA comparison | TBD | I05、B03 | docs/ascon_ppa_comparison.md（芯片级 STA 证据）；板上 PPA 待 B03/V01 | 同工具/part/约束/策略，LUT/FF/BRAM/DSP/Fmax/时序均有证据；芯片级收敛 WNS+0.007/0 失败端点；板级 IO delay 未约束不标上板达标 | 2026-10-20 | done |
| V01 | baseline regression/counter sanity | TBD | 完整验收需 B02、B03、B04；模块测试可先行 | 修订dcache TB/独立事务/故障注入/6中断场景及完整smoke、regression均PASS；ISA/SoC/板级完整门禁待验 | 保存可重跑程序/TB/日志；mcycle 读取与溢出、计数开销已检查；支持范围明确 | 2026-09-29 | in_progress |
| V02 | software/ISE differential verification | TBD | I05、I06、C03 | ACB 套件（sw/hw/ise 同 KAT + 篡改拒绝 + stall/reset 注入）证据 data/ascon/results/key_lifecycle/*_timing_acb*.json | 两套固件均通过可信 KAT，篡改拒绝；流水 hazard/flush 场景无回归 | 2026-10-13 | done |
| V03 | PS/PL end-to-end regression | TBD | Y02、Y03、V02 | 自动板级测试/错误场景日志 | 软件/ISE 输入到输出可复现；错误 tag、超时、长度边界、重复命令、缓存可见性可检查 | 2026-10-20 | todo |
| V04 | core freeze regression | TBD | Y05、I08、V03 | 冻结回归清单与证据索引 | P0/P1 验收齐全、无未关闭阻断缺陷；冻结哈希与环境留档；不以 P2 拖延 | 2026-10-27 | todo |
| V05 | standalone Ascon AEAD RTL verification and main integration | TBD | C01；独立于CPU ISE | sim/ascon TB/runner、data/ascon/results/rtl_integration_regression.*、docs/ascon_rtl_decrypt_validation.md | 最新main上整合、远端Decrypt接口兼容；289官方KAT、篡改/超长/reset、round/P8/P12、全生产编译仿真PASS；旧工作区保留 | 2026-10-09 | done |

V06（2026-10-17复核）：安全修复/最终源码仿真PASS，两轮实现后100 MHz timing not met：WNS=-0.177ns/TNS=-2.968ns，31个setup端点失败；已停止优化。阶段性收尾可提交，板型/DRC/IO门禁仍未过。
V06 审查纠正：I02/I04/I05 的早期 done 覆盖不全。定向hold/cancel/reset与KAT已通过，
但RV64、完整异常/抢占上下文、ISE-disabled和全部baseline门禁尚未验收，保持in_progress。
C04/I07既有done仅代表所记录的RTL仿真性能，不代表板上验收。

| ID | task | owner | prerequisite | deliverable | acceptance criteria | deadline | status |
|---|---|---|---|---|---|---|---|
| V06 | Ascon key lifecycle/security and pre-board review | TBD | latest main三种实现、C01 | docs/ascon_key_management.md、key_lifecycle证据、独立Vivado入口 | KAT/动态Key/认证失败保护/ZEROIZE/ISE交互、可复现构建；板级风险独立记录 | 2026-10-16 | in_progress |
| V07 | Ross and engineering Skills compatibility assessment | TBD | V06 stable checkpoint | docs/ross_and_engineering_skills_evaluation.md、双轴审查与安装证据 | 官方版本/权限/依赖核验；有限只读review；Ross下载阻塞与未测项明确，不改工程 | 2026-10-17 | done |
| V09 | A/C/B timing path repair and dual-strategy validation | TBD | V08 fix_r1 工作区及路由快照；用户授权 A→C→B | docs/timing_acb_validation.md、ISA/CPU 原始证据、双策略 STA | 已完成：8项整机/5单元/生命周期通过，ISA49/50与控制一致；两策略WNS+0.001/+0.007、TNS0、失败端点0；板级IO/DRC不在完成范围 | 2026-10-20 | done |
| V10 | Prune obsolete artifacts and verify cleanup equivalence | TBD | 用户确认最终双策略 RPT 保留及删除后重跑 | docs/workspace_cleanup.md、build/metadata/cleanup_20261018.json、cleanup_v10_verification.json | 数据复验已一致：8项CPU镜像/周期、单元/安全、ISA及231文件hash相同；6个旧路径被并行恢复，用户确认暂保留，最终留存收口待并行结束 | TBD | blocked |

## PYNQ 与通用 Skill（P1）

| ID | task | owner | prerequisite | deliverable | acceptance criteria | deadline | status |
|---|---|---|---|---|---|---|---|
| Y01 | Zynq PS/PL interface design | TBD | B03、B04；C02 API | 版本化 register/mailbox/buffer 协议 | 控制路径、firmware loading、地址/端序/长度、所有权/一致性、cycle/status/error/timeout 明确，双方可据此实现 | 2026-10-08 | todo |
| Y02 | PYNQ overlay | TBD | Y01、I05、B02 | Tcl/IP 配置、overlay 发布清单与 hash | 在已核验 image/板卡上加载，bit/hwh 匹配；PS 可控制 CPU，干净构建可生成 | 2026-10-17 | todo |
| Y03 | Python host API | TBD | Y01、C03；联调需 Y02 | Python API、golden checker、测试 | 输入 key/nonce/AD/plaintext，返回 ciphertext/tag/cycles，错误显式；匹配锁定 C/Python reference | 2026-10-18 | todo |
| Y04 | Jupyter demo | TBD | Y02、Y03、I07 | 可从头执行 notebook 与说明 | 重启后顺序执行，展示软件/ISE 正确性与加速比，区分 CPU 与端到端计时 | 2026-10-20 | todo |
| Y05 | automatic benchmark/report | TBD | Y04、V03、I07、I08 | 自动 KAT/benchmark/report 入口和原始数据 | 同次运行可生成结果、失败返回非成功状态；软件/ISE 对比可追溯、无手填性能值 | 2026-10-21 | todo |
| S01 | generic overlay loader | TBD | Y02 | skill 通用 loader | 板型/overlay 路径参数化，校验 bit/hwh/版本，给出适用与失效条件 | 2026-10-21 | todo |
| S02 | register map helper | TBD | Y01、Y03 | skill 寄存器访问 helper | 地址/位宽/端序由配置提供，读写与边界测试通过，不硬编码 Ascon | 2026-10-21 | todo |
| S03 | golden reference checker | TBD | C03、Y03 | skill 可注入 golden checker | 算法作为 callback/适配器，报告首个差异与失败；用非 Ascon 示例验证 | 2026-10-21 | todo |
| S04 | performance/report collector | TBD | Y05、I08 | skill 数据收集与报告工具 | schema/指标可配置，缺失与估算明确，使用非 Ascon 数据示例验证 | 2026-10-21 | todo |
| S05 | PYNQ skill README | TBD | S01、S02、S03、S04 | skill 使用/边界/案例/来源说明 | 陌生使用者按说明运行通用示例；P1 验收版随 M05，11-01 完成提交材料整理 | 2026-10-21 | todo |

## 可选安全原型（P2）

以下日期仅在 P0/P1 全稳定、前述 09-23～10-21 节点达标且 Skill 核心交付稳定时有效；否则直接 deferred，不延期主线。

| ID | task | owner | prerequisite | deliverable | acceptance criteria | deadline | status |
|---|---|---|---|---|---|---|---|
| P01 | RO PUF prototype | TBD | B02/B03/C04/I04/I07/I08/Y05/V03、S01-S05 与 P0/P1 门禁通过 | 独立 RO PUF RTL/约束/观测记录 | 综合/实现后结构保留，有真实响应，异常与限制记录完整 | 2026-10-23（条件节点） | gated |
| P02 | stability measurement | TBD | P01 | 多次上电/温度/电压响应与统计 | 预先声明采样和阈值，报告 BER/失败率，不能只选成功样本 | 2026-10-24（条件节点） | gated |
| P03 | key reconstruction | TBD | P02 | enrollment/reconstruction 与 helper data 方案 | 多次重建/失败处理实测，密钥不入日志；可靠性阈值达标 | 2026-10-26（条件节点） | gated |
| P04 | authenticated boot prototype | TBD | P03、C03、V02 | Ascon 镜像认证/完整性原型 | 正确镜像允许、修改镜像拒绝；说明信任边界和回滚限制；冻结前未验收即延期 | 2026-10-27（条件节点） | gated |

## 文档与发布

| ID | task | owner | prerequisite | deliverable | acceptance criteria | deadline | status |
|---|---|---|---|---|---|---|---|
| D00 | repository collaboration skeleton | TBD | B01 | README/AGENTS/docs/tasks/project_log/目录说明/.gitignore | 请求的入口齐全、任务字段完整、链接可用、原工程未变、忽略规则保留证据 | 2026-09-23 | done |
| D01 | architecture figure | TBD | B01；定稿需 I02/Y01 | 架构图与版本说明 | 当前/计划分开；最终图与 CPU/PS/PL 实现一致，报告可引用 | 2026-10-29 | in_progress |
| D02 | benchmark tables | TBD | I07、I08、Y05、V04 | 对比表与数据来源索引 | 每个数值追溯原始结果，测试条件一致，未测项明确 | 2026-10-30 | todo |
| D03 | report | TBD | D01、D02、V04、S01-S04 | 报告、PPT、LLM 协作记录 | 原理/创新/对比/失败与复现材料齐全，规则/来源可追溯，无虚构成果 | 2026-11-01 | todo |
| D04 | demo video | TBD | Y04、Y05、V04 | 演示视频与脚本/文件 hash 索引 | 真实目标板上输入输出、KAT 和两模式指标一致，关键过程可辨识 | 2026-11-01 | todo |
| D05 | clean-clone reproduction | TBD | B02、B03、B04、V04、D03、D04、S05 | 干净机器/clone 的端到端日志 | 无开发机缓存/IP/绝对路径依赖，重新构建并运行 KAT/benchmark/demo；材料引用有效 | 2026-11-02 | todo |
| D06 | final package | TBD | D05、D03、D04、S05 | 最终清单/许可证/哈希/材料包 | 11-03 只修材料并核对包；11-04 仅正式提交，由用户控制提交动作 | 2026-11-03 | todo |

2026-10-15：C02 目标编译/运行已在仿真层达成（done）；C04 CPU 级软件 benchmark 完成
（done，仿真层，非上板）：自研 RV32IM CPU 运行锁定生产 Ascon-AEAD128，6 组官方 KAT +
篡改拒绝 PASS，mcycle/CPI 实测 enc16B=16840、enc32B=21018、dec16B=17226、dec32B=21461 cycles，
code=38852 B。C03 目标 KAT 为 6 组代表向量（全 1,089 仍仅 host）。板级(B02/B03)、ISE、
Vivado/PPA 未做。I03/I04 仍指真正的 custom instruction，未因软件/独立AEAD完成而标 done。

另：Ascon MMIO 加速器（ascon_mmio + ascon_aead_core + bus/soc_top 接线）已接入并在 CPU 上
通过 KAT（详见 actual_progress 2026-10-15）：16B 纯 crypto 99 cyc、完整 MMIO 往返 544 cyc，
对软件 16840 cyc 约 170×/31×。这是软件→ISE 之间的第一级硬件加速。

2026-10-15：ISE（Ascon 置换 custom instruction，custom-0 opcode 0x0B）已实现并测试通过——
ascon_ise.v + id/ex_stage 译码执行与多周期 stall；inline asm(.insn) 封装；4 组官方 KAT +
解密往返 + 篡改拒绝 PASS；反汇编确认 142 条 opcode 0x0B 真编码；warm 16B 加密 1880 cyc（vs
软件 16840 ≈ 9×）。I03/I06/I07 已达标（RTL 实现、inline asm、benchmark）；I01/I02/I04/I05
主体完成，剩余：随机/边界/复位单元测试、baseline 全回归重跑、ISE-disabled 模式与中断/异常
/flush 交互、正式 spec 文档，这些待补后才能真正标 done。I08(PPA) 需 Vivado 综合，未做。

2026-10-09：C01已锁定并重验；C03 host/RTL子项通过，目标CPU尚未验；V05已在
最新main基点0a425f9隔离整合并重新验证，保留tag_in/tag/correct原15端口。
下一步首选 B02/B03/B04/V01，完成CPU baseline、target KAT/mcycle后C04→I01/I02；
B04仍缺准确kernel/bootloader源与运行证据；B02/V01部分进展不等于完整验收。

2026-10-27 上板复核（三套固件全部跑通）：板型=正点原子领航者 ZYNQ7020，part `xc7z020clg400-1`，
100 MHz，独立工程 `board/vivado_zynq7000_xc7z020_ascon`（手工新建，Vivado 2025.2，
Performance_ExploreWithRemap），三份 bitstream 全部 **WNS +0.087 / TNS 0 / 0 失败端点 / DRC 0 Error**：
sw `f4233827…`、ise `f85eb1a6…`、hw `2f6f2469…`。三份都通过 KAT（含篡改拒绝；hw 另有 16B 长度拒绝）。
板上 warm 16B 加密：**软件 20806 cyc（1.0×）→ MMIO 688 cyc 端到端（30.2×，裸 crypto 103 cyc）→
ISE 2570 cyc（8.10×）**，同 RTL 同编译器仿真对照为 17353 / 670 / 2496，
板上分别 +19.9% / +2.7% / +3.0%（开销 ∝ 访存密度，已在 actual_progress 记录解释）。
状态调整：B03 blocked→in_progress（PYNQ 平台与镜像仍缺、芯片丝印速度等级未核）；
B04 的"固件加载链"已由 Ascon 三套实证，但 baseline FreeRTOS 固件仍缺 kernel/bootloader 源；
C03/V01 的**板上**部分已补齐，完整的 1,089 KAT 与 ISA 板上抽样仍未做。证据见
`project_log/actual_progress.md` 2026-10-26/27 条目、`first_time.runs/{synth_1,impl_1}` 报告、
`build/local/board_bitstream/*.bit`（不入 git）、`data/ascon/results/board/`。
