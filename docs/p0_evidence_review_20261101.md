# P0 未验收项的现有证据复核

日期：2026-11-01；owner TBD。范围：复核既有数据、测试源码、日志与任务验收条件，不运行新的硬件/仿真/综合流程。
这不是把历史运行重新标为当前源码通过，也不修改原始结果或放宽验收标准。

> 同日版本审计补充：[全部版本清单](version_inventory_20261101.md)发现独立 CPU-DMA 实验已有 SW/ISE 各 1089 组
> 目标 CPU 仿真；本表中“目标侧完整 1089 未测”仅适用于当前 PUF3/Y01 发布路径，不是全仓库均无此证据。
> 两个版本的接口、源集、固件与物理候选不同，不能互相转记验收。

## 结论

此前答复把“11 个任务状态不是 done”近似成“11 项未验证”，判读不准确。
当前 RV32 / PT、AD 各 ≤16 B / bare-metal 交付链已有实现、功能仿真、标准 KAT、实现报告和实板证据。
主要缺口是原始 CICC baseline 的独立复现，以及超出当前交付边界的完整 ISA/非法编码/异常抢占/RV64 矩阵。
不能因此把所有原始大任务标 done；也不能再把已通过的子项说成未测。

## 逐项复核

| 任务 | 已有证据与已完成范围 | 实际尚未闭合的部分 |
|---|---|---|
| B02 原 baseline 重建 | 原 XPR/XCI/XDC/COE 和资产已恢复；以恢复工程为基础、替换为开发 RTL 的审查工程已综合/实现；Ascon/PYNQ/PUF3 工程都有构建结果 | 没有证明“未混入开发 RTL 的原始 baseline，在独立 checkout 无本机缓存依赖下重建并运行”。不能说项目从未构建过，也不能拿 PUF3 成功代替原 baseline 复现 |
| B03 板卡核验 | 正点原子领航者 ZYNQ7020 已运行；8 个 PL 端口静态核验；冻结记录有底板 V3.9/核心板 2V5；PYNQ 2.7.0、Python 3.8.2 与内核有实板记录；PUF3 FCLK0 寄存器推导 99.999999 MHz、mcycle/PS 时基估测 99.9723 MHz | 芯片完整丝印与 -1/-2 速度等级等实物证据仍待补。板级真实 IO 延迟未测；不能把“尚无示波器/Fmax测量”写成“完全没核对频率” |
| B04 原 baseline 固件 | Ascon 三套裸机固件和 pynq-svc-puf3 的编译、ELF/BIN/COE、BRAM 初始化、启动及实板 mcycle 已有证据；PUF3 固件构建 7 个步骤 exit 0 | 原 FreeRTOS baseline 所需准确 kernel 来源/版本、原 CoreMark bootloader 源码/构建链未闭合；不是所有项目固件都没编译、没加载 |
| C03 KAT | host 完整 1089 组；独立 RTL 接口内 289 组及篡改测试；10-31 PUF3 SW/HW/ISE 各 289/289 KAT、289/289 错 Tag 拒绝，原件与 candidate 哈希绑定；另有 CPU-DMA 实验的 SW/ISE 各 1089 组目标仿真 | 超过 16 B 接口的 800 组未在当前 PUF3 板端 ABI 跑，不是失败；CPU-DMA 的全量 CPU 仿真不能当成 PUF3 全量板测。看板的 target待验 已过时 |
| I02 指令规范 | docs/ascon_key_management.md §ISE 现行约定和生命周期、docs/interfaces.md、最终报告 §2.3.3.4/附录已有 custom-0/funct 字段、10×32-bit 布局、非法索引、hold/ack/cancel/清零和中断取消约定；明确没有上下文保存恢复 ABI | 保留 opcode/funct 编码空间与全局非法指令陷阱审计未完成；完整 RV64/抢占恢复语义和测试未闭合。不是“没有规范”或“flush 行为完全没写” |
| I03 RTL 实现 | ascon_ise + decode/execute/旁路控制已实现；当前 ISE XSim 1502/0，PUF3 固件包含 22 条静态 custom-0 编码；完整候选已实现且实板 SW/MMIO/ISE 标准 KAT 通过 | 当前 RV32 实现本体已有可验收依据；与原任务捆绑的完整 I02/I05 门禁不应重复算作一项“缺 RTL” |
| I04 单元测试 | 置换源数据 6 组边界/定向状态 + 16 组固定 seed 伪随机状态（0x800232）；P8/P12 各 22 个输入，共 44 次，ISE TB 1502 检查；覆盖非法索引、busy 写忽略、模式锁存、跨完成 hold、阻止重入、ack、cancel、运行中 reset、私有副本清零；10-31 XSim PASS | 不声称所有时序组合、完整编码空间和全覆盖率闭合。旧 Icarus 结果属于当时源码；当前 XSim 单元源哈希已单独核验。此前“缺随机/边界/复位/seed”错误 |
| I05 CPU 集成 | 旧 ACB 八项 SW/HW/ISE/security/stall/reset 集成运行 PASS；EX 集成 TB 有中断 cancel、hold、被取消写不提交；后续真实 CPU+CLINT 六场景中断/handler/mret；当前 PUF3 固件+AXI-Lite+UART 行为协同仿真 54 步 PASS、自动锁钥反例被检出，实板通过三模式 KAT | 六场景不是完整 ISE AEAD 抢占恢复；嵌套/优先级/全部异常、保留编码、RV64、ISE-disabled 硬件配置与原 baseline 全门禁未找到完整验收证据。纯 SW 模式通过不等于 ISE-disabled 配置通过 |
| V01 baseline/计数回归 | RV32I/M 已重跑 50 个恢复测试体，49 PASS、ma_data 1 FAIL；Cache 有四固定 seed 逐拍差分、独立事务/故障注入；CPU+真实 CLINT 六个接受/handler/mret 场景；10-28 regression 为 15 PASS/0 FAIL/0 BLOCKED/1 NOT_RUN，后续板测另有证据 | ma_data 是控制组同样失败的非对齐访存能力差异，不改为 PASS；完整特权/SoC/异常/RV64 与板上 ISA 回归未闭合。不能说“没做 CPU 回归” |
| V06 密钥生命周期/上板前审查 | 旧生命周期仿真 MMIO 13212/0、ISE 1502/0，动态 Key、篡改拒绝、显式 ZEROIZE 与取消测试已有；10-17 负 WNS 后，V09、PL-only、PYNQ v1、PUF3 后续实现与实板已提供更晚证据；当前 PUF3 候选已约束路径 WNS +0.104、DRC 0 Error/0 Critical，HWKEY 切换与恢复实板 PASS | 旧安全测试不能不比源码直接当成当前 PUF3 全套重测；PUF3 RO 域仍未签核，完整错误门禁未重跑，调试可读。HW 驱动不每次发送 ZEROIZE 是契约/边界，不说明 RTL ZEROIZE 从未验证。V06 不能仍仅以 10-17 时序失败为当前结论 |
| V10 清理等价性 | cleanup_v10_verification.json 的八项整机、生命周期、单元、ISA 前后数据一致，231 个保留文件哈希一致；源码未因清理改变 | overall FAIL 来自被删除路径重新出现，用户决定保留。是文件留存收口，非未做功能验证；不抹除原始 FAIL |

