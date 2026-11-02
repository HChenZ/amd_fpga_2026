# PS/PL 最小接入建议（Y01 draft，owner TBD）

> 2026-11-01：这是早期接入建议，非当前唯一方案/运行授权。PUF3使用独立身份与Notebook，旧v1程序保留。
> 当前协议/源集选择见 report/design/interfaces.md 与 report/design/version_entrypoints.md，不按草案替换现有设计。

2026-10-25。接口设计准备，**未冻结、未实现到 RTL/固件**。复用 `src/pynq/mailbox_protocol.md` 的 draft v1 消息；不分配任何真实 PS 寄存器地址。当前 baseline 无 PS7、无 PS 可用 Mailbox；三套固件是 UART 自测程序，没有 Mailbox 服务循环。

```text
Jupyter → AsconHost → MailboxBackend → NavigatorTransport → future physical driver
    → PS M_AXI_GP0 → AXI-Lite control + shared BRAM → PL RISC-V firmware → SW/MMIO/ISE
```

| 方案 | 所需改动与主要风险 | 选择 |
|---|---|---|
| A AXI-Lite 控制 + 共享 BRAM | 小控制适配块提供 reset/start/status/epoch/capabilities，payload 在受控 BRAM；固件加 Mailbox 循环；仍须 CPU 侧可见地址和缓存策略 | 推荐作为后续评审方向，生命周期与故障恢复较明确 |
| B PS 直接写现有 RV32 存储器 + 状态握手 | 两主机仲裁/额外 BRAM 端口，需从128 KiB中预留空间并修改链接；CPU I/D Cache 与 PS 写冲突；动态重装与正在执行代码冲突 | 初次自测可评估 reset下装载；不推荐无隔离地当长期运行协议 |

两方案都不是纯 Python 修改。A 增加控制逻辑，但能避免 PS 任意写执行区，并复用既有 Host 单槽所有权/恢复逻辑。相对整个 SoC 风险最低不等于“现有端口已经可连”；从资源/RTL接口静态看尚不能断言无需 CPU/SoC 集成修改。团队必须评审物理接入，用户本轮禁止的文件均未主动修改。

| 契约项 | 建议及待冻结内容 |
|---|---|
| CPU 启动/复位 | 后续独立 wrapper 的 PS 控制位先保持 RV32 reset；时钟锁定并完成镜像/协议初始化后，同步释放。PS/AXI 控制域不能随 RV32 soft reset 一起失联。状态至少区分 RESET/BOOTING/READY/BUSY/COMPLETE/ERROR；位偏移待设计分配。不能用物理 PL reset 替代每次命令握手 |
| 已知 RV32 地址 | reset PC与BRAM=0x10000000，容量128 KiB；UART=0x20000000，Ascon MMIO=0x30000000（见 ascon_hw_rv32/main.c / bus_interconnect.v）；均不是 PS 物理地址。PS control/mailbox base/range、RV32 mailbox地址和翻译一律 TBD，后续以 BD/HWH/address report 为准 |
| 固件加载 | 优先在未来独立工程用本轮 SW/HW/ISE COE 静态初始化，保持128 KiB。PS 动态装载属于后续：全程 RV32 reset，检查段/容量/校验和，处理 I/D Cache失效后再启动；未经验证不能声称支持 reload。原 baseline COE不改 |
| 请求 | 既有48B little-endian header，非零u64 epoch/request_id，op/mode/AD/input/output_capacity/tag长度；内联 key16+nonce16+AD+input+decrypt-tag16。只复用逻辑消息偏移，不把它们当控制寄存器偏移 |
| 响应 | 既有48B header，epoch/id/op/mode 回显，status/有效长度/u64 mcycle；encrypt为CT+tag，decrypt仅认证成功后发布PT。失败payload空、cycles invalid，匹配ACK并完成清理后才能复用单槽 |
| 容量 | 当前 full-MMIO 模式PT/AD各≤16B。初版广告所有mode共同上限16B，避免Python32B模拟能力被误认为硬件能力。请求最大128B（48+16+16+16+16+16），响应最大80B；实际分配需另计能力/状态/对齐，最终大小由设计确认。SW/ISE更长长度需单独能力协商升级，不能悄悄截断 |
| BRAM/总线接入 | 优先独立 Mailbox scratch BRAM，避免侵占固件/栈；但现有外部 AXI 主口主要走memory路径，非任意MMIO都转发到该口，且dcache有cacheable判定。需要团队明确新增可达/不缓存窗口或审核有效失效操作；本轮不承诺把AXI线接上就能轮询共享区 |
| 时钟/复位 | 可评估 CPU/AXI/控制同100MHz FCLK0以降低CDC风险；当前50MHz外输入+PLL方案先保留，不能把FCLK与外PLL当同源。异步域必须用AXI clock converter/双口BRAM配套发布握手，同步reset释放，验证reset during busy/late response |
| 缓存/发布 | PS MMIO映射非缓存或正确flush/invalidate；RV32需经验证的不缓存访问路径，不能仅靠volatile/fence推断dcache失效。PS先写payload再release/doorbell，CPU acquire后处理；CPU完成候选擦除、写完整响应再release done，PS acquire后取快照。ACK清理后所有权归还；64-bit状态不能靠两次32-bit读假定原子 |
| 超时 | 单次绝对monotonic deadline覆盖submit/poll/ACK；总线错误、晚响应、身份不匹配、ACK失败隔离通道。显式reset/quiesce改变epoch并确认旧工作停止后才能恢复；不自动重试加密，不把timeout解释为操作未发生 |
| cycles | 固件调用边界64-bit mcycle差值，RV32高低高读取；范围固定并注明是否含擦除。PS端到端时间单列。不使用cpi_cnt事件和或Python wall time替代；未测=None/NOT_MEASURED |
| 后续PUF | 本轮只保留既有public-test-key16消息，无密钥生成/重建实现。未来key_handle/key_source需版本化协议扩展、能力协商和独立安全审查；不得在保留位偷偷塞handle，不改key_mmio/key lifecycle。PUF结果和内部密钥不得经普通日志泄漏 |

`NavigatorTransport` 只提供可配置绑定与 driver 注入接口。真实路径要求已加载 Overlay（调用方提供）、同名 bit/hwh、firmware SHA256、固件标识、design_source、protocol_revision，以及与 HWH `ip_dict` 精确一致且不重叠的control/mailbox窗口。默认配置为 NOT_CONFIGURED；mock路径强制 simulated=True，使用现有MemoryTransport，cycles=None。哈希和hello身份是追溯检查，不构成安全认证或完整可信启动。

后续冻结前必须交付：控制寄存器物理语义/能力区布局、RV32服务固件与cache策略、地址表、取消/清理的硬件语义、多主机独占锁，以及旧/新epoch跨复位用例。当前 Python 单实例锁不能替代跨进程设备独占。完整Y01/Y02/Y03/Y04/V03仍未验收。
