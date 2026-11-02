# 接口契约与待定项

## 2026-11-01 版本兼容边界

| 对象 | 控制身份 / 固件 | 使用入口 |
|---|---|---|
| **当前 PUF3** | PQF3=0x33465150 / pynq-svc-puf3 | src/pynq_puf3 的 Notebook 与内嵌驱动；三模式 Y01 + Y01P/Y01K |
| 旧 PYNQ v1 release | PYNQ=0x514e5950 / pynq-svc-v1 | src/pynq 的 board_demo/benchmark/error_gate 与两个板测 Notebook |
| 旧 PUF-only | PFU1=0x31554650 / keys_rv32 自检 | ASCII 自检，不是三模式服务 |
| 独立 CPU-DMA/HW_DIRECT | D01/ABI v2，独立控制窗口/能力 | DMA host/bringup，不是 UART Y01 |

这些身份互不替代，不能靠换 bit 路径或改共享 ID 绕过。旧 9/9 错误恢复与 Skill L3 Ascon 是 v1 证据，
不自动成为 PUF3 的同项验证。当前 PUF3 只有 ≤16 B 的三模式与会话内 PUF 证据，完整 RV64/异常/抢占等仍有边界。
本文下方带日期的寄存器/接口说明保留对应阶段；完整入口见 [版本速查](version_entrypoints.md)。

## 2026-10-30 PYNQ v1 实现状态（历史对照）

PYNQ v1 在当时已经有实板接口证据（以下 V03 结论不转记到 PUF3）：

- PS 两个 4 KiB AXI-Lite 窗口：control `0x4000_0000`、mailbox `0x4000_1000`，地址以
  同次导出的 HWH 为准。
- PS/PL 数据通道为 AXI-Lite byte FIFO ↔ RV32 已有 UART `0x2000_0000`，不使用
  shared BRAM；该 UART 是 uncached MMIO，所以当前 ABI 没有共享 cacheable buffer。
- 协议为 `src/pynq/mailbox_protocol.md` 中的 UART mailbox v1；请求/响应最长承载
  PT/AD 各 16 bytes。V03 已实板验证错误长度、半帧、deadline、重复 ID、错误 epoch、
  RX overflow、显式 reset/epoch 恢复和三模式 KAT。
- PYNQ 固件以 COE 作为 BRAM 初值随 bitstream 构建，不在运行时动态加载。通用动态
  firmware loader 不属于当前 ABI。

本条更新 Y01 当前实现；下文 2026-09/10 内容保留历史边界。CPU ISE 的完整 RV64、
异常/中断矩阵和 baseline 全回归仍未全部关闭。

### PUF3：当前主演示，独立于旧 release 身份

`pynq_puf3` 使用独立 overlay、`pynq-svc-puf3` 固件和 PQF3 control ID
`0x33465150`，不改变现有 PYNQ release 的 mailbox v1。服务能力仍为 SW/HW/ISE，
`max_msg=16`、`max_ad=16`；Y01P/Y01K 提供 STATUS、ENROLL、RECONSTRUCT、
HWKEY_ON/HWKEY_OFF 操作。实板结果已完成单次上电的 289 组容量内 KAT、坏 Tag
拒绝、5 次 reconstruct 和 HWKEY 开关恢复；PUF key 不可读，诊断量 REF/MASK/RAW/DNA
可读，不能据此宣称保密。跨电源周期、温度/BER/熵/唯一性和 RO timing signoff
仍为 `not_measured`，不得作为安全启动接口或最终 P2 验收。

## 2026-10-18 V09 时序修复接口增量（owner TBD）

- ISE opcode/字布局/结果/软件 ABI 不变。`ascon_ise` 的 P8/P12 私有复位控制注册化：
  cancel 当拍架构 `state` 与完成状态清零，下一拍私有 `s_reg/s_out` 清零；正常完成转 idle
  后最多两拍清除私有副本。取消期间不发布结果。接受与 `p_start` 同拍释放局部复位，
  不增加正常置换执行周期。系统复位仍可取消操作。
- `multiplier` 内部接口追加 `mul_ack` 与 `cancel`：输入寄存器 → 乘积寄存器，
  接受后下一拍乘积与 `mul_done` 有效；`mul_done`/结果保持到 `mul_ack`，cancel/reset
  取消且不完成。EX 以 `mul_done && !ex_hold` 确认退休。reset-free 数据通路只在完成有效时消费，
  不承诺 reset 后无效 `mul_result` 的数值。M 扩展编码及算术语义不变，无 multicycle XDC 例外。
- dcache 仅 cacheable load miss 走 MISS_CAPTURE；store/MMIO 直接发单拍注册请求，恢复 HEAD
  延迟。MMIO 采用原固定延迟读回（检测 T，T+1 请求/等待，T+2 数据/解除等待），
  不等待仅用于 cacheable fill 的 `bus_rdata_valid_i`。CPU/总线端口与地址映射不变。

验证与尚未验收项见 [历史V09报告](../../archive/history/docs/timing_acb_validation.md)。

2026-10-16现行增量：软件/MMIO/ISE已在RV32仿真运行。MMIO CTRL[2]为idle ZEROIZE，
BUSY写忽略、认证成功且有效长度内才允许OUT读取；ISE新增内部cancel/ack、EX hold接线，
**没有新opcode**。ISE decrypt helper新增最后一个mlen指针，失败-1/0长度并擦除候选。
当时地址、编码、端序、生命周期与局限见[历史密钥管理审查](../../archive/history/docs/ascon_key_management.md)；
下文带2026-09/10-09日期的内容保留为历史，不能据其断言CPU ISE仍未实现。