## 本次直接核对的原件

- `data/ascon/permutation_cases.json`、`sim/ascon/freeze_vectors.py`：seed=0x800232，22 个状态、308 条 round/P8/P12 向量；P8/P12 各 22 条。
- `sim/ascon/tb_key_ise.v` 与 `data/ascon/results/ise_screenshot_20261031/{summary.json,simulate.log}`：1502 checks、0 errors、37390 ns finish。
  summary 记录的 8 个源/配置/向量哈希与当前工作区逐字节全部一致。
- `docs/ascon_key_management.md` §83–100：现行 RV32 编码、布局、非法索引、握手、取消和明确未测的上下文恢复边界。
- `data/ascon/results/key_lifecycle/{key_rtl_timing_acb.json,cpu_units_timing_acb.json}` 与对应日志：MMIO 13212/0、ISE 1502/0、EX 11/0、CPU 单元 5/5。
  这些是 10-18 源快照的测试；比对发现部分当前文件哈希已变化，不据此宣称全套当前 PUF3 生命周期已重跑。
- `data/ascon/results/timing_acb_functional_summary.json`：八项整机等 checks 全 true；regression_gate=true、full_isa_pass=false。
- `data/ascon/results/isa/timing_acb/summary.json`：50 项，唯一 FAIL 为 rv32ui_ma_data；控制组结果见 `isa/fix_r1_control/`。
- `board/atk_navigator_7020/{validation_evidence.json,validation_followup.md}`：六场景真实 CLINT 中断与 mret，以及四 seed Cache 差分；中断 TB/CPU/CLINT/CSR 的哈希与当前一致。
  总体 46 个记录输入 41 个 raw/LF 匹配，5 个已改变，保留历史来源边界，不宣称最新完整 SoC 重跑。
- `build/reports/pynq_final_20261028/regression_final/summary.json`：15 PASS、0 FAIL、0 BLOCKED、1 NOT_RUN，唯一 NOT_RUN 为当时板测。
- `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/{manifest.json,reports/cosim_summary.json,reports/firmware_build.json}`：
  当前生产输入 56 个（按报告核对脚本相同过滤条件）全部 raw/LF 哈希匹配；行为协同仿真 54 步 PASS；固件构建 7 步 exit 0、custom-0=22。
  RO/DNA 在协同仿真中为行为模型，不能由此代替物理 PUF 验证。
- `data/pynq_puf3/notebook_20261031_114512/result.json`：PASS/exit 0、simulated=false、三模式各 289/289 + 坏 Tag 289/289；
  bit/hwh/manifest 与 candidate 三项哈希逐项相同；时基估测 99.9723 MHz。
- `docs/freeze_checkpoint_20261027.md` §1：记录底板 V3.9/核心板 2V5；不是“完全没有板卡 revision 记录”。
- `submission/freeze_manifest.json`：11-01 18:39 已生成冻结留档，源码提交 92159b9；status=PASS 只表示该留档脚本的检查通过，不等于 P0 全部验收。

## 如何解释剩余工作

1. 已验证但看板陈旧：I03 实现本体、I04 已列定向/固定随机测试、C03 当前容量内板测、B03 PYNQ与时基核验、V04 冻结留档子项。
2. 已验证一部分、宽泛验收未关：I02/I05/V01/V06/B03。必须把实际未覆盖的子项单列，避免重复统计成多个“功能没做”。
3. 旧路线尚未完整复现：B02/B04 的原 CICC/FreeRTOS/bootloader，不是当前 PUF3 演示不能运行。
4. 已执行但没全绿：ISA 的 ma_data、V10 文件留存检查。FAIL 不等于 NOT_RUN。
5. 范围之外仍未测：完整 RV64/特权异常/ISE 抢占上下文恢复、ISE-disabled 配置、当前 PUF3 路径的全 1089 目标侧 KAT；
   PUF3 完整错误恢复矩阵、RO 计数器时序与跨上电/PVT/BER 等。当前实板成功不能覆盖这些项。

本轮不自动修改旧任务为 done，不重新生成证据包，不 commit/push；后续若收口看板，应先拆清现行 RV32 交付与历史广范围验收。
