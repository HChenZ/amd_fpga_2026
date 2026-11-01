## 3 Ascon-AEAD128 的三种实现方案

本章论述算法的实现层内容，包括算法标准与参数（§3.1）、三种方案的接口契约（§3.2–§3.4），以及三者置于同一
SoC 内进行对照的必要性（§3.5）。全部公式依 NIST SP 800-232 Final 参数书写；端序统一为
little-endian，输入为字节串，tag 为完整 128 bit，不作截断，亦不采用 nonce masking。

### 3.1 算法标准与参数定义

Ascon 的安全核心为 320 bit 状态 $S=(s_0,s_1,s_2,s_3,s_4)$，每个分量 64 bit，认证加密通过"吸收与挤出
＋置换"实现。AEAD128 的参数如下表。

| 参数 | 取值 | 本作品的处理 |
|---|---|---|
| key | 16 byte / 128 bit | $K_0$ 取低 64 bit，$K_1$ 取高 64 bit |
| nonce | 16 byte / 128 bit | $N_0$、$N_1$ 同理 |
| tag | 16 byte / 128 bit | 完整输出，不截断 |
| rate / capacity | 128 bit / 192 bit | 每块吸收 16 byte |
| 初始向量 | 整数 `0x0000_1000_808c_0001`，字节串 `01 00 8c 80 00 10 00 00` | 常量以位移式匹配 |
| 轮常量 | `f0 e1 d2 c3 b4 a5 96 87 78 69 5a 4b`（第 0 至 11 轮） | P12 取前 12 个，P8 取后 8 个 |
| 域分离 | $s_4 \mathrel{\oplus}= 2^{63}$（`0x8000_0000_0000_0000`） | 于 AD 与 PT 之间插入 |

**轮函数**。第 $i$ 轮先执行常量加与 S-box，再执行线性扩散：

$$
\begin{aligned}
s_2 &\mathrel{\oplus}= c_i \\
s_0 &\mathrel{\oplus}= s_4,\quad s_4 \mathrel{\oplus}= s_3,\quad s_2 \mathrel{\oplus}= s_1 \\
t_0 &= \overline{s_0}\, s_1,\;\; t_1 = \overline{s_1}\, s_2,\;\; t_2 = \overline{s_2}\, s_3,\;\; t_3 = \overline{s_3}\, s_4,\;\; t_4 = \overline{s_4}\, s_0 \\
s_0 &\mathrel{\oplus}= t_1,\quad s_1 \mathrel{\oplus}= t_2,\quad s_2 \mathrel{\oplus}= t_3,\quad s_3 \mathrel{\oplus}= t_4,\quad s_4 \mathrel{\oplus}= t_0 \\
s_1 &\mathrel{\oplus}= s_0,\quad s_0 \mathrel{\oplus}= s_4,\quad s_3 \mathrel{\oplus}= s_2,\quad s_2 = \overline{s_2}
\end{aligned}
$$

线性层（$\mathrm{rotr}$ 表示 64 bit 循环右移）：

$$
s_i \mathrel{\oplus}= \mathrm{rotr}(s_i,\,r_{i,1}) \mathrel{\oplus} \mathrm{rotr}(s_i,\,r_{i,2}),
\qquad (r_{i,1},r_{i,2}) \in \{(19,28),(61,39),(1,6),(10,17),(7,41)\}
$$

**AEAD 流程**（加密方向）：

1. 初始化：$S \gets (IV,K_0,K_1,N_0,N_1)$，$S \gets P^{12}(S)$，$s_3 \mathrel{\oplus}= K_0$，
   $s_4 \mathrel{\oplus}= K_1$；
2. 关联数据：按 16 byte 分块吸收并执行 $P^8$；非空整块之后仍须追加一个空 padding 块并再次执行
   $P^8$；
