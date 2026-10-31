---
name: pynq-overlay-workflow
description: "Use when writing, reviewing or debugging PYNQ host-side Python for any Zynq-7000/Zynq UltraScale+ board: overlay (.bit/.hwh) loading and verification, MMIO/register_map drivers generated from an interface contract, HLS ap_ctrl kernels, AXI DMA transfers and cache coherence (flush/invalidate), golden-reference comparison, timing/resource report collection. Board- and design-agnostic."
---

# PYNQ Overlay 工作流（板卡/题目无关）

PYNQ 主机代码最常见的失败**不是 Python 写错**，而是：PS 读到的不是你以为的那份硬件
（bit/hwh 不配套）、寄存器语义靠猜（clear-on-read、64 位地址拆分）、DMA 和 CPU 缓存
看到的数据不一致、等待没有超时导致整个 Notebook 卡死、以及"结果对了"其实是旧数据。
本 Skill 把这些变成**可检查的门禁**，并提供 `scripts/pynq_skill/` 通用工具（纯 Python，
不依赖具体板卡；能在无板环境用 `fakes.py` 离线测试）。

不适用：RTL/HLS 内部设计（用 rtl-design-discipline / hls-*）、Vivado 时序收敛、
PetaLinux/设备树定制、Versal/RFSoC 专有 IP、Scatter-Gather DMA 的完整驱动（只给定位方法）。

## 0. 五段式流程（每段有门禁，门禁不过不进入下一段）

| 段 | 做什么 | 门禁（可判定） | 工具 |
|---|---|---|---|
| A 工件 | 定位 .bit/.hwh，核对哈希与来源 | bit 与 hwh **同名同目录**、哈希与 manifest 一致、来自同一次实现 | `artifacts.check_artifacts` |
| B 加载 | `Overlay()` 下载并读回 | `is_loaded()`；所需 IP 在 `ip_dict`、VLNV/基址/范围与 hwh 一致；身份/版本寄存器读回正确；FCLK 与 hwh 一致 | `overlay_check.verify_overlay` |
| C 寄存器 | 从**接口契约**生成驱动 | 契约无重叠/越界；每个寄存器有访问语义（rw/ro/wo/rc/w1c）；生成的测试骨架在 FakeMMIO 上通过 | `regmap` + `pynq_skill_cli.py gen` |
| D 数据通路 | MMIO 或 DMA 搬运 | 每次等待有**有限 deadline**；DMA 前 flush、后 invalidate；用**实际传输长度**取结果；出错先证明 DMA 已停再释放缓冲 | `dma.BoundedSimpleDMA` |
| E 证据 | 黄金比对 + 性能/资源报告 | 比对覆盖边界用例且含**故意错误**（变异）用例；性能分 warm/cold、给分布；每个数字标 measured/simulated/not_measured | `golden`、`report` |

开始任何 PYNQ 任务前，先回答四个问题并写进代码注释或说明：
1. 哪个 bit/hwh（路径+SHA-256）？由哪个 Vivado 版本、哪个 PYNQ 版本使用？
2. 要访问的 IP 实例名是什么（**从 hwh/ip_dict 查，不要猜**）？
3. 寄存器语义的权威来源是什么（HLS 生成的 `x<kernel>_hw.h`、IP 产品手册 PG0xx、RTL 源码）？
4. 数据走 MMIO 还是 DMA？缓冲区是否 cacheable？完成条件是什么？超时多少？

## 1. Overlay 加载与校验

- **O1 bit 与 hwh 必须同名同目录**：`Overlay('x/design.bit')` 按同名找 `x/design.hwh`。
  重命名 bit 却留下旧 hwh，PYNQ 不报错，`ip_dict` 地址却是旧设计的 —— 写寄存器打到错误外设。
  用哈希 manifest 证明两者来自同一次实现，不要只比文件名或时间戳。
- **O2 先校验再下载**：哈希不对就不要 `Overlay()`，下载会改 PL 与 FCLK，影响别的进程。
  需要只解析不下载时用 `Overlay(path, download=False)`。
- **O3 读回身份**：设计里应有只读 ID/VERSION 寄存器（自定义 IP 强烈建议加）；加载后读回比对。
  没有 ID 寄存器时，至少比对 `ip_dict[name]['phys_addr']`、`addr_range`、`type`(VLNV) 与 hwh。
- **O4 IP 名从 hwh 取**：BD 里的实例名（如 `axi_dma_0`、`hier/foo_0`）就是 `ip_dict` 的键；
  层级 IP 键含 `/`，属性访问要用 `overlay.hier.foo_0` 或 `ip_dict['hier/foo_0']`。
