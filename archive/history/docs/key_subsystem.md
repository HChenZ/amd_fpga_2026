# 密钥子系统（RO-PUF + Device DNA → Ascon KDF）

> 2026-11-01 范围：早期 PUF v1/PL-only 设计与阶段记录；下文“未综合/未上板”不是现在的全仓状态。
> PUF3 复用 PUF v1，但增加软件 HWKEY 选择并使用独立 soc_top/key_mmio 变体。
> keys_rv32 v3 不等于 PUF3 固件，PUF v2/MIN 也不是它的替换品；当前入口见 version_entrypoints.md。

2026-10-25；owner TBD。目标板：正点原子 领航者 ZYNQ7020（`xc7z020clg400-1`，
50 MHz @ U18，MMCM ×2 = 100 MHz 核频）。本文对应代码已落地并通过仿真；
尚未综合/上板。

## 1. 文件与状态

| 文件 | 作用 | 状态 |
|---|---|---|
| `src/rtl/keys/device_dna.v` | 读 57-bit Device DNA（DNA_PORT） | 仿真 PASS |
| `src/rtl/keys/ro_unit.v` | 环形振荡器单元（综合/仿真双模） | 仿真 PASS |
| `src/rtl/keys/ro_puf_core.v` | 256 RO（**RO 自身当时钟**计数）+ 慢时钟域控制 + 跨域握手 + M 次表决 | 仿真 PASS |
| `src/rtl/keys/puf_key.v` | enroll/reconstruct + helper + Ascon p12 KDF → 128-bit key；对外暴露 helper 供回读 | 仿真 PASS |
| `src/rtl/keys/key_mmio.v` | MMIO 状态/控制窗口（Ascon 窗口 0x80 段，**不暴露 key**） | 仿真 PASS |
| `sim/keys/tb_puf_key.v` / `tb_key_mmio.v` / `tb_dna_min.v` | 主流程 / MMIO 窗口 / DNA 位序定位 | PASS |
| `sim/keys/run_key_tests.sh` | 一键跑两套测试 | exit 0 |
| `sim/keys/tb_keys_fw.v` | 跑**真固件**的 SoC 级 TB（KEY_WINDOW=256 提速） | PASS |
| `src/firmware/keys_rv32/` | 自检固件：enroll → 打印 → reconstruct → 判定 | 仿真 PASS（620 words） |
| `sim/keys/DNA_PORT_sim.v` / `BUFG_sim.v` | DNA_PORT、BUFG 的 Icarus 模型 | — |
| `sim/keys/run_puf_key.sh` | 一键跑测试 | exit 0 |
| `build/keys_ro_pblock.xdc` | RO 阵列独立 pblock（X60Y115:X113Y149）+ DONT_TOUCH | — |
| `build/build_keys_sta.tcl` | 集成后 100 MHz STA（含 pblock） | 见 §5 |
| `build/patches/key_subsystem_ascon_mmio_hwkey.patch` | ascon_mmio 加 `key_hw/key_hw_sel` | 可干净应用 |
| `build/patches/key_subsystem_soc_top_inst.patch` | soc_top 实例化 puf_key + 生成 `ro_clk` | 可干净应用 |

集成：

```bash
git apply build/patches/key_subsystem_ascon_mmio_hwkey.patch
git apply build/patches/key_subsystem_soc_top_inst.patch
./sim/keys/run_puf_key.sh          # 期望 ===DONE[RESULT] tb_puf_key PASS
```

## 2. 安全模型（写进报告要能站得住）

- **PUF = 秘密**：RO 频率指纹由制造偏差决定，只有这颗芯片测得出，不存于任何存储。
- **DNA = 绑定**：57-bit 出厂唯一 ID，公开可读，**不是秘密**，作用是把密钥钉死在这颗芯片上。
- **KDF**：
  ```
  s = KDF_CTX ^ { "KEYGEN04", "KEYGEN03", puf_bits[127:0], {7'b0, dna[56:0]} }
  key[127:0] = P12(s)[127:0]
  ```
  PUF 位与 DNA 都参与；缺任一方都重建不出同一把钥匙（仿真已证：helper 被破坏时
  走 DNA-only 回退，得到的 key 与纯 DNA 模式完全一致）。