3. 域分离：$s_4 \mathrel{\oplus}= 2^{63}$；
4. 明文：按 16 byte 分块挤出 $C_i = P_i \oplus (s_0 \| s_1)$ 并执行 $P^8$；末块不足 16 byte 时先补
   `0x01` 再补 `0x00`，末块不再置换；
5. 终结：$s_2 \mathrel{\oplus}= K_0$，$s_3 \mathrel{\oplus}= K_1$，$S \gets P^{12}(S)$，
   $s_3 \mathrel{\oplus}= K_0$，$s_4 \mathrel{\oplus}= K_1$；
6. 标签：$T = \mathrm{LE64}(s_3) \,\|\, \mathrm{LE64}(s_4)$；密文与明文等长。

三种方案遵循的实现要点如下。完整 1,089 组 KAT 为 host 验证范围；当前板级三模式仅验证容量内 289 组：

- padding 为"追加字节 `0x01` 后补 `0x00`"，在 64-bit 字中表示为 $1 \ll (8n)$，$n<8$；
- AD 为空时既不吸收亦不 padding，但仍执行域分离；
- 整块 AD 与整块 PT 之后均须再经一个空 padding 块，不得以"满块即结束"处理；
- 长度须显式给出，不得由"最高非零 bit"反推（否则 `00` 与 `a500` 将判定错误）。

> <span class="figslot">图 2-6</span> **Ascon 置换数据通路**：5 × 64-bit 状态、S-box 的五个与非项
> 组合、线性层的五组双旋转与轮常量注入；标注 P12/P8 轮数差异及 ISE 内 320-bit 状态寄存器位置。

### 3.2 方案一：纯软件实现（SW）

软件实现为正确性基准，同时作为周期加速比的参照基准（分母）。生产代码位于 `ascon/ascon_c/aead/`，锁定且不可修改的
参考实现位于 `sim/ascon/reference/ascon_c/`（ascon-c 固定 commit `446347f2`）。

**API 契约**（C）：

- `crypto_aead_encrypt(c, clen, m, mlen, ad, adlen, nsec, npub, k)`：`clen` 含 16 byte tag；
- `crypto_aead_decrypt(m, mlen, nsec, c, clen, ad, adlen, npub, k)`：tag 拼接于密文末尾，成功返回 0，且 `*mlen = clen − 16`；
  认证失败返回 −1，`*mlen = 0`，并清除 `m[0, clen−16)` 范围内的候选明文；`clen < 16` 时返回 −1
  且不写 `m`。

"认证失败须清除候选明文"为项目验收要求，非 SUPERCOP 的强制项：原始 C 参考在 bad tag 时返回 −1，
但缓冲区仍保留明文，且 `mlen` 等于明文长度。本作品修复生产 C 实现的失败处理，并将"原始 C 的真实
FAIL 行为"作为保留证据，不予掩盖。

**历史 PL-only 构建**：以 xpack `riscv-none-elf-gcc 15.2.0`、`-O2` 交叉编译为裸机固件，链接至
`0x1000_0000`，经 UART 输出测试结果。周期加速比的分母即该固件在板上的 `mcycle` 增量。在 16 字节明文、
warm 条件（指令已在 I-cache）下，板上实测为 **20806 周期**。当前 PYNQ 服务固件的固定输入
加密中位周期为 **23342**，见 §6.1；不与历史工具链和测量边界混用。

### 3.3 方案二：存储器映射加速器（MMIO／HW）

MMIO 实现将整个 AEAD 实现为挂接于 `0x3000_0000` 的从设备，CPU 仅承担参数搬运、状态轮询与结果读取。
当前接口取自发布源集 `board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v`，如下表。

