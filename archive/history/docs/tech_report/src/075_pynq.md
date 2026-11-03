## 8 PS/PL 协同与 PYNQ 展示层

本章论述 PS/PL 协同通路的设计与验证。该通路的目标并非提升运算速度，而是使 ARM 侧应用（Python/Jupyter）
可调用 PL 内的 RV32 + Ascon 系统。当前已有 overlay、握手、容量内 KAT、Notebook、
warm benchmark 与错误恢复门禁的实板证据；所有结论限于当前 16 B 容量。

### 8.1 PS/PL 数据通道方案论证

任务书初稿拟定的方案为"AXI-Lite 控制寄存器 + 共享 BRAM"。查证冻结 RTL 后，该方案在不修改 `src/rtl`
的前提下不可成立，依据如下：

| 证据 | 位置 | 后果 |
|---|---|---|
| 外设访问全部在 `bus_interconnect` 内部译码（clint、uart、gpio、cpi、ascon），无通向 PL 边界的 MMIO 出口 | `src/rtl/bus_interconnect.v` | 若为 CPU 增加 PS 可见寄存器窗口，必须修改该文件 |
| 仅 `0x1000_0000` 至 `0x100F_FFFF` 被判为可 Cache | `src/rtl/dcache.v` | 共享 BRAM 必落于该窗口内，PS 写入后 CPU 可能读到旧 Cache 行 |
| 无 D-cache 失效或清洗指令（仅 `fence.i` 触发 I-cache 冲刷） | `src/rtl/cpu_core.v`、`dcache.v` | 固件无法在两次事务之间保证一致性，`volatile` 与 `fence` 不足以替代 |
| 历史 P0 时序余量为 WNS +0.087 ns | `docs/freeze_checkpoint_20261027.md` §4 | 改动公共路径需重新验证；采用独立 PYNQ 工程控制变更范围 |

据此，本作品采用"以既有 UART MMIO 作为 PS/PL 数据通道"的方案：在 PL 内新增 `pynq_mbox.v` 实现串口的
另一端，字节经 `uart_tx` 送入 SoC 的 `uart_rxd`，SoC 的 `uart_txd` 经 `uart_rx` 收入 RX FIFO 供 PS 读取。
该方案具备四项性质：

1. **独立发布源集**：历史 PL-only 证据保留，当前 BD 与桥接 RTL 单独构建并验证；
2. UART 属不可 Cache MMIO，当前无 PS/RV32 共享可缓存 buffer，缓存可见性记为 N/A，不泛化为所有架构均无一致性问题；
3. 同一份服务固件既可运行于 P0 纯 PL 版本（接真实 UART 引脚），亦可运行于 PYNQ 版本（PS 为对端），
   仅需维护一条代码路径；
4. 代价为延迟与带宽：链路为 6.25 Mbaud（`BAUD_CNT_MAX = 16`，100 MHz 分频），每字节约 1.6 µs。
   理论字节时间不等于 PS 调用墙钟。固定 KAT #529 的实测中位为 **4.262–5.216 ms**，
   包含 Python、MMIO 与 UART。固件 AEAD 周期不含串口，须与墙钟分列；不同固件边界仍会影响周期。

### 8.2 结构与寄存器定义

```
Jupyter (Python)
  └─ AsconHost → MailboxBackend → PynqUartTransport（src/pynq/pynq_transport.py）
        │  pynq.MMIO × 2（GP0，各 4 KiB）
        ├─ CONTROL 0x4000_0000 ── pynq_ctl.v  ：SOC_RESET / BUTTON / STAT(LED, RST) / ID
        └─ MAILBOX 0x4000_1000 ── pynq_mbox.v ：TX FIFO（64）─uart_tx─┐
                                                                     │ PL 内部，不经引脚
                                        RX FIFO（256）─uart_rx──┐    │
                                                               ▼    ▼
                                            SoC uart_rxd / uart_txd（top 端口，P0 同源集）
                                              cpu_core + dcache + uart_ctrl（0x2000_0000）
                                                        └─ Ascon：SW／MMIO／ISE
```

**CONTROL 窗口**（`pynq_ctl.v`，AXI-Lite 32 bit，遵循 WSTRB[0]）：