恢复阶段说明：原始XCI配置PLL 50→100 MHz，BRAM为32×32768 words（128 KiB），使用当时的COE输入。该源快照和报告现已隔离，不等于当前PUF3实测；当前源清单由PUF3专用Tcl定义。

更新快照：2026-09-21。该段描述当时状态：现有 RTL 静态提取、未上板、目标接口草案
未冻结。当前 PYNQ UART mailbox v1 与 V03 状态以上方 2026-10-29 条目为准。

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
才能使用成功输出；详见 [C API 说明](../../ascon/ascon_c/aead/readme.md)。
此为项目验收要求，不把擦除行为声称为 SUPERCOP API 的强制条件。

## ISE 契约（I02 待冻结）

2026-10-09 standalone RTL 补记（V05/C03，owner TBD）：
`ascon_aead_2.v` encrypt/decrypt 采用显式长度、little-endian128-bit数据/AD总线，
最多各16 bytes；同步低有效rst_n，一拍start，busy时忽略新请求，done为一拍。
整合保留远端decrypt原15端口：tag_in输入、tag计算输出、correct/done/busy。
clen不含tag；done && correct才是成功，按接受请求的clen读取；认证前/失败时
m=0、correct=0，有效明文长度为0。解密不新增mlen/error/result。
encrypt增加error，done && !error才是成功输出；17..31长度当拍done/error拒绝。
解密17..31长度当拍done、correct=0、m=0、tag=0拒绝。
key/nonce/tag_in须稳定至done；数据/AD与长度在start捕获。>=32长度须在缩窄端口前拒绝。
完整端口与结果保持规则见 [RTL接口](../../src/rtl/ascon/readme.md)。这些是独立AEAD
接口，不是已冻结的CPU ISE规范；CPU RTL未变。

历史阶段尚无已分配的 Ascon custom opcode；现行custom-0规范见上方2026-10-16增量。现有 `ror/load_bytes/store_bytes` 不是 CPU 指令规范。I02 的交付应填满：指令名/编码、输入/输出寄存器、RV32 64-bit state 表示方式、状态布局、round constant、latency、stall/flush/interrupt、非法编码、clobber、软件封装、golden model、覆盖矩阵。禁止先让 RTL 与软件各自猜一个编码。

## PS/PL 命令接口（Y01 当前 UART mailbox v1）

| 方向 | 字段 | 当前实现 / 边界 |
|---|---|---|
| PS → PL | protocol_version、request_id、operation、mode、key、nonce、AD/input、output capacity | little-endian 内联帧；当前 PT/AD 各 ≤16B；单客户端/单槽 |
| PL → PS | request_id、status/error、ciphertext/tag、输出长度、64-bit `mcycle`、mode | `Y01R` 帧；非 OK 无 payload/cycles；V03 已验证拒绝与恢复 |
| 会话 | epoch、ACK/reset | 非零递增 epoch；超时后必须 `recover()`，不自动重试；V03 已验证 |
| 共享 buffer | ownership/可见性 | `NOT_APPLICABLE`：当前 UART uncached MMIO，无 shared cacheable buffer |

Python 展示输入 key/nonce/AD/plaintext，读取 ciphertext/tag/cycles；认证失败与超时
显式报错，不形成成功 benchmark。S01-S05 若要抽象通用 Skill，仍必须参数化长度和地址，
不能把当前 16B 或 Ascon 地址硬编码为通用接口。

## benchmark 记录契约（拟定字段）

`schema_version, run_id, task_id, source_commit, dirty_patch_hash, timestamp, evidence_kind, board, part, xlen, clock_hz, vivado_version, compiler_version, compile_flags, firmware_hash, bitstream_hash, reference_commit, kat_hash, mode, operation, ad_bytes, message_bytes, cache_policy, interrupt_policy, measurement_scope, repetitions, raw_cycles, cycles_per_byte, code_bytes, lut, ff, bram, dsp, fmax_hz, timing_met, status, notes`。

JSON 保存原始值/结构化元数据，CSV 给出可比汇总；未测字段为 null/N/A 并说明原因。schema 正式实现由 C04/I07/Y05 维护版本，接口变更记录在 [decisions](decisions.md)。

## 2026-10-28 PYNQ UART服务实现补充（Y01，owner TBD）

PS控制/邮箱地址由HWH核验，当前BD分配0x40000000/0x40001000，各4KiB。CPU UART STATUS bit1=非空、bit3=满；不是PS地址。AXI写遵循WSTRB[0]，TX满延迟写响应，RX满置bit18溢出，UART无远端反压。SoC reset清FIFO及串口半帧，主机等boot Y01S后再发Y01E。Y01S bit0=simulated、bit1=selftest_pass、bit2=epoch_set；Y01R沿用mailbox协议bit0=cycles_valid/bit1=simulated，不混用。单请求/单客户端，ACK由Transport本地确认已收完整响应后释放；固件顺序处理，不另发ACK帧。超时/半帧需主机reset换epoch，不隐式重试。消息和AD上限各16B；repeat request_id及epoch0拒绝；64bit mcycle hi-lo-hi循环读取。
