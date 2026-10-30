# PYNQ 常见错误形态 → 定位方法

按"先确认看到的是哪份硬件，再确认寄存器语义，最后看数据通路"的顺序排查。
每条给出**可执行的判别动作**，不要凭现象直接改代码。

## 1. 加载/身份类

| 现象 | 判别动作 | 结论与修复 |
|---|---|---|
| `Overlay()` 成功但某 IP 属性不存在 | `print(ol.ip_dict.keys())`；`hwh.parse_hwh()` 列实例名 | 名字以 hwh 为准；层级 IP 用 `ol.hier.ip` 或含 `/` 的键 |
| 寄存器读回与预期完全无关 | 比对 `ip_dict[ip]['phys_addr']` 与 hwh MEMRANGE；读 ID 寄存器 | bit 与 hwh 不配套或用了旧 hwh → 重新导出同一次实现的 bit+hwh，用哈希 manifest 绑定 |
| 第一次 MMIO 读就卡死（Python 不返回） | 换一个已知 IP（如 GPIO）读；查 PL 时钟/复位 | AXI 从口不应答（无时钟、复位未释放、地址落在未映射区）。Python 层无法超时打断内核 MMIO 访问，必须修硬件或地址 |
| `fclk0_mhz` 与设计不符（常见约 1.5 倍偏差） | 比较 hwh `PCW_CRYSTAL_PERIPHERAL_FREQMHZ` 与 PYNQ 参考时钟假设 | 读回值是按寄存器推算的；参考时钟假设不同会失真，记录为推算值 |
| 两个 Notebook 交替出错 | `lsof`/进程表；看是否都调用了 `Overlay()` | PL 被另一个进程重新下载；加进程锁且在下载前获取 |
| 访问 `ol.axi_dma_0` 就卡住 | 改用 `MMIO(ip_dict[...])` 读 DMASR | 驱动构造函数里 `start()` 无超时自旋，DMA 未出复位或时钟缺失 |

## 2. 寄存器语义类

| 现象 | 判别动作 | 结论与修复 |
|---|---|---|
| done 永远等不到，但 IP 实际已完成 | 查该位是否 clear-on-read；看代码是否在等待前已读过一次控制寄存器 | 读清位被提前消费；一次读取保存全部字段（R3） |
| 第一次结果是上一次的 | 打印 START 前后的 busy/done | 粘滞 done 未清或未确认 busy 抬起（R6） |
| 64 位地址设备访问到奇怪位置 | 读回 `_lo`/`_hi` 两个寄存器 | 只写了低半（R4） |
| 中断只来一次 | 查 ISR 是否 TOW/W1C 并已清 | 中断处理里写 1 清 ISR，且不要对 ISR 读-改-写 |
| `register_map` 不存在或字段缺失 | 看 hwh 里该 MODULE 是否有 `<REGISTERS>` | 非 HLS/未声明寄存器的 IP 没有 register_map；用契约 + MMIO |

## 3. DMA 与缓存类

AXI DMA（PG021）简单模式寄存器：MM2S 基 0x00，S2MM 基 0x30。
`DMACR`(+0x00)：bit0 RS 运行，bit2 Reset，bit12/13/14 IOC/Dly/Err 中断使能。
`DMASR`(+0x04)：bit0 Halted，bit1 Idle，bit3 SGIncld，bit4 DMAIntErr，bit5 DMASlvErr，
bit6 DMADecErr，bit8–10 SG 错误，bit12 IOC_Irq，bit13 Dly_Irq，bit14 Err_Irq（12–14 为 W1C）。
地址 +0x18/+0x1C（低/高），长度 +0x28；S2MM 实际接收长度即 0x58。
`dma.decode_dmasr(value)` 会把这些位翻成文字。

| 现象 | 判别动作 | 结论与修复 |
|---|---|---|
| `DMA Internal Error (transfer length 0?)` / bit4 | 打印请求长度、S2MM 缓冲长度、包实际长度 | 长度 0；或 S2MM 申请长度 < PL 包长（TLAST 来得晚） |
| bit5 SlvErr / bit6 DecErr | 打印写入的地址寄存器、缓冲 `physical_address` | 写了虚拟地址/未分配/已释放地址；HP/ACP 口未使能或地址不在其映射内 |
| 接收永不完成，DMASR 不 Idle | 读 S2MM DMASR 与 MM2S DMASR；看发送是否已 Idle | PL 未发 TLAST、PL 侧流反压未释放、先发后收导致死锁（D4/D5） |
| 输出全 0/全哨兵 | 接收前填哨兵；完成后看 `transferred` | DMA 没写（长度 0/TLAST 早到）或未 invalidate |
| 输出是上一次的正确结果 | 每轮换输入并填哨兵 | 缺 invalidate、读取了旧缓冲，或 done 归属错 |
| 输出前面对后面错 | 对比 `transferred` 与期望长度 | 实际长度更短（TLAST 早到）或超过 `max_size` 被截断 |
| 字节整体平移 | 检查 `physical_address % data_width_bytes` | 无 DRE 时未对齐 |
| 释放缓冲后系统随机崩溃/其他程序数据损坏 | 回看错误路径是否在 DMA 停止前释放 | D7：先 Reset → 双通道 Halted → 再释放 |

## 4. 黄金比对诊断提示（`golden.compare` 的 `hint` 字段）

| hint | 含义 |
|---|---|
| `all_sentinel` | 硬件没有写入接收区，或没 invalidate |
| `all_zero` | 未写入/读错缓冲/设备返回 0 |
| `equals_previous` | 读到上一次的数据（缓存或 done 归属） |
| `byte_swapped_words` | 端序问题（32 位字内字节反转） |
| `shifted_by_k` | 偏移/对齐错误，k 为平移字节数 |
| `tail_only` | 只有尾部错：长度、填充或 TLAST |
| `length_mismatch` | 实际长度与期望不同 |
| `scattered` | 无明显模式：算法/位序/参数错误，回到参考模型逐步对拍 |