| 偏移 | 名称 | 读写 | 位定义 |
|---|---|---|---|
| `0x00` | CTRL | RW | `[0]` SOC_RESET（1 保持 RV32 复位，上电默认 1）；`[3:2]` BUTTON[1:0] 透传至 SoC GPIO |
| `0x04` | STAT | RO | `[0]` SOC_RST_N（送给 SoC 的复位，1 为运行）；`[3:2]` LED[1:0] 回读 |
| `0x08` | ID | RO | `0x514E_5950`（"PYNQ"，小端） |
| `0x0C` | VERSION | RO | `0x0000_0001` |

复位约定为：`CTRL[0]` 上电置 1（SoC 保持复位），PS 确认链路可用后写 0 释放；释放信号经三级同步器
进入 SoC 时钟域。

**MAILBOX 窗口**（`pynq_mbox.v`，TX 深度 64、RX 深度 256）：

| 偏移 | 名称 | 读写 | 含义 |
|---|---|---|---|
| `0x00` | TXDATA | W | `[7:0]` 压入一字节；FIFO 满时延迟写响应 |
| `0x04` | RXDATA | R | `[7:0]` 弹出一字节；空时读 0 且不弹出 |
| `0x08` | TXSTAT | R | `[15:0]` 深度；`[16]` 满；`[17]` 空 |
| `0x0C` | RXSTAT | R | `[15:0]` 深度；`[16]` 满；`[17]` 空；`[18]` 溢出（粘滞） |
| `0x10` | RXCLR | W | `[0]` 清溢出标志 |
| `0x14` | TXFLUSH | W | `[0]` 清空 TX FIFO |
| `0x18` | CNT | R | `[15:0]` PS 已压入字节数；`[31:16]` 已接收字节数（16-bit 回绕） |
| `0x1C` | ID | R | `0x4D42_4F58`。按 32-bit 小端读出字节序为 `58 4F 42 4D`（"XOBM"），按大端字节序方为 ASCII "MBOX"；与 CONTROL 窗口 `0x514E_5950`（小端读出 "PYNQ"）的编码方向相反，正文按 RTL 现状如实记录 |

`link_flush`（由 CONTROL 的 SOC_RESET 驱动）为高时清空两侧 FIFO 与计数，保证每次 SoC 复位后链路回到
确定状态。

### 8.3 服务协议与服务固件

字节流格式由 `src/pynq/mailbox_protocol.py` 与服务固件共同实现，共四类帧：

| 帧 | 长度 | 方向 | 用途 |
|---|---|---|---|
| `Y01Q` | 48 B 头 + key16 + nonce16 + AD + data + tag | PS → PL | AEAD 请求 |
| `Y01R` | 48 B 头 + payload | PL → PS | AEAD 响应 |
| `Y01S` | 64 B | PL → PS | 开机与 epoch 应答：固件标识、能力上限、自检结果、boot `mcycle` |
| `Y01E` | 20 B | PS → PL | PS 下发会话 epoch |

请求头字段依次为：magic（`Y01Q`）、version、flags、epoch（u64）、request_id（u64）、operation
（1 加密 / 2 解密）、mode（1 SW / 2 HW / 3 ISE）、adlen、dlen、output_capacity、taglen；响应头为
magic（`Y01R`）、version、flags、epoch、request_id、status、operation、mode、size、cycles。状态码为
`OK`、`AUTH_FAILED`、`LENGTH`、`UNSUPPORTED`、`INTERNAL`；响应 flags 中 `SIMULATED` 位在真实硬件执行
时恒为 0，`CYCLES_VALID` 位指示周期字段是否有效。协议约束为：失败响应不得携带数据与周期；key 与 nonce
长度须为 16；解密请求须携带 16 字节 tag。

服务固件 `pynq-svc-v1`（`src/firmware/pynq_svc/`）具备以下设计特征：

- **单槽串行**：一次仅处理一个请求，响应发完后回到帧同步状态，故 PS 侧无需额外 ACK 线；
- **周期口径**：仅在 AEAD 调用边界读取 64-bit `mcycle`（`0xB00`/`0xB80`，hi-lo-hi 一致读取），
  **不含串口传输时间**；
- **能力上限**：message 与 AD 各 16 字节，超长请求立即拒绝并返回 `LENGTH`；
- **构建**：`src/firmware/pynq_svc/build.sh` 以 RV32IM_Zicsr/ilp32 交叉编译，产物中检出 24 条
  custom-0 指令，P12/P8 均存在，可作为"ISE 确实被调用"的静态证据；
- **异常处置**：半帧读取依赖主机超时后 reset；无本地接收超时；UART 无远端流控。