- **O5 时钟**：PYNQ 加载时按 hwh 设置 FCLK。用 `pynq.ps.Clocks.fclk0_mhz` 读回并与 hwh 的
  `PCW_FPGA0_PERIPHERAL_FREQMHZ` 比；这个值是按寄存器和**参考时钟假设**算出的，
  若 hwh 的 `PCW_CRYSTAL_PERIPHERAL_FREQMHZ` 与 PYNQ 镜像假设（如 50 MHz vs 33.333 MHz）不同，
  读回值会失真 —— 记录"寄存器推算值"，不要当成实测频率。
- **O6 访问驱动类的副作用**：`overlay.<ip>` 会实例化绑定的驱动；某些驱动构造函数会访问硬件
  （PYNQ 2.7 `DMA.__init__` 中 `_SDMAChannel.start()` 是无超时自旋）。硬件未就绪时可能卡死。
  需要可控时用 `pynq.MMIO(ip_dict[name]['phys_addr'], ip_dict[name]['addr_range'])` 自建访问。
- **O7 多进程独占**：同一 PL 只能有一个所有者。Notebook 与脚本同时 `Overlay()` 会互相改 PL。
  用文件锁（`fcntl.flock`）且**在下载前**取锁。

## 2. 寄存器：接口契约 → 驱动 → 测试骨架

- **R1 契约优先**：先写机器可读的接口契约（JSON，格式见 `references/contract_format.md`），
  再从契约生成驱动和测试骨架。手写偏移常数散落在 Notebook 里是漂移源。
- **R2 `register_map` 只在 hwh 带寄存器描述时存在**：HLS `s_axilite` 核和打包时声明了
  寄存器的 IP 有 `ip.register_map`（字段级访问如 `ip.register_map.CTRL.AP_START = 1`）；
  自建 RTL/module_ref 通常**没有**，此时用契约 + MMIO。两者都有时，用
  `regmap.cross_check_hwh()` 核对契约与 hwh 的偏移/位宽一致后再用。
- **R3 每个寄存器写清访问语义**：`rw` / `ro` / `wo` / `rc`(读清) / `w1c`(写 1 清)。
  对 `rc`/`w1c` 寄存器**禁止读-改-写**；对 `rc` 寄存器，读一次就要保存全部字段
  （例如 HLS 新版本的 `ap_done` 读清：先读一次判断 idle 再读一次判断 done，第二次永远读不到）。
- **R4 宽地址拆分**：64 位指针/计数分成 `_lo`/`_hi` 两个 32 位寄存器，两个都要写
  （Zynq-7000 物理地址 < 4 GiB 时高半也必须写 0，残值会使访问越界）。
- **R5 偏移对齐与范围**：MMIO 偏移 4 字节对齐、小于 `addr_range`；契约检查器会拒绝越界与重叠。
- **R6 启动-完成握手的归属**：等待 `done` 前确认它属于**这一次**启动：先等 idle → 清旧状态
  → START → 确认 busy/started 抬起（或 ap_idle 落下）→ 再等 done。`busy=1 且 done=1`
  同时出现通常是读到上一次的粘滞 done。
- **R7 HLS `ap_ctrl_hs`**（以生成的 `x<kernel>_hw.h` 为准，不同 Vitis HLS 版本有差异）：
  0x00 控制位 bit0 ap_start、bit1 ap_done、bit2 ap_idle、bit3 ap_ready、bit7 auto_restart；
  0x04 GIE、0x08 IER、0x0C ISR；参数从 0x10 起。用 `hls_ctrl.run_once()` 处理读清与超时。

## 3. DMA 与缓存一致性

- **D1 一致性规则**：PS 写、PL 读之前 `buf.flush()`；PL 写、PS 读之前 `buf.invalidate()`。
  `pynq.allocate` 的缓冲在 `coherent=True` 时这两个调用为空操作，所以**总是调用**是跨板安全写法。
  PYNQ 官方 DMA 驱动的 `transfer()`(发送)会 flush、`wait()`(接收)会 invalidate；
  但**HLS m_axi 主口直接读写 DDR、自建 DMA、或 PL 修改了发送缓冲**时没有人替你做。
- **D2 用物理地址**：给硬件写 `buf.physical_address`（或 `device_address`），不是 `id()`/虚拟地址；
  缓冲必须来自 `pynq.allocate`（物理连续），numpy 普通数组不行。
- **D3 对齐与长度上限从 hwh 取**：无 DRE 时地址须按 `c_m_axi_*_data_width/8` 对齐；
  单次长度上限 `2**c_sg_length_width - 1`（默认宽度常为 14 → 16383 字节）。超限 PYNQ 文档写明会挂死。