## 3. 工作流程

```
start ─► DNA 读出(57b) ─► [跨域] RO 采样(M 次 × WINDOW) ─► 逐位多数表决 ─► [跨回]
      ─► [mode=1] 记录 ref=raw, mask=~dither
         [mode=0] 与 ref&mask 比对：一致→用 raw&mask；不一致→mismatch+回退 DNA-only
      ─► P12 KDF ─► key[127:0] + key_valid
```

### 3.1 两个时钟域（为什么这样分）

| 域 | 时钟 | 内容 |
|---|---|---|
| 核心域 | `clk`（100 MHz） | DNA 读取、KDF、key 寄存器、与 ascon_mmio 的握手 |
| PUF 域 | `ro_clk`（顶层 clk/4 = 25 MHz，过 BUFG） | RO 使能/窗口/清零、256 个计数器的快照、逐位比较与表决 |

域间只传两个翻转脉冲（`req_tgl` / `done_tgl`，两级同步），`raw/dither` 在 done 之后保持静态，
核心侧直接搬。这样 256 个计数器和表决逻辑不会挂在 100 MHz 关键路径上。

### 3.2 为什么计数器要用 RO 自己当时钟（重要修正）

最初的草稿（以及 `../IO/ro_puf_top.v`）是用系统时钟去数 RO 的上升沿。这在硬件上**测不出频率**：
7 系列 LUT 构成的 RO 典型 150~300 MHz，比 100 MHz 采样时钟快，边沿检测直接混叠，
计数只反映相位而非频率。正确做法是：

```
always @(posedge osc[k]) begin        // 计数器时钟 = 该 RO
    if (cnt_clr)     cnt[k] <= 0;
    else if (cnt_en) cnt[k] <= cnt[k] + 1;
end
```

窗口结束后先停计数（计数器变静态），再在 ro_clk 域做快照与比较，
避免读一个还在跳的计数器造成的亚稳态/撕裂。`cnt_clr` 必须保持 ≥4 个 ro_clk 周期，
因为清零只在 RO 有时钟时才能生效（所以清零点在 RO 已起振之后）。


- `mask[i]=1` 表示该位在 M 次采样里稳定（用于重建），`dither[i]=1` 表示不稳定。
- 连续两次 reconstruct 得到同一把 key（仿真已验证）。
- 无 helper（`INIT_MASK=0`）时**不会**产生一把随机的钥匙，而是报 `mismatch+fallback`，
  让上层知道"这把钥匙是降级的"。

### 3.3 RO 必须用原语固化（否则综合会把 5 级环压成 1 个 LUT）

第一版用 `assign` 链搭 5 级环，综合后 DRC 报：

```
CRITICAL WARNING: [DRC LUTLP-1] Combinatorial Loop Alert: **1 LUT cells** form a combinatorial loop
  ... cells in the loop are: .../g_ro[0].u_ro/osc_INST_0
```

即 **5 级反相链被合并成一个 LUT**，`STAGES` 参数完全失效；而且 256 个 RO 只有 101 条环告警，
说明还有一部分被合并/吞掉了 —— 这会让部分 challenge 位恒定，熵大幅下降。

修正：`ro_unit` 的 `SYNTHESIS` 分支改为**显式 LUT 原语**，每级 DONT_TOUCH：

```verilog
(* DONT_TOUCH = "yes" *) LUT2 #(.INIT(4'b0010)) u_nand (.O(n[0]), .I0(en), .I1(n[STAGES-1]));  // ~(en & n4)
(* DONT_TOUCH = "yes" *) LUT1 #(.INIT(2'b01))   u_inv  (.O(n[i]), .I0(n[i-1]));                 // 4 级取反
```

并在 **opt_design 之前**（网表已存在时）显式承认这些环：

```tcl
# build/keys_ro_allow_loops.tcl，由 build_keys_sta.tcl 挂到
#   STEPS.OPT_DESIGN.TCL.PRE
foreach nt [get_nets -quiet -hier -filter {NAME =~ "*u_puf_key/u_puf/g_ro*/u_ro/n*"}] {
    set_property ALLOW_COMBINATORIAL_LOOPS TRUE $nt
}
```