> <span class="figslot">图 2-9</span> **PS/PL 协同通路结构**：Jupyter → Python API → 两个 AXI-Lite
> 窗口 → PL 内 UART 桥 → RV32 服务固件 → SW/MMIO/ISE；标注时钟域（FCLK0 100 MHz）、FIFO 深度与
> 帧格式。

### 8.4 Overlay 构建与时序签核

Overlay 由 `board/vivado_zynq7000_xc7z020_pynq/build.tcl` 自动创建：独立工程 `pynq_overlay.xpr`、
Block Design（PS7 GP0、FCLK0 = 100 MHz、`proc_sys_reset`）、综合与实现并导出同名 bit 与 hwh。发布产物
为 `release/pynq.bit`（4,045,688 B，与 P0 三份 4,045,687 B 的 bitstream 属不同源集）与
`release/pynq.hwh`（148,833 B），二者由同一 BD 导出；BRAM 单独
重新生成后，MIF 与最终 BIN 逐字节一致（128 KiB，含补零）。

> <span class="figslot">图 2-13</span> **Vivado Block Design：PYNQ overlay**：在 `pynq_overlay` 工程中
> 打开 Block Design，展示 PS7、AXI Interconnect、`proc_sys_reset` 与 PL 内 CONTROL / MAILBOX 窗口及 SoC 的连接。

时序与实现结果（100 MHz，2026-10-28）：

| 指标 | 数值 | 判据 |
|---|---|---|
| WNS / TNS | **+0.034 ns / 0** | setup 失败端点 0/62861 |
| WHS / THS | +0.020 ns / 0 | hold 失败端点 0/62861 |
| 未约束检查 | 内部未约束端点 0；`no_clock`、`no_input_delay`、`no_output_delay` 均为 0 | 本工程无外接 PL IO，故未套用 PL-only 的 UART/LED XDC |
| DRC | **0 Error / 0 Critical Warning** | 默认显示 53 项 Warning，含规则条数上限提示，不等于全部潜在 Warning 数 |
| 整机资源 | LUT 14269、FF 19691、BRAM 34.5 tile、DSP 4 | utilization.rpt；不沿用历史 PL-only 数字 |

> <span class="figslot">图 2-14</span> **Vivado 实现后时序摘要**：打开 `impl_1` 的 Report Timing Summary，
> 截取 Design Timing Summary 区域，应可见 WNS +0.034 ns、TNS 0、WHS +0.020 ns 与失败端点 0。

须注意：该 overlay 工程使用 `rtl_p0` 目录下的 `soc_top.v` 与 `ascon_mmio.v` 副本，其余 CPU 与 Ascon
模块按 manifest 记录选择。当前 KEY 由调用者写入，不能把工作树任意同名文件当作发布输入。
本轮不改 RTL、固件、bit/hwh 或 manifest，只对齐报告与已有证据。

### 8.5 验证结果与板上实测

**仿真与主机侧验证**（`validation_20261028.md`，全部 exit 0）：

| 验证项 | 内容 | 结果 |
|---|---|---|
| `test_host_api.py` | 17 项，含历史 Notebook 顺序执行 | PASS |
| `test_mailbox.py` | 24 项协议编解码与错误分支 | PASS |
| `test_navigator.py` | 8 项 | PASS |
| `test_pynq_transport.py` | 14 项，含 real-service 标志回归 | PASS |
| `golden_checker.py` | 1,089 组官方 KAT、4,290 次拒绝（host 范围） | PASS |
| `run_bridge.py` | 真实桥 RTL：双向传输、空读、WSTRB、RX 满与溢出、顺序读回、复位中止发送 | PASS |
| `run_service.py` | 真实 CPU + 最终固件 + AXI-Lite/UART + 行为级 AXI 存储；三模式 36 请求（加密/解密/坏 tag），检查 `mcycle` 非零；半帧复位后重新握手 | PASS |
| 固件构建 | RV32IM_Zicsr/ilp32，24 条 custom-0，P12/P8 存在 | PASS |
| 镜像一致性 | Vivado BRAM MIF 与最终 BIN 逐字节比较（128 KiB 含补零） | PASS |

**板上结果**（正点原子领航者 ZYNQ7020，PYNQ 2.7.0，Python 3.8.2）：
overlay 加载成功，MMIO ID 检查通过；服务报告为 `firmware_id=pynq-svc-v1`、`simulated=false`、
`selftest_mask=7`、`max_message_bytes=16`、`max_ad_bytes=16`、`board_validation=PASS`。

