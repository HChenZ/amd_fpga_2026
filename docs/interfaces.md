# 接口契约与待定项

恢复补充（2026-09-21）：原始 XCI 已确认 PLL 50→100 MHz，BRAM 为 32×32768 words（128 KiB）、freertos_demo.coe 初始化。下文 RTL 地址/计数语义保持不变；共有 31 个 RTL 规范化换行后与当前源码一致。配置频率和历史报告不等于本轮板上实测，详见 [恢复审计](cicc1000023_recovery_audit.md)。

更新：2026-09-21。状态：**现有 RTL 静态提取，未上板验证；目标接口草案未冻结**。修改相关实现前先读本文件，变更需同步测试与上下游说明。

## 现有 CPU/存储/MMIO

源：`src/rtl/defines.v`、`if_stage.v`、`bus_interconnect.v`、`top.v`、`top_pl_bram.v`。

| 项 | 当前代码值 / 语义 |
|---|---|
| XLEN | 默认 32，参数化 64；尚无本轮 RV64 回归证据 |
| 复位 PC | `0x10000000` |
| memory decode | `cpu_addr[31:20] == 0x100`；窗口不等于物理容量 |
| BRAM | wrapper 基址 `0x10000000`，默认 32768 words；原始 XCI 已确认 32-bit × 32768 words = 128 KiB |
| CLINT | `0x12000000` 窗口；+0x0000 msip，+0x4000/+0x4004 mtimecmp，+0xbff8/+0xbffc mtime；分半值主要对应 RV32 |
| UART | `0x20000000`；+0x00 status，+0x04 RX/TX data，+0x08 control；数据/控制位查 `uart_ctrl.v`，读 FIFO 有副作用 |
| GPIO | `0x20010000`；+0x00 LED control/状态，+0x04 锁存 button event（读清） |
| CPI events | `0x60000000`；具体分配见下表 |
| AXI | `top` 暴露 AXI4 master；地址/数据宽度 XLEN，ID 1 bit，WSTRB 为 XLEN/8；burst 和 backpressure 须仿真确认 |
| 复位与时钟 | `top` 使用低有效 rst_n；wrapper 默认低有效按键，经 clock locked 与同步链释放复位；XDC 输入 20 ns，内部 100 MHz 已由原始 XCI 配置确认，实际运行待验证 |

以上是 RTL 实现地址，不是新 PYNQ register map；高位别名、未定义地址行为及有效容量在 B02/V01 测试，不假定全窗口可访问。

## cycle 与事件计数

`csr_file.v` 的 64-bit `mcycle` 在每个非复位时钟加一：RV32 CSR `0xb00` 为低 32 位、`0xb80` 为高 32 位；RV64 `0xb00` 返回完整值。当前 read case 未提供 `0xc00/0xc80` 别名，软件不应直接假定 `rdcycle` 可用；优先核验 M-mode 对 `mcycle/mcycleh` 的访问。

RV32 使用 high→low→high 读取，不一致则重试。C04 要测真实软件读数、溢出与测量边界；`mcycle` 当前写逻辑不含清零入口，采用差值而非假定可写复位。

| CPI offset | 事件 | RV32 返回 |
|---|---|---|
| 0x00 / 0x04 | `probe_inst_valid` | cnt_inst 低/高 |
| 0x08 / 0x0c | `probe_stall_ld` | cnt_stall_ld 低/高 |
| 0x10 / 0x14 | `probe_stall_md` | cnt_stall_md 低/高 |
| 0x18 / 0x1c | `probe_flush_br` | cnt_flush_br 低/高；每次事件 **加 2** |

探针由 `cpu_core.v` 输出，`soc_top.v` 连入计数器。事件可能重叠，flush 指标还有权重；**不能将事件之和作为 cycles**。CPI 如需报告，使用同一区间的 cycle delta / verified retired instruction delta。

## Ascon 软件契约（C01/C02 待冻结）

目标 key=16 bytes、nonce=16 bytes、tag=16 bytes，AD/plaintext 为显式长度字节串。C 现有 `crypto_aead_encrypt/decrypt` 在 `ascon/ascon_c/aead/aead.c`；Python `ascon_encrypt/decrypt` 在 `ascon/pyascon/ascon.py`。现有实现输出为 ciphertext 与 tag 拼接，host API 是否分拆须在 C02/Y03 约定。必须核对长度、返回码、buffer 重叠规则以及认证失败后的输出，不在本轮假定已满足。

标准、可信参考 SHA 和 KAT SHA 由 C01 给出；C03 同时验证加解密与篡改拒绝。现有 XOF 代码保留，非 P0 主线。

C02 host 契约补记（2026-10-07）：production C 位于 `ascon/ascon_c/aead/`，
锁定且不得修改的 reference 位于 `sim/ascon/reference/`。完整 16-byte tag 配置，
成功解密返回 0、`*mlen=clen-16`、输出对应明文；认证失败返回 -1、`*mlen=0`，
仅清零 `m[0..clen-16)` 的候选明文。`clen<16` 返回 -1、`*mlen=0`，不写 m。
调用者必须提供有效 mlen 指针及足够容量、无重叠的输入/输出，检查返回值后
才能使用成功输出；详见 [C API 说明](../ascon/ascon_c/aead/readme.md)。
此为项目验收要求，不把擦除行为声称为 SUPERCOP API 的强制条件。

## ISE 契约（I02 待冻结）

目前没有已分配的 Ascon custom opcode。现有 `ror/load_bytes/store_bytes` 不是 CPU 指令规范。I02 的交付应填满：指令名/编码、输入/输出寄存器、RV32 64-bit state 表示方式、状态布局、round constant、latency、stall/flush/interrupt、非法编码、clobber、软件封装、golden model、覆盖矩阵。禁止先让 RTL 与软件各自猜一个编码。

## PS/PL 命令接口（Y01 草案，禁止据此写死寄存器）

| 方向 | 所需逻辑字段 | 待定内容 |
|---|---|---|
| PS → PL | protocol_version、request_id、operation、software/ise mode、key、nonce、AD/input 长度与数据位置、output capacity、start | AXI/BRAM/mailbox 方案、地址、对齐、端序、最大长度、加载固件方式 |
| PL → PS | request_id、busy/done/error、ciphertext/tag、输出长度、64-bit cycles、实现模式 | 状态位与错误码、原子完成、ack/reset、timeout 与重试 |
| 共享 buffer | ownership、可见性与生命周期 | PS cache flush/invalidate、CPU Cache 处理、内存屏障、禁止工作中复用 |

Python 展示输入 key/nonce/AD/plaintext，读取 ciphertext/tag/cycles；认证失败与超时必须显式报错，不形成成功 benchmark。Y01 应用时保留板级参数，不向通用 Skill 硬编码 Ascon 长度或地址。

## benchmark 记录契约（拟定字段）

`schema_version, run_id, task_id, source_commit, dirty_patch_hash, timestamp, evidence_kind, board, part, xlen, clock_hz, vivado_version, compiler_version, compile_flags, firmware_hash, bitstream_hash, reference_commit, kat_hash, mode, operation, ad_bytes, message_bytes, cache_policy, interrupt_policy, measurement_scope, repetitions, raw_cycles, cycles_per_byte, code_bytes, lut, ff, bram, dsp, fmax_hz, timing_met, status, notes`。

JSON 保存原始值/结构化元数据，CSV 给出可比汇总；未测字段为 null/N/A 并说明原因。schema 正式实现由 C04/I07/Y05 维护版本，接口变更记录在 [decisions](decisions.md)。