⚠ 两个坑（都实测踩过）：

1. **不能写在 XDC 里**：约束文件在综合前被读入，那时 net 不存在，`get_nets` 返回空、属性被静默丢弃。
2. **不能用层次名过滤**：综合后 `u_puf` 会被打平，net 名变成 `u_puf_key/...`，
   `*u_puf_key/u_puf/g_ro*/u_ro/n*` 匹配不到任何东西（第一次钩子就报了 `nets_tagged=0`）。
   正确做法是从 `*u_ro/*` 的 LUT 单元出发、按**引脚**找 net，对打平免疫：

```tcl
foreach c [get_cells -quiet -hier -filter {NAME =~ "*u_ro/*"}] {
    foreach p [get_pins -quiet -of_objects $c -filter {DIRECTION == "OUT"}] {
        foreach nt [get_nets -quiet -of_objects $p] {
            set_property ALLOW_COMBINATORIAL_LOOPS TRUE $nt
        }
    }
}
```

实测该钩子：`ro_lut_cells=1280 nets_tagged=1280` —— 正好 **256 RO × 5 LUT**，说明每根都是 5 级环。

这样级数可控、每根 RO 都是 5 级；DRC 的 LUTLP-1 也变成"已显式承认"而不再刷屏。


## 3.4 MMIO 窗口（基址 0x3000_0000，字索引 = 偏移 >> 2）

挂在 Ascon 窗口的 **0x80 段**（`ascon_addr_sel` 32..52）—— 这样不用改共享的
`bus_interconnect.v`：`ascon_mmio` 对这些地址本来就读 0，`soc_top` 把
`ascon_rdata = ascon_rdata_core | key_rdata`，未选中恒 0，OR 合并安全。

| 偏移 | 名字 | 读/写 | 位定义 |
|---|---|---|---|
| 0x80 | STATUS | R | `[0]`busy `[1]`key_ready(粘滞) `[2]`enrolled `[3]`mismatch(粘滞) `[4]`fallback(粘滞) `[5]`done(粘滞) `[15:8]`quality |
| 0x84 | CTRL | W | `[0]`START(自清，busy 时忽略) `[1]`ENROLL(保持) `[2]`CLEAR(清粘滞位) |
| 0x88 | DNA_LO | R | `dna[31:0]` |
| 0x8C | DNA_HI | R | `{7'b0, dna[56:32]}` |
| 0x90 | QUALITY | R | `{24'b0, quality}` |
| 0x94..0xA0 | REF0..3 | R | helper 参考位（enroll 产物，回填 `KEY_INIT_REF`） |
| 0xA4..0xB0 | MASK0..3 | R | helper 可用掩码（回填 `KEY_INIT_MASK`） |
| 0xB4..0xC0 | DITHER0..3 | R | 本次采样不稳定位（P02 统计） |
| 0xC4..0xD0 | RAW0..3 | R | 多数表决后的原始响应（P02 统计） |

**密钥不在这个窗口里**：`key` 只在 `puf_key → ascon_mmio` 的内部通路上，CPU 既不能写也不能读。
可读的 DNA / helper / quality 都是公开量或降级指示。

### 3.5 ILA 还是 MMIO？（为什么两个都要，但主力是 MMIO）

| 维度 | ILA | MMIO |
|---|---|---|
| 接入 | Vivado 调试核改网表 | RTL 模块，属于设计 |
| 访问 | JTAG + GUI | 固件 load → UART → 任意终端/脚本 |
| 采样 | 全速、带触发、看波形 | 一次一字，串口速率 |
| 能否留最终设计 | **不能**（占 BRAM、扰动布局） | 能 |
| 自动化 | 难 | **易**（50 次上电统计 BER） |

结论：**enroll 回读、稳定性统计、演示**都用 MMIO；ILA 只在首次 bring-up
（DNA 位序、PUF 全是 0 时查 `cnt[i]` 有没有动）临时插一次，之后从 bitstream 里摘掉。
因为本设计 WNS 只剩 0.6%，**带 ILA 的 run 出来的时序不能当验收证据**。

