# Y01 UART mailbox 协议 v1

2026-10-18 起草，2026-10-29 完成当前实现验收。owner TBD。

当前物理映射为两个 AXI-Lite 窗口 + AXI-Lite byte FIFO + RV32 UART uncached MMIO：
control `0x4000_0000`、mailbox `0x4000_1000`，CPU UART `0x2000_0000`；
地址最终以同次 HWH 为准。2026-10-28/29 已完成三模式 KAT、Notebook、warm benchmark
和 V03 错误/恢复门禁，证据见
`board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md`。

这是 Host 与 `pynq_svc` 固件之间的逻辑与物理实现契约。
本节其余内容描述消息逻辑；实际 AXI 地址、FIFO 位宽和 UART 映射以上方当前状态为准。
下文的字节偏移仅为**消息内偏移**，禁止作为 MMIO 地址使用。
历史草案中关于“尚未接入硬件”的描述已经被上述实板结果取代。

## 1. 范围与实现入口

```text
AsconHost (既有 API，不变)
  -> MailboxBackend (事务适配器、deadline、身份核对、ACK、恢复门禁)
    -> Transport (抽象接口，不指定物理链路)
      -> MemoryTransport (Python 单槽模拟 peer)
        -> 锁定 Ascon-AEAD128 Python reference
```

- `mailbox_protocol.py`：有界消息编解码，版本/保留位/长度/状态检查。
- `mailbox_backend.py`：Transport 契约、协议适配器、内存 peer。
- `test_mailbox.py`：codec、身份、所有权、拒绝、错误/恢复及 deadline 测试。
- `golden_checker.py --backend mailbox`：通过整个模拟事务链执行官方 KAT 和篡改拒绝。

不生成假的 bit/hwh、固件镜像或 PynqBackend。所有 mode 在 MemoryTransport 中都调用
同一锁定 Python reference；不会执行真实 SW/RV32、MMIO 或 custom ISE。

## 2. 握手、容量与单槽所有权

在任何带密钥请求之前，`hello(absolute_deadline)` 返回不可变 `Capabilities`：

| 字段 | 含义 |
|---|---|
| version | 必须等于 1，不兼容版本拒绝，不静默降级 |
| epoch | 非零 u64 会话标识；reset 后变化，真实实现不得在旧响应可能存在时复用 |
| max_message_bytes / max_ad_bytes | 当前服务实际容量，各 0..65536；不是端口位宽 |
| modes | 支持的 SW/HW/ISE 子集，非空且不重复 |
| simulated | 结果证据类别，response 必须与握手一致；不具备密码学身份认证含义 |
| firmware_id | 非空、最长128字符的运行固件标识；模拟值明确为 simulated-reference |

握手是 Transport 方法返回的逻辑对象。当前 board profile 从 HWH 校验窗口地址，
并用 `Y01S` 服务帧核对 firmware_id/版本/能力；详细物理映射见本文开头。
所有已广告 mode 共用该容量上限；若真实 MMIO 仅支持16B，须只广告适用 mode，或保守地
令共同上限为16B；要实现每mode不同容量必须升级能力契约，不能让 host 猜测。
内存 peer 默认32B/32B只是为了覆盖1,089官方向量，**不是硬件多块支持证明**。

每个 Transport 只允许一个 MailboxBackend 拥有；多调用方共享同一个 backend。
backend 使用非阻塞互斥，重入抛 `MailboxBusyError`。不支持多个进程或多个 adapter
共享同一 mailbox，未来需要设备独占锁，不能依赖 Python 线程锁替代系统级所有权。

```text
idle --submit--> busy --原子完成--> complete --匹配ACK并清理--> idle
  \______________________ reset/quiesce _____________________/
```

- `submit` 只能在 idle 发布完整请求；busy/complete 均拒绝第二个请求，不覆盖旧 slot。
- busy 时 `poll` 返回 None，不能读出候选结果；complete 响应保持稳定，直到正确 ACK。
- ACK 必须匹配 `(epoch, request_id)`；错误 ACK 不释放 slot。
- `request_id` 非零 u64，每会话严格递增，重复/乱序均拒绝；耗尽后显式恢复，不允许回绕。
- `reset` 可丢弃未完成请求或未ACK完成结果；确认旧执行已停止、敏感内容已清理后才能返回
  新 epoch 并开放新 slot。MemoryTransport 只清除 Python 引用，不声称物理安全擦除。

## 3. 请求消息（little-endian）