板上在 16 字节容量内执行 message 与 AD 各 0 至 16 字节的全部 289 组组合，三模式均通过：

| 模式 | 加密 KAT | 错误 Tag 拒绝 | 周期最小值 | 周期均值 | 周期中位数 | 周期最大值 |
|---|---:|---:|---:|---:|---:|---:|
| SW | 289/289 | 289/289 | 17584 | 23801.7 | 23543 | 33595 |
| HW | 289/289 | 289/289 | 1229 | 1589.0 | 1594 | 1797 |
| ISE | 289/289 | 289/289 | 3012 | 4122.0 | 4137 | 5209 |

据同一统计口径，均值之比为 **SW/HW ≈ 15.0×、SW/ISE ≈ 5.8×**，不是逐条加速比的均值。
该组数据不能与 §6.3 的历史 PL-only 独立基准
数值直接比较：后者为固定 16 字节、单一拍数的端到端测量（SW 20806、ISE 2570、MMIO 688），而本表为
服务固件覆盖 0 至 16 字节全长度组合的逐次统计，且调用内部包含适配、轮询与缓冲清理，不含请求帧传输。两组数值
差异的归因（尤以 HW 路径的平均 1589 周期与 P0 的 688 周期之差别）本轮<span class="blocked">尚未完成
</span>，故正文分列呈现，不作合并。

**证据身份**：板上测试使用发布版 bit、hwh 与固件，对应 Git `ac9143d5`，bit SHA-256
`6e7f9320…`，hwh SHA-256 `3ebd2640…`；证据归档于 `data/pynq/board_20261028/`（`pynq_board_full.json`、
`pynq_board_full.log`、`pynq_board_20261028.log`、`pynq_board_result.json`、`identity.txt`）。

**10-29 固定输入 benchmark 与 Notebook**：同 release、官方 KAT #529、PT=16 B、AD=0，
每模式预热 5 次后各 30 次加密/解密，全部 KAT 匹配。周期和墙钟见 §6.1–§6.2，
原始数组见 `data/pynq/notebook_20261029_130920/`。顺序执行结果存在；warm benchmark 已执行 ipynb 本体仍缺。

**10-29 V03 错误恢复**：9/9 checks、7/7 reset 恢复通过；epoch 1→8，
每次恢复后重新验证三模式 KAT。17 B PT/AD 返回 LENGTH；半帧、过期 deadline、重复 ID、错误 epoch、
RX FIFO overflow 均按门禁验证；每模式 50 次加密与 50 次解密匹配 KAT。
过期 deadline 用例验证主机截止时间与恢复机制，不证明硬件永久卡死也可自动恢复。
`data/pynq/error_gate_20261029_134023/` 含执行 Notebook、identity、JSON 与日志。

> <span class="figslot">图 2-10</span> **PYNQ 板测数据重排**：容量内 KAT、固定输入 warm benchmark 与错误恢复，
> 取自归档 JSON，不是原始终端截图或真实 Python 调用代码示例。

### 8.6 未闭环项

| 项 | 状态 | 说明 |
|---|---|---|
| 超出容量的 800 组板上用例 | NOT_RUN / 当前接口不支持 | 全量 host 已通过，不列为本次新增功能承诺 |
| warm benchmark 执行 Notebook 本体 | 待归档 | JSON/log 已存在，error-gate 本体已归档 |
| 小时级与资源泄漏 | not_measured | 每模式 50 次往返不等于小时级 RSS/FD 统计 |
| 协议错误与恢复 | 已有 9/9 实板证据 | 当前无共享 cacheable buffer，不伪造缓存测试 |
| 重复断电上电稳定性 | not_measured | 需冷启动与每次 smoke，软件 reset 不等于断电 |
| 独立 FCLK 测量 | not_measured | 配置 100 MHz 不等于独立测量 |
| 硬件轮询超时的错误语义 | <span class="todo">待完善</span> | 当前可能表现为内部失败或解密认证失败；异常时整链 reset 后重测，不作为认证性能数据 |

<span class="evid">证据 board/vivado_zynq7000_xc7z020_pynq/validation_20261028.md；board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md；data/pynq/board_20261028/pynq_board_full.json；data/pynq/notebook_20261029_130920/；data/pynq/error_gate_20261029_134023/</span>