## 3.6 自检固件（`src/firmware/keys_rv32/`）

上板后**不用开 ILA、不用改 RTL** 就能跑完整流程：

```bash
bash src/firmware/keys_rv32/build.sh     # 交叉编译 -> build/local/keys_fw/keys.hex
bash sim/keys/run_keys_fw.sh             # 仿真跑同一份固件（tb_keys_fw）
```

固件流程（`main.c`）：
1. 打印上电 STATUS（puf_key 在上电约 0xFFFF 拍后自动尝试一次 reconstruct，helper 未烧时
   这里必然是 `mismatch|fallback` —— 属预期，不是故障）
2. `CTRL=0x4` 清粘滞 → `CTRL=0x3`（START+ENROLL）→ 轮询 `STATUS[5]`
3. 打印 quality / DNA / REF / MASK / DITHER / RAW
4. `CTRL=0x4` → `CTRL=0x1`（START，reconstruct）→ 轮询 `STATUS[5]`
5. `mismatch`/`fallback` 都为 0 且 `key_ready=1` 才打印 `PASS`

仿真实测输出（`tb_keys_fw`，KEY_WINDOW=256、`KEY_SIM_DNA=57'h0123_4567_89AB_CD`）：

```
=== KEY SUBSYSTEM SELF-TEST ===
STATUS boot : 0000003a          <- ready|mismatch|fallback|done：helper 还没烧，预期
STATUS enrol: 00008026          <- ready|enrolled|done, quality=128
DNA         : 000123456789abcd
REF         : 75df75df 75df75df 75df75df 75df75df
MASK        : ffffffff ffffffff ffffffff ffffffff
DITHER      : 00000000 00000000 00000000 00000000
RAW         : 75df75df 75df75df 75df75df 75df75df
STATUS recon: 00008026
PASS key subsystem: enroll + reconstruct stable
DONE
```

**仿真里的 REF/RAW 是 `75df75df` 循环、DITHER 全 0、quality=128，这是 RO 行为模型的产物**
（仿真里每根 RO 的周期由 `SIM_DIV_*` 决定、相邻 RO 只差固定档位，且没有抖动模型），
**不能拿它判断真实 PUF 质量**。真实板子上这三项都会不同：quality 会小于 128、DITHER 非 0、
REF 应当没有周期性。上板看到 `75df75df` 这种循环图案才是异常。

TB 侧另有一条 `framing_err` 计数：UART 监视器会校验 stop bit，坏帧打 `?` 并计数。
仿真结论要求 `framing_err=0`，否则说明串口证据本身不可信。

## 4. 上板流程（必须按顺序，前两步不做完不要用它加密）


### 步骤 0：上电点灯
先按 `docs/board_bringup_plan.md` 阶段 2 把最小系统点亮（LED 心跳 + UART hello）。
密钥子系统在 `KEY_USE_PUF=0` 下可以先跑，确认不会把自己锁死。

### 步骤 1：核对 DNA 位序（`SHIFT_SKIP`）
1. Vivado Hardware Manager → 连上板子 → `Hardware Device Properties` 里读 **Device DNA**（或在
   Programmer 里 "Read Device DNA"）。
2. 把设计里 `device_dna` 读到的 57-bit 值（可通过 ILA 抓 `u_puf_key/dna_o`）与它**逐位**比对。
3. 若整体错一位：把 `device_dna` 的 `SHIFT_SKIP` 取反（1↔0）重新综合。
   原因：`DNA_PORT` 的 `DOUT` 是 SHIFT 有效后由寄存器给出，第一个 SHIFT 拍采到的是
   载入拍遗留值；不同工具/版本对该相位表述略有差异，**必须用实测对齐一次**。