- **D4 先启动接收再启动发送**：对回环/流处理 IP，先 `recvchannel.transfer` 再 `sendchannel.transfer`。
  反过来时 AXI-Stream 通常只是反压等待；但带超时/丢包逻辑或无反压（tready 恒 1）的 IP 会丢数据，统一先收后发最稳。
- **D4b 接收缓冲也要先 flush**：接收缓冲若有脏缓存行（例如刚填过哨兵值），DMA 写完后缓存行被逐出会覆盖 DMA 数据；
  所以发送前对 rx 也 `flush()`，完成后再 `invalidate()`。
- **D5 TLAST 决定 S2MM 完成**：PL 不给 TLAST，接收通道永远不完成；PL 给得早，实际长度小于申请。
  结果长度用 S2MM_LENGTH(0x58，即 `recvchannel.transferred`)，不要用自己申请的大小。
- **D6 等待必须有界**：`channel.wait()` 在 PYNQ 2.x 是无超时自旋。生产代码用带 deadline 的轮询
  （`dma.BoundedSimpleDMA` 或自己轮询 DMASR），超时要报告 DMASR 解码而不是只说"卡住"。
- **D7 失败后的缓冲生命周期**：DMA 可能仍在写内存时 `freebuffer()`/让缓冲被 GC，会把 DMA 写进
  别人的内存。出错路径：先复位 DMA（DMACR bit2）→ 确认两通道 halted → 再释放；证明不了就保留引用。
- **D8 不混用**：同一个 DMA 不要同时用官方驱动方法和裸寄存器操作；同一缓冲不要并发给两个通道。

## 4. 黄金参考比对

- **G1 参考模型独立**：黄金值来自独立实现（标准库、已发布向量 KAT、numpy 参考），不要从被测
  代码的表达式复制，也不要用"上一次板上输出"做黄金值。
- **G2 用例分层**：空/最小/边界（如 0、1、对齐-1、对齐、对齐+1、上限）、随机（固定 seed 并记录）、
  背靠背连续调用（检测旧数据残留）。
- **G3 防"假通过"**：每轮至少一个**变异/负向用例**（篡改输入或期望）必须 FAIL；
  比较前把接收缓冲填成哨兵值（如 0xA5），否则"DMA 根本没写"会被旧的正确数据掩盖。
- **G4 差异要诊断**：`golden.compare()` 给出首个差异位置、差异数、以及模式提示
  （全 0/全哨兵 → 未写入或未 invalidate；等于上一次输出 → 旧数据；按字节反转 → 端序；
  整体平移 k → 对齐/偏移；只有尾部错 → 长度/TLAST）。

## 5. 性能与资源数据采集

- **P1 分开报**：端到端墙钟（含 Python/驱动开销）、硬件周期（PL 计数器）、吞吐。不能混成一个"加速比"。
- **P2 分 cold/warm**：第一次调用含 JIT/分配/缓存冷启动；warmup 后重复 N 次，报 min/median/p95，
  记录 N 与 `time.perf_counter_ns`。
- **P3 资源/时序来自报告文件**：`report.parse_utilization()` 读 Vivado `report_utilization`，
  WNS 从 `report_timing_summary` 读；同时记录报告路径和哈希、Design State（Routed/Synthesized）。
- **P4 证据分级**：每个数字带 `measured`（板上实测）/ `tool_report`（Vivado 报告数值，非板上测量）/
  `simulated` / `estimated`（必须写明依据）/ `not_measured`；在模拟/假后端上得到的时间**永远不是**板级性能。
- **P5 指标用 schema 配置，不写死**：用 `references/report_schema.md` 的 JSON 声明数据源（Vivado 资源/时序报告、
  任意结果 JSON）和每个指标的路径、汇总方式、是否必需；取不到的指标记 `not_measured` 并写明原因，必需指标缺失时
  报告失败。换题目/换板卡只换 schema 与数据文件（示例：`examples/report_schema.dma_loopback.json`）。

## 6. 常见错误 → 首查位置（完整表见 `references/failure_signatures.md`）

