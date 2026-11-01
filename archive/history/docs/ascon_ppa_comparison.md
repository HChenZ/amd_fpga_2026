# Ascon 三实现 PPA 对比与收敛历程（I08 收口）

> 2026-11-01 范围：历史三实现/时序快照的 PPA 记录，不是三份当前 PUF3 独立核 PPA。
> PUF3 整个 overlay 的资源与时序在其 candidate 报告中；指标不得跨源集混用。当前入口见 version_entrypoints.md。

日期 2026-10-18；owner TBD。本文件以芯片级 STA 证据收口 I08（PPA comparison）；
板上 PPA 仍待 B03（板型核验）与 V01（实板回归）。所有数字均可追溯到报告文件，
缺失项标 not_measured。

## 1. SoC 资源演进（同一 top_pl_bram，xc7z020clg400-1，Vivado 2025.2）

| 阶段 | 策略 | WNS | TNS | 失败端点 | LUT | FF | BRAM | DSP |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| HEAD f52bc49 基线 | Vivado Implementation Defaults | -0.942 | -433.585 | 1579 | 11562 | 15949 | 38.5 | 4 |
| HEAD + 33 策略扫掠最优 | Performance_ExploreWithRemap | -0.118 | -1.008 | 22 | 11643 | 15949 | 38.5 | 4 |
| A/C/B RTL 修复后 | Performance_ExplorePostRoutePhysOpt | **+0.001** | 0 | 0 | 11680 | 15992 | 38.5 | 4 |
| A/C/B RTL 修复后 | Performance_ExploreWithRemap | **+0.007** | 0 | 0 | 11752 | 16040 | 38.5 | 4 |

- A = ascon_ise.v 局部复位寄存器化（消 93 端点）；C = 乘法器输入/输出寄存器化 +
  done 保持到 ack（消 48 端点，mult.v 新模块）；B = store/MMIO 绕过 MISS_CAPTURE
  （周期代价收回）。资源代价：相对 HEAD 约 +120~190 LUT、+43~91 FF，BRAM/DSP 不变。
- 证据：`build/reports/timing_acb_20261018/{postroute,remap}/route_utilization.rpt`、
  `route_timing.rpt`、`build/reports/strategy_sweep_20261017/`。

## 2. 周期与加速比（16B 加密，warm 仿真实测，非板上）

| 实现 | cycles | 加速比（vs 软件） | 备注 |
|---|---:|---:|---|
| 纯软件（sw） | 17353 | 1.0× | CPU 上 C 实现 |
| MMIO 全卸载（hw） | 670 | 25.9× | START→轮询完成往返 |
| ISE 置换加速（ise） | 2496 | 7.0× | inline asm 置换 |
| crypto 核心延迟 | 99 | — | 纯 crypto_aead 延迟，不计寄存器往返 |

- 证据：`data/ascon/results/key_lifecycle/{sw,hw,ise}_timing_acb_*.json`；
  99 cyc 来自 `project_log/actual_progress.md` V06 条目（历史仿真实测）。
- 周期口径：simulated（Icarus/vvp 仿真实测，非板上 mcycle）；板上基准待 V01/Y05。

## 3. 时序收敛历程（-0.177 → +0.007）

1. **基线墙**：HEAD 默认策略 WNS -0.177、31 失败端点，最差路径
   `id_ex/rs1_o_reg → dcache/bus_wmask_r_reg/CE`（路由延迟 70%）。
2. **策略扫掠（33/33 内置策略）**：最优 Performance_ExploreWithRemap -0.118/22 端点；
   详见 [ascon_strategy_sweep.md](ascon_strategy_sweep.md)。结论：单靠策略差 0.118。
3. **RTL 三堵墙**（对 fix_r1 的 156 失败端点逐点归因）：
   - dcache miss→bus 请求路径（11 端点）：MISS_CAPTURE 流水化 + MMIO 握手修复
   - ascon_ise s_reg 复位（93 端点，-0.128）：复位局部寄存器化
   - ex_stage 乘法器（48 端点，-0.105）：输入/输出寄存器化，multi-cycle
4. **收敛**：双策略 STA 通过。PostRoute WNS=+0.001/WHS=+0.031；
   **Remap WNS=+0.007/WHS=+0.023**（推荐 Remap 为生产策略）。TNS=0，setup/hold/pulse
   失败端点全 0，路由错误 0。证据：`docs/timing_acb_validation.md`。

## 4. 边界声明

- 100 MHz **芯片级 STA** 通过；板级 3 输入/3 输出 **IO delay 未约束**，板型/pinout
  未核验，bitstream/实板 KAT 未做 —— 不是上板验收。
- 收敛余量 1-7 ps 处于布局噪声量级；任何后续 RTL/XDC/IP 改动必须按
  [freeze_checkpoint_20261018.md](freeze_checkpoint_20261018.md) 全套复验。
- 板上 cycles/PPA = not_measured（待 B03/V01/Y05）。