### 步骤 2：enroll（一次性，全部走 MMIO + 串口，固件见 §3.6）
1. 顶层参数 `KEY_INIT_REF=0`、`KEY_INIT_MASK=0`，烧录。
2. 固件写 `CTRL = 0x3`（START + ENROLL），轮询 `STATUS[5]`（done）一直到 1。
3. 打印 `STATUS`（看 `quality`）、`DNA_LO/HI`、`REF0..3`、`MASK0..3`：
   ```c
   *(volatile uint32_t*)0x30000084 = 0x3;                  // start + enroll
   while (!(*(volatile uint32_t*)0x30000080 & (1u<<5))) ;  // wait done
   uint32_t st = *(volatile uint32_t*)0x30000080;          // quality = st>>8
   printf("DNA  = %08x%08x
", *(volatile uint32_t*)0x3000008c & 0x1ffffff,
                                 *(volatile uint32_t*)0x30000088);
   printf("REF  = %08x %08x %08x %08x
", REG(0x94), REG(0x98), REG(0x9c), REG(0xa0));
   printf("MASK = %08x %08x %08x %08x
", REG(0xa4), REG(0xa8), REG(0xac), REG(0xb0));
   ```
4. 把 `REF`/`MASK` 填回顶层参数 `KEY_INIT_REF`/`KEY_INIT_MASK`，重新综合 → 下次上电直接 reconstruct。

### 步骤 3：reconstruct 验证
1. 重新上电 ≥5 次，每次确认 `key_valid=1`、`mismatch=0`。
2. 用这把 key 跑一次 Ascon AEAD（CT/tag 与黄金参考比对）；应稳定一致。
3. **若出现 `mismatch=1`**：说明有稳定位翻转，先加大 `M`（5→7/9）或 `WINDOW`，再考虑纠错码。

### 步骤 4：稳定性测量（P02）
- 上电 ≥50 次、记录每次 `raw` 与 `dither`；温度/电压若可调，各做一组。
- 统计：`BER = 翻转位数 / 总位数`、唯一性（不同板之间 Hamming 距离应 ≈ 50%）。
- 若 BER > ~5%：把 `mask` 全量启用（100% 丢弃抖动位）+ 提高 M；仍不够则上 BCH（P03）。

## 5. 资源与时序影响（**已按 100 MHz 实测**）

集成方式：`build/local/rtl_keys` = `src/rtl` + 两个补丁；`build/keys_ro_pblock.xdc` 把 RO 阵列
单独约束到器件上沿；实现策略沿用生产策略 `Performance_ExploreWithRemap`。
脚本 `build/build_keys_sta.tcl`，证据 `build/reports/keys_sta_20261025/`。

| 指标 | 不含密钥子系统 | PUF（RO 被压成 1 LUT） | PUF（256×5 原语 RO） | **PUF + key_mmio（最终，`keys_sta_final`）** |
|---|---|---|---|---|
| WNS | +0.087 | +0.051 | +0.058 | **+0.023** |
| TNS / 失败端点 | 0 / 0 | 0 / 0 | 0 / 0 | **0 / 0** |
| 最差路径 | CPU | CPU | CPU | CPU `id_ex_u/rs1_o→func_sel_o` |
| WHS | +0.033 | +0.035 | +0.020 | **+0.015** |
| LUT | 13478 | 13924 | 14802 | **17022**（+3544） |
| FF | 17187 | 22088 | 22094 | **28543**（+11356） |
| BRAM | 38.5 | 34.5 | 34.5 | 34.5 |
| DRC LUTLP-1 | — | 256 | 256（钩子未生效） | **0（钩子生效）** |
| 布线错误 | 0 | 0 | 0 | **0** |

`key_mmio` 的代价主要是面积（+3544 LUT / +11356 FF）：21 个寄存器的读 mux、4×128 位回读通路
（REF/MASK/DITHER/RAW），以及 RO 环 net 被 `ALLOW_COMBINATORIAL_LOOPS` 保护后 opt 不能再合并
其周边逻辑。时序上并不吃亏 —— `keys_sta_mmio2`（同配置首跑）是 +0.023，`keys_sta_final`
（修正 mismatch/fallback 语义后重跑）是 **+0.168**，两者差 0.145 ns 来自布局差异而非逻辑深度，
说明这个利用率下 WNS 对布局种子敏感，**报数要带 run 名字**。
若面积/时序吃紧，可以砍掉 DITHER/RAW 回读（8 个字）或把 `N_RO` 从 256 降到 128（计数器 FF 减半）。