所有整数无符号，固定 header 为48 bytes，`struct`：`<4sHHQQIIIIII`。
消息是不可变 bytes 快照，不允许工作中修改或复用其底层共享buffer。

| 消息内偏移 | 字节数 | 字段 |
|---:|---:|---|
| 0 | 4 | magic ASCII `Y01Q` |
| 4 | 2 | version=1 |
| 6 | 2 | flags=0，保留位非零拒绝 |
| 8 | 8 | epoch |
| 16 | 8 | request_id |
| 24 | 4 | operation：1 encrypt、2 decrypt |
| 28 | 4 | mode：1 SW、2 HW（full MMIO AEAD）、3 ISE（CPU编排/置换ISE） |
| 32 | 4 | ad_bytes |
| 36 | 4 | input_bytes（不包含tag） |
| 40 | 4 | output_capacity（包含加密输出tag所需空间） |
| 44 | 4 | tag_bytes：加密0，解密16 |
| 48起 | 变长 | `key[16] || nonce[16] || AD || input || tag` |

算法仅 Ascon-AEAD128 / NIST SP800-232 Final：固定16B key/nonce/tag，不接受截短tag。
加密 input 是明文；解密 input 是密文，tag 独立附于请求末尾。
加密所需输出容量为 input_bytes+16；解密为 input_bytes；空加密仍需要16B tag容量。
header、body 必须精确一致，拒绝截断、额外尾字节、未知版本/mode/op、错误tag长度。
codec 的消息/AD最大值各65536B，服务容量另以握手为准；先检查容量和长度，再执行算法。
不支持隐式截断、整数缩窄、重叠输出或任意地址指针，避免地址溢出和输入/输出别名。
当前 v1 采用内联 payload；未来 BRAM/DDR buffer 描述符、对齐与地址翻译尚未定义。

## 4. 响应消息与认证发布

固定 header 为48 bytes，`struct`：`<4sHHQQIIIIQ`。

| 消息内偏移 | 字节数 | 字段 |
|---:|---:|---|
| 0 | 4 | magic ASCII `Y01R` |
| 4 | 2 | version=1 |
| 6 | 2 | flags：bit0 CYCLES_VALID、bit1 SIMULATED，其余必须0 |
| 8 | 8 | epoch（原样回显） |
| 16 | 8 | request_id（原样回显） |
| 24 | 4 | status |
| 28 | 4 | operation（原样回显） |
| 32 | 4 | mode（原样回显） |
| 36 | 4 | output_bytes |
| 40 | 8 | cycles；无效时必须0，不以数值0表示“未测” |
| 48起 | 变长 | 成功：加密 `ciphertext || tag`、解密 `plaintext` |

| status | 编码 | host 行为 |
|---|---:|---|
| OK | 0 | 校验身份/长度，ACK成功后才返回输出 |
| AUTH_FAILED | 1 | 仅解密允许；ACK后抛 AuthenticationError，不返回明文 |
| LENGTH | 2 | ACK后抛 InvalidLengthError |
| UNSUPPORTED | 3 | ACK后抛 BackendProtocolError |
| INTERNAL | 4 | ACK后抛 BackendProtocolError，无内部错误详情 |

所有非OK响应必须 output_bytes=0、payload空、CYCLES_VALID=0、cycles=0。
codec 直接拒绝“错误状态附带候选明文/周期”的帧。
真正固件必须完整tag验证、候选擦除和状态清理后才发布失败；认证前不得对PS开放候选输出。
header和payload需要一致快照，完成发布与读取具备release/acquire语义；48B复制本身
不是原子硬件动作，物理适配器需要独立完成标记/序号或等效快照机制。
协议中的“原子”是逻辑契约；当前硬件实现已验证单槽完成/ACK，但未来共享内存方案
仍需单独验证物理原子性。

成功响应必须与本次 epoch/id/op/mode、证据类型及精确预期输出长度一致，否则隔离通道。
ACK失败时即使拿到了正确解密结果也不向调用方返回。

### 周期规则

- 真实服务应记录固件内 AEAD 调用边界的64-bit `mcycle` 差值，RV32高低高一致读取；
  具体擦除是否计入需随固件固定测量范围，不能将CPU CPI事件相加当cycles。
- cycles 不是PS端到端时间，排除传输、Python、轮询和ACK；若以后需要wall time须另立字段。
- `CYCLES_VALID=0` 映射 `cycles=None / not_measured`；valid=1时零可表示真实零值。
- MemoryTransport 不伪造mcycle，正常响应始终未测；不把上一任务的17353/670/2496历史采样
  塞进本次通信响应。测试注入的>32bit周期只验证编解码/传递，不是benchmark。