| 偏移 | 名称 | 读写 | 位定义与语义 |
|---|---|---|---|
| `0x00` | CTRL | W | `[0]` START（自清脉冲，仅空闲态接受）；`[1]` ENCRYPT（1 加密，0 解密）；`[2]` ZEROIZE（仅空闲态接受，同一写中优先于 START） |
| `0x04` | STATUS | R | `[0]` BUSY；`[1]` DONE；`[2]` FAIL（解密 tag 校验失败） |
| `0x08` | ADLEN | W | AD 字节数 |
| `0x0C` | MLEN | W | 消息字节数 |
| `0x10–0x1C` | KEY | W | 四个小端序 32-bit key 字，由调用者写入 |
| `0x20–0x2C` | NONCE | W | $N_0$ 至 $N_3$ |
| `0x30–0x3C` | TAGIN | W | 解密时待校验的 tag |
| `0x40` | AD_WDATA | W | 推入一个 AD 字（内部指针自增） |
| `0x44` | MSG_WDATA | W | 推入一个消息字（加密为明文，解密为密文） |
| `0x48` | OUT_RDATA | R | 弹出一个输出字（加密为密文，解密为明文），指针自增 |
| `0x4C–0x58` | TAGOUT | R | 加密计算所得 tag |

以下四项行为构成"可用外设"而非"可计算模块"的判据，须写入契约：

1. **BUSY 期间全部写操作被忽略**，包括 ZEROIZE、START、key/nonce、长度与输入缓冲；
2. **输出读门禁**：`OUT_RDATA` 仅在 `DONE && !BUSY && !FAIL` 且未超出有效字数时返回数据并推进指针，
   其余情形返回零且不推进。认证失败不得发布明文由硬件保证，不依赖软件自觉；
3. **ZEROIZE**：清除 key、nonce、tagin、长度与状态，以及全部 AD、MSG、OUT 数组，并经子核心复位清除
   适配器缓冲、$s_0..s_4$、候选明文与 P8/P12 私有副本。DONE 本身不等于清理，取完结果后须显式清零；
4. **长度上限**：硬件实际支持 AD 与消息各 0 至 16 byte（参数名 `MAX_AD_BYTES=256` 仅为缓冲上限，
   不代表多块能力），超长请求显式返回 FAIL。该限制为 P0 的边界条件：板级 MMIO 周期加速比仅对
   ≤16 byte 成立，正文不将其泛化为"任意长度"。

延迟结构上，MMIO 端到端周期由参数搬运（key、nonce、AD 与消息的逐字写入）、轮询往返与密码核本体三
部分组成。历史 PL-only 16 B 调用为 **688 周期**，核本体观测 **103 周期**；
当前 PYNQ 固定输入加密为 **1439 周期**。核外开销的历史分解不直接套用到当前调用。

### 3.4 方案三：定制指令扩展（ISE）

ISE 将置换并入 CPU：320 bit Ascon 状态作为执行级的专用寄存器堆，由 4 条定制指令访问。指令占用
RISC-V 预留的 custom-0 编码（`0b0001011`），**未新造主操作码值**，4 条指令以 funct3 区分。

| funct3 | 助记符 | 操作数 | 周期 | 语义 |
|---|---|---|---|---|
| `000` | `ascon.w` | `rs1` 为数据，`rs2[3:0]` 为索引 | 1 | `state[32*idx +: 32] = rs1` |
| `001` | `ascon.rd` | `rs1[3:0]` 为索引，`rd` 为结果 | 1 | `rd = state[32*idx +: 32]` |
| `010` | `ascon.p12` | — | 多周期 | `state = P12(state)` |
| `011` | `ascon.p8` | — | 多周期 | `state = P8(state)` |

状态映射固定为 10 个 32-bit 字：`s0` 低与高、`s1` 低与高，直至 `s4`。非法索引（不在 0 至 9 范围）
读返回零、写被忽略；该行为属显式容错约定，不产生非法指令异常。保留 opcode 与 funct 编码的全局审计
仍在待办之列，正文不声称已覆盖全部指令空间。

实现细节与生命周期如下：

- `perm_start` 为电平信号（指令位于 EX 且未完成期间保持有效），内部状态机对其打一拍脉冲，完成后
  锁存结果；据此，流水线 hold 跨越完成不会导致重复执行；