最差路径始终在 CPU（`id_ex → dcache`），**不在密钥子系统里**，说明 pblock + 慢时钟域把 PUF
完全隔离出了 100 MHz 关键路径。

**RO 结构核查**：DRC 报 `5 LUT cells form a combinatorial loop`，且报告里出现
`g_ro[0]..g_ro[255]` 共 **256 个** RO 索引 —— 每个 RO 确实是 5 级原语环，没有被合并或吞掉。
（stdout 里只打印了 101 条是 Vivado 的打印上限，DRC 报告本身覆盖全部 256 根。）


**落点核查**（`build/probe_keys_placement.tcl`，对 `keys_routed.dcp`）：

```
PUF_LEAVES 7275        PUF_IN_PBLOCK 7275      PUF_BBOX X=56..113 Y=102..149
CPU_BBOX   X=27..96    Y=0..92                → 与 PUF 区域完全不重叠
```

7275 个单元全部落在 `pb_ro_puf` 内，CPU 被压在下半部，两者物理隔离。

采样耗时：`M × (DWELL + WINDOW)` = 5 × (256 + 16384) 个 ro_clk（25 MHz）≈ **3.3 ms**。

⚠ 最终配置（PUF + key_mmio）余量只有 **+0.023 ns（0.23%）**。若演示要更稳：

| 核频 | WNS | 说明 |
|---|---|---|
| 100 MHz | +0.023（实测） | 芯片级收敛，无 IO delay / 无 PS7 |
| 80 MHz | ≈ **+2.52**（算术：周期 +2.5 ns，到达时间不变） | cycles/cpb/加速比不变 |
| 75 MHz | ≈ +3.38 | 同上 |

（注：用 `reset_timing` 后重建输入时钟再测 80 MHz 会让 MMCM 派生关系失效、给出 −3 ns 的
假数据，所以这里改用周期差的算术值；100 MHz 的 +0.023 是 10-26 14:01 的最终配置实测，
+0.051 / +0.058 是 PUF-only 阶段两次独立 run 的实测值。无密钥子系统的基线是 **+0.087**，
不是 +0.039——后者是带强制复制钩子的实验臂。）

## 6. 已知限制（不要在报告里忽略）

- **仿真 PUF 响应是合成的**（`75df75df` 循环、DITHER=0、quality=128），只证明数据通路与
  协议正确，不证明 PUF 熵/稳定性；真实指标必须上板测 ≥50 次上电。
- 上电时若 helper 未烧入，STATUS 会是 `mismatch|fallback`，此时密钥是 DNA-only 降级密钥，
  **不能拿去加密真实数据**。


- 仿真里的 RO 频率差是注入的确定性差值，**不能证明**随机性/唯一性/稳定性；这三项只能上板测。
- helper data 存在片内寄存器（由参数回填），**掉电后由 bitstream 恢复**；
  换板/换 bitstream 就必须重新 enroll（比赛演示可接受，量产不可）。
- DNA 的熵上限是 57 bit 且公开；单独用 DNA 派生只是"设备绑定"，不是秘密。
- 目前没有 MMIO 状态/回读口，enroll 数据要靠 ILA 或临时加寄存器搬出来。

## 7. 待办

- [x] `key_mmio.v`：STATUS / CTRL / DNA / QUALITY / REF / MASK / DITHER / RAW 共 21 个字，
      enroll 结果可从串口打印（仿真 PASS，寄存器映射见 §3.4）。
- [ ] `ascon_mmio` 的 nonce 策略：AEAD 要求 (key, nonce) 不重用；当前 nonce 仍由 CPU 写，
      需加"硬件递增计数器 + 与 key 绑定"的规则。
- [ ] 综合 + 上板：DNA 位序对齐 → enroll → 回填 → reconstruct ×5。
- [ ] P02 稳定性统计（≥50 次上电）、P03 纠错（若 BER 高）。
- [ ] 报告用的性能数据：enroll/reconstruct 各多少 ms，占多少 LUT/FF。