- adapter 按线程保存最近成功事务CycleInfo，防止共享backend的不同调用线程混淆周期。

## 5. deadline、错误与恢复

Transport 的所有方法接受 monotonic **绝对 deadline**：

```text
hello(deadline) -> Capabilities
submit(request_packet, deadline) -> None
poll(deadline) -> response_packet | None
ack(epoch, request_id, deadline) -> None
reset(deadline) -> Capabilities
```

backend 每次操作使用一个预算覆盖 submit/poll/sleep/ACK；调用前后都查deadline。
握手和显式恢复各有独立有限正数预算。poll 间隔默认1ms，并按剩余预算缩短。
任何真实Transport必须在阻塞I/O内部落实deadline；外层检查不能抢占挂起的系统调用。
MemoryTransport 的reference执行同步不可抢占，超时只能在返回后拒绝结果。

- submit/poll/ACK发生超时、总线错误、格式错误或旧响应，设置 `needs_recovery=True`。
- 此后新请求立即拒绝，不能复用旧slot或静默重试，也不因poll次数耗尽假装完成。
- 调用 `backend.recover(timeout_s=...)`：reset/quiesce、确认 epoch 改变、重新验证能力后解禁。
  reset失败、超时或未改变epoch则保持隔离；恢复本身不重发原请求。
- 正常认证/长度/不支持/内部错误响应在完成合法ACK后可释放slot；不作为成功benchmark。
- caller负责部署时key/nonce唯一性策略；运输异常不能作为“加密肯定未发生”的证明。
- 不在异常中输出key、nonce、明文、tag或底层设备详情。数据帧包含秘密，不应保存到普通日志。

## 6. 当前实现与边界

1. PS/PL 不共享 BRAM。主机通过两个 AXI-Lite 窗口访问 `pynq_ctl`/`pynq_mbox`，
   后者连接 RV32 UART。当前帧为内联 bytes，没有地址描述符或重叠 buffer。
2. UART 是 uncached MMIO，因此当前 ABI 不依赖 PS/CPU cache flush 或 invalidate；
   缓存可见性记为 `NOT_APPLICABLE`。若未来改成 shared BRAM/DDR，必须重新定义一致性。
3. 单槽、单客户端、顺序处理；ACK 由 Transport 在收到完整合法响应后本地释放 slot。
   V03 已实板验证重复 request_id、错误 epoch、RX overflow、半帧和显式 reset/epoch 恢复。
4. 固件镜像通过 `blk_mem_gen_0` 的 COE 随 bitstream 构建，不是运行时任意内存写命令。
   当前没有通用动态 firmware loader；S01 若实现 loader，必须另行验证哈希、复位向量、
   内存范围和失败关闭。
5. 当前硬件容量为 PT/AD 各 16 bytes。800 组超容量 KAT 为 `NOT_RUN`；host 1,089 组
   通过不能替代目标硬件全量通过。

## 7. 运行与证据

仓库根，Python3.11，仅标准库：

```sh
python src/pynq/test_mailbox.py
python src/pynq/golden_checker.py --backend mailbox --mode ise
python src/pynq/golden_checker.py --backend mailbox --mode sw
python src/pynq/golden_checker.py --backend mailbox --mode hw
python src/pynq/test_host_api.py
```

使用现有API，无需改调用：

```python
from src.pynq.ascon_host_api import AsconHost
from src.pynq.mailbox_backend import MailboxBackend, MemoryTransport

backend = MailboxBackend(MemoryTransport(), mode="ise")
host = AsconHost(backend)
# 公开测试输入，不用于部署；同一key下nonce必须唯一。
result = host.encrypt(bytes(range(16)), bytes(range(16, 32)), b"", b"hello")
assert result.simulated and result.cycles is None
assert host.decrypt(bytes(range(16)), bytes(range(16, 32)), b"", result.ciphertext, result.tag).plaintext == b"hello"
```

2026-10-18 初次无板实跑 CPython3.11.16：协议测试24/24通过；ISE模拟mailbox全量
KAT PASS1089/FAIL0，篡改拒绝4290，exit0。其余回归与最终命令结果见本目录readme。
未启动Vivado，未编译/加载固件，无板级测量；全部owner TBD。

2026-10-29 update：上述“无板”结论是历史快照。当前已在领航者 ZYNQ7020 实板完成
容量内 289/289 KAT、Notebook、30 次 warm benchmark 和 V03 9/9 错误/恢复门禁；
详细证据见 `board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md`。
