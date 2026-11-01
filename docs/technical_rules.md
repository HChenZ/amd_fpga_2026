# 技术约定

更新：2026-09-21。本文件规定工程验收条件；不代替官方比赛规则。

2026-11-01 版本说明：本页测量/验证纪律继续适用，带“本轮/当前本地标记”的初期事实按其日期解读。
现行主演示是 PUF3；v1/原baseline/独立实验的验收不跨版本转记，入口见 version_entrypoints.md。
本轮只澄清说明，不放宽既有测试标准、不改程序或锁定参考。

## 标准与参考实现

- 主线算法为 **Ascon-AEAD128 / NIST SP 800-232 final**。使用 [NIST 最终发布页](https://csrc.nist.gov/pubs/sp/800/232/final) 为规范入口；不得把旧 Ascon-128/Ascon-128a 的向量直接当最终标准向量。
- [ascon-c](https://github.com/ascon/ascon-c) 与 [pyascon](https://github.com/meichlseder/pyascon) 为候选可信参考。C01 必须锁定提交、文件路径、许可、下载日期和 SHA-256；本轮只查阅，不引入新的实现。
- ascon-c 上游说明标准化调整涉及字节序和 IV，且不同分支/实现可能对应不同版本。逐项核对 IV、little-endian、padding、domain separation、round 数、输入输出格式，最终以目标 KAT 判定。
- 当前本地 C 标记 `CRYPTO_VERSION=1.3.0`，Python README 引用 initial public draft；这既不能证明错误，也不能证明已通过最终标准。生成自己的 KAT 不是独立正确性证据。
- 论文 *RISC-V Instruction Set Extensions for Lightweight Symmetric Cryptography* 可作为 ISE 设计研究入口，C01/I01 记录检索到的准确版本/链接；本轮未核读论文，不声称其指令与最终标准兼容。

## baseline 与工具

保留原 RTL/XPR/XDC 字节内容；Kintex 路径已按用户授权归并到 vivado_kintex7_legacy，相对引用已核验。修复先在分支上操作源配置，不编辑 runs/cache/generated HDL。已从 ZIP 恢复真实 Zynq baseline 到独立目录；不新建空白工程替代。B02/B03 重建与回归后再评审集成。

Vivado 操作记录：实际 `version`、IP 版本、part、board part、top、时钟与 IO 约束、参数、脚本、source commit/dirty diff、报告。现有 XPR 的 `2025.2` 是历史文件元数据，不等于本机已安装或测试。工具升级单列决策，不在打开工程时默默覆盖。

固件需记录 compiler/binutils 版本、`-march`/`-mabi`/优化和 LTO 选项、启动文件、链接脚本、libc、加载方式与 ELF 哈希。现有默认 RV32 配置优先；避免依赖未验证的 A/C/F/D 等扩展。

## custom instruction 完成定义

每条指令的交付必须包括：

1. **spec / encoding / semantics**：opcode、funct 字段、操作数、结果、RV32/RV64 行为、字节序、合法输入、非法编码/异常语义。
2. **RTL test**：定向、随机、边界；组合/多周期延迟，back-to-back、数据相关、stall、flush、reset、中断/异常场景。
3. **CPU integration**：decode/execute、寄存器写回、旁路、长延迟握手；关掉 ISE 的 baseline 可回归。
4. **software test**：inline asm/intrinsic，明确寄存器约束、clobber、volatile 与 memory 顺序；必要时使用 `.insn` 或编码封装。第一阶段不修改 GCC backend。
5. **KAT**：软件与 ISE 均通过锁定的最终标准向量；包含空输入、rate 边界、多块、AD、解密及篡改 tag/ciphertext 拒绝；失败不得返回可使用明文。
6. **cycle benchmark**：保留反汇编和执行 trace/计数等证据，证明热点实际执行自定义 opcode，不因优化被删或落回纯软件。

## 测量纪律

| 项 | 要求 |
|---|---|
| 周期 | `mcycle` 差值；RV32 高低高一致读取；测试读计数器开销，记录是否扣除及方法；不得用 CPI 事件相加估算总周期 |
| 输入条件 | 相同 key/nonce/AD/plaintext、长度矩阵、加/解密方向、调用次数、验证边界；测试公开固定 key 可以入库，真实密钥不可 |
| 平台条件 | 同 part/板卡/频率、XLEN、内存布局、Cache 冷/热状态、中断策略、编译选项；差异必须列出 |
| 指标 | cycles；cycles/byte = cycles / plaintext bytes（长度 0 为 N/A）；speedup = software cycles / ISE cycles；ELF `.text` 和总体代码量定义一致 |
| PPA | LUT/FF/BRAM/DSP，约束频率、实现 timing summary/WNS/TNS；Fmax 给出可复现推导或频率扫描方法，不直接把时钟名当 Fmax |
| 数据证据 | 每次原始值、重复次数、统计方法、异常/失败样本、KAT hash、硬件/固件/source hash 与版本；不只保存均值截图 |
| 分类 | `hardware_measured`、`simulation`、`implementation_report`、`estimate`、`not_measured` 分列；未测数值用空值及原因，不写 0 |

## PYNQ 与冻结

日期覆盖（2026-10-29 用户授权）：本轮提交和冻结统一为 **2026-11-01**，下文 10-27/10-28/11-04
是旧计划。提交前允许必要缺陷修复和交付工具编写，变更须验证；额外可靠性与通用性实验不阻塞。

Y01 明确数据缓存一致性、内存屏障、buffer 生命周期、长度检查、命令/完成/错误、timeout/reset、版本握手和 cycle 宽度。PYNQ image 必须匹配实际板级平台，不能只看 XC7Z020 芯片。

P0/P1 稳定前不将 PUF/认证启动纳入主线。10-27 功能冻结，10-28 code freeze；之后仅必要缺陷修复且附回归记录，11-03 只修材料，11-04 不开发。日期来源见 [milestones](../tasks/milestones.md)。
（2026-11-01 更新：按 10-29 授权改为 11-01 提交并冻结；最终报告以集成 PUF 密钥通路的 PUF3 overlay 为主演示，
PUF 仅有会话内功能证据，认证启动未开展。上句为原规则，保留作记录。）

新增文件 UTF-8，普通路径小写 ASCII；保留 README.md、AGENTS.md、Git 配置标准名。已有编码问题单列修复任务，不为统一编码触碰原 RTL/XDC。
