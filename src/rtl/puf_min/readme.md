# `src/rtl/puf_min` — PUF-MIN 最小闭环 RTL

> 2026-11-01 范围：独立无RV32的PUF-MIN实验，复用keys_v2采样器；不是当前PUF3源集。
> 下文资源/仿真属于其探索记录，未声明已发布可用候选或板测；程序/参数保持不变。

任务号 `PUF-MIN`（`tasks/puf_fix_and_min_goal_20261030.md` §4.2 / §4.3 / §4.5）。
owner TBD。**复用** `src/rtl/keys_v2/` 已有的 RO 采样器，不修改它。

| 文件 | 作用 |
|---|---|
| `puf_min_axil.v` | 4KiB AXI4-Lite 寄存器从机 + 采样器/DNA 封装 + 粘滞状态 |
| `puf_min_top.v` | 顶层包装：`ro_array_v2`（物理环阵列）+ `puf_min_axil` |

## 层次与单时钟

```
puf_min_top
├── ro_array_v2 #(.N(256),.STAGES(5))  bank     ← 1280 个 LUT 的物理环阵列
└── puf_min_axil
    ├── ro_puf_core_v2  sampler                 ← 复用 keys_v2，clk 与 ro_clk 接同一个网络
    └── device_dna      dna_reader               ← 复用 src/rtl/keys/device_dna.v
```

`puf_min_axil` 内部把 `ro_puf_core_v2` 的 `.ro_clk` 直接接到 `.clk`，因此整个设计
**只有一个时钟输入**（PS 的 FCLK0 = 100MHz）。`clk == ro_clk` 下采样器仍然正确，
证据见 `sim/puf_min/tb_ro_core_single_clock.sv`（生产参数 6/6 次采样逐位一致、
事务号递增、busy 期间 START 报 0x40、复位后恢复）与
`docs/puf_min_explore_20261030.md` 的 E1 一节。

RO 环本身仍是**异步物理环路**：不定义 RO 时钟、不虚构最小周期、不加全局
`false_path`。剩余无时钟 pin / 未约束端点数量在实现报告里如实列出。

## 寄存器 ABI（4KiB，PS 基址 `0x40000000`）

| 偏移 | 名称 | 读写 | 说明 |
|---|---|---|---|
| 0x00 | ID | R | `0x4E494D50`（"PMIN"），与已有 ID 均不冲突 |
| 0x04 | VERSION | R | 1 |
| 0x08 | CTRL | W | bit0 START（脉冲），bit1 CLEAR（脉冲）。两位置 1 时 **CLEAR 优先** |
| 0x0C | STATUS | R | bit0 busy，bit1 done（粘滞），bit2 valid（粘滞），bit3 locked，bit4 dna_ready |
| 0x10 | ERROR | R | 最近一次采样结束时的 `core.error_code`（见下表） |
| 0x14 | TXN | R | 事务号：每个 START +1；只有模块复位归零，**CLEAR 不清零** |
| 0x20..0x2C | RAW[0..3] | R | 128-bit 响应；`valid=0` 时读 0 |
| 0x30 | DNA_LO | R | `dna[31:0]` |
| 0x34 | DNA_HI | R | `{7'b0, dna[56:32]}` |
| 0x40 | CNT_SEL | W | 计数器下标 0..255（默认 0） |
| 0x44 | CNT_VAL | R | 该计数器在最近一次成功采样里的计数；`valid=0` 时读 0 |

未映射偏移、非 4 字节对齐、写只读寄存器 → AXI `SLVERR`（读数据返回 0）。

`ERROR` 位含义（与 `ro_puf_core_v2` 一一对应）：

| 值 | 含义 |
|---|---|
| 0x01 | RO 看门狗：`RO_DEADLINE` 内没有看到振荡沿 |
| 0x02 | 核心 deadline 到期 |
| 0x04 | 某环计数为 0 |
| 0x08 | 某对环计数相等（无法判定方向） |
| 0x10 | 计数器饱和 |
| 0x20 | 全部比较方向相同 |
| 0x40 | busy 期间再次 START（或已锁定）→ 同时置 `locked` |
| 0x85 | 内部超时 |

## `done` / `valid` 为什么是粘滞的

`ro_puf_core_v2` 的 `done`/`valid` 只有 1 拍。PS 侧用 MMIO 轮询不可能可靠命中单拍，
所以寄存器层把它们变成粘滞位，并在下一个 START 或 CLEAR 时清除；
`RAW`/`ERROR` 在 `core_done` 那一拍一起锁存，读回不会因为采样器内部继续变化而漂移。

## 诊断计数回读的代价（实测，别随手改）

`CNT_VAL` 要能读任意一个计数器。第一版直接对 5120 位向量做变量切片
`core_counts[cnt_sel*CW +: CW]`（`cnt_sel*20`），综合器把它展开成一堆比较器：
`puf_puf_core` 的 OOC 综合结果是 **18170 LUT / 14754 FF**（证据
`data/advanced/puf_min/impl_20261030_115206`），远超"最小版"应有的规模。

改法是**按 32 位对齐打包**，让下标乘法退化成移位：

```verilog
generate for (gc = 0; gc < 2*BITS; gc = gc + 1) begin: pack
    assign counts_packed[gc*32 +: CW] = core_counts[gc*CW +: CW];  // 常量下标
end endgenerate
wire [CW-1:0] cnt_word = counts_packed[cnt_sel*32 +: CW];           // 纯移位索引
```

实测效果见 `docs/puf_min_explore_20261030.md` E4 与对应 `impl_*` 证据目录。
`sim/puf_min/tb_puf_min.sv` 的 CNT 用例（c0/c1/c128/c129 的差频方向）覆盖这条路径。

## 明确不宣称

RAW 可读、**没有保密性**；DNA 是唯一 ID 不是秘密；不提供 ECC、熵估计、安全提取器、
安全启动、防回滚、多板唯一性、温度/电压/老化可靠性。