- **取消**：陷入与中断经 `cancel` 丢弃在飞操作并清零 ISE 状态，且不发布迟到结果；普通分支冲刷仅
  清除较年轻指令，不影响已完成的置换；
- **局部复位寄存器化**：P12/P8 的 1280-bit 私有复位扇出原挂接于全局复位的组合锥（93 个失败端点、
  −0.128 ns），改为"取消当拍清架构 `state`，下一拍清私有 `s_reg/s_out`"，接受与 `p_start` 同拍
  释放局部复位，不增加正常执行的置换周期（§4.2）；
- **无上下文保存与恢复 ABI**：陷入取消后不可自中间轮续算，调用者须串行独占或整体重算。当前
  bare-metal 自测不启用抢占，真实中断、多任务与嵌套调用下的恢复尚未验证；
- **软件封装**：以 `asm volatile` 手写 intrinsic（不改动 GCC backend），逐字读写状态并调用 P8/P12；
  软件侧 AEAD 循环与 MMIO 版本共用同一调用顺序与测试向量，故两版密文与 tag 可逐字节比对。

历史 PL-only 16 B 加密为 **2570 周期**、相对同组软件 8.10×；当前 PYNQ 固定输入为
**3995 周期**、相对当前 SW 5.843×。ISE 的设计动机是用硬件置换替代软件轮函数；
不同固件的差值尚未完成分项归因，不把推测写成已测结论。

> <span class="figslot">图 2-7</span> **三种实现的调用路径对比**：SW（全部于 CPU 内完成）、
> HW（CPU 经寄存器搬运至加速器并轮询）、ISE（CPU 直接执行 custom-0，状态位于 EX 级）；标注三者
> 的数据搬运量与关键延迟分项（搬运、轮询、算法本体）。

### 3.5 三种方案的可比性边界

| 维度 | SW | MMIO（HW） | ISE |
|---|---|---|---|
| 数据通路 | 全部于 CPU 内逐字运算 | CPU → MMIO 总线 → 专用核 | CPU EX 级内，状态寄存器 |
| 单次 AEAD 的 CPU 动作 | 纯计算 | 写 key/nonce/AD/msg/len → START → 轮询 STATUS → 读 OUT/TAG | 写状态 → P8/P12 → 读状态 |
| 当前 PYNQ 加密周期（KAT #529） | 23342 | 1439 | 3995 |
| 当前周期加速比（相对 SW） | 1.000× | 16.221× | 5.843× |
| 当前服务长度能力 | PT/AD 各 ≤16 B | PT/AD 各 ≤16 B | PT/AD 各 ≤16 B |
| 主要成本 | CPU 软件运算 | 寄存器与窗口逻辑、轮询开销 | 指令译码、状态搬运与 EX 级多周期 |
| 面积统计 | 三模式共同占用的整机资源；不拆分独立面积 | 同左 | 同左 |
| 时序风险 | 无 | MMIO 完成路径（§4.2 最差路径） | EX 级 hold 与状态复位扇出 |
| 当前使用方式 | 正确性与周期基线 | CPU 搬运参数并主动轮询，短消息加速 | 软件 AEAD 控制流与硬件置换紧耦合 |

上述结果不宜读作"性能强弱排序"，而应理解为两条技术路线的取舍：MMIO 的周期加速比更高，但其能力受 16 byte
寄存器窗口与轮询开销约束，且 CPU 在轮询期间不可用；ISE 的周期加速比相对较低，然其状态位于流水线内，无
MMIO 总线往返，但当前服务仍统一受 16 B 长度限制。三者置于同一 SoC、同一套向量与
同一块板上测量，方能为该取舍提供实测依据。

<span class="evid">证据 docs/ascon_key_management.md；docs/ascon_standard_baseline.md；board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v；src/rtl/ascon/ascon_ise.v；data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json</span>