| 现象 | 最可能原因 | 首查 |
|---|---|---|
| 写寄存器无效果/读回全 0 或 0xDEADBEEF 类 | 打错基址（hwh 旧/重名）、IP 不在该地址 | O1/O3：哈希、`ip_dict` 与 hwh 比对、ID 寄存器 |
| Notebook 卡死无报错 | 无超时的 `wait()`/自旋、驱动构造函数、AXI 从口不应答 | D6/O6；若连 MMIO 读都不返回则是 PL 侧 AXI 从口/时钟复位问题 |
| 结果全 0 或等于上一次 | 缺 invalidate/flush、DMA 未真正写、done 归属错 | D1、G3 哨兵、R6 |
| `DMA Internal Error (transfer length 0?)` | 长度 0、S2MM 申请长度小于实际包、TLAST 异常 | D3/D5，DMASR bit4 |
| `DMA Decode/Slave Error` | 物理地址错（用了虚拟地址/已释放缓冲）、HP 口未使能 | D2，DMASR bit5/6 |
| 每次第二次调用才对/才错 | 读清寄存器被读两次、粘滞 done、未清 ISR | R3/R6 |
| 频率/性能比预期差一倍左右 | FCLK 参考时钟假设不同、hwh 与运行时不同 | O5 |

## 7. 工具用法（`scripts/`，Python ≥3.8，标准库即可；板上额外需要 `pynq`）

```python
import sys; sys.path.insert(0, '<skill_dir>/scripts')
from pynq_skill import artifacts, hwh, overlay_check, regmap, hls_ctrl, dma, golden, report

art = artifacts.check_artifacts('design.bit', manifest='manifest.json')       # 段 A
info = hwh.parse_hwh(art['hwh'])
from pynq import Overlay
ol = Overlay(art['bit'])                                                       # 段 B
overlay_check.verify_overlay(ol, info, required={'my_ip_0': 'xilinx.com:hls:my_ip:1.0'},
                             identity=[('my_ip_0', 0x1C, 0x4D594950)])
contract = regmap.load_contract('my_ip.contract.json')                        # 段 C
regs = regmap.RegisterMap(pynq.MMIO(ol.ip_dict['my_ip_0']['phys_addr'], 0x1000), contract)
```

在 Python 中使用工具时，`<skill_dir>/scripts` 必须在 `sys.path` 上（如上），**上板时把 `scripts/pynq_skill/` 一起拷到板上**。

由契约生成驱动（推荐路径，输出目录自包含，不需要设置路径）：

```sh
python <skill_dir>/scripts/pynq_skill_cli.py gen my_ip.contract.json -o my_ip_drv/
python -m pytest my_ip_drv/          # 生成的结构测试应直接通过；行为测试是 skip 的 TODO，需接独立参考
# 上板：把整个 my_ip_drv/ 目录拷过去（内含驱动、测试和一份 pynq_skill），在该目录下运行
# （或先 sys.path.insert(0, '<my_ip_drv 路径>')），然后
#   from my_ip_driver import MyIp; drv = MyIp.from_overlay(ol, 'my_ip_0')
```

`gen` 默认把 `pynq_skill` 复制进输出目录；加 `--no-vendor` 则不复制，此时按它打印的 `PYTHONPATH` 运行。

其他命令：`python scripts/pynq_skill_cli.py hwh <file.hwh>`（列 IP/基址/FCLK）、
`... artifacts <bit> [--manifest m.json]`、
`... report --utilization u.rpt --results r.json -o report.md`；可配置指标：
`... report --schema s.json --source util=u.rpt --source board=run.json -o report.md`（必需指标缺失时 exit 1）。

离线自测：`python -m pytest <skill_dir>/tests -q`（使用 `fakes.py` 的 MMIO/DMA/非一致缓存模型）。

## 8. 交付检查清单（复制到 PR/报告）

- [ ] bit/hwh/固件路径与 SHA-256、PYNQ 版本、板型已记录
- [ ] 加载后 IP 集合、基址、ID/VERSION、FCLK 已读回并比对
- [ ] 寄存器访问全部经由契约/`register_map`，无散落魔数；rc/w1c 无读-改-写
- [ ] 每个等待都有 deadline，超时报告包含状态寄存器解码
- [ ] DMA：flush/invalidate、物理地址、对齐/上限、先收后发、实际长度、失败后先停再释放
- [ ] 黄金比对：独立参考、边界+随机(seed)+背靠背、哨兵、至少一个变异用例 FAIL
- [ ] 性能：cold/warm 分开、N/统计量、硬件周期与墙钟分列；资源/时序附报告路径
- [ ] 所有数值标注 measured/tool_report/simulated/estimated/not_measured；估算写明依据；失败与未测项保留
- [ ] 报告指标由 schema 声明，必需指标齐全；缺失项以 not_measured 出现而不是被省略

参考：`references/failure_signatures.md`（错误定位表与 AXI DMA 状态位）、
`references/contract_format.md`（接口契约格式与示例）、`references/report_schema.md`（报告指标 schema）、`examples/`（AXI GPIO、HLS 向量加、AXI DMA 回环三份与 Ascon 无关的契约）。
