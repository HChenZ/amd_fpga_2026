# pynq_puf3：三模式 SW/HW(MMIO)/ISE 服务 + PUF v1，单一 bitstream

2026-10-30；owner TBD。独立入口：不打开、不修改 PYNQ 发布版
（`../vivado_zynq7000_xc7z020_pynq/release/`）、`../vivado_zynq7000_xc7z020_pynq_puf/`
与 JTAG 工程；共享的 `src/rtl/soc_top.v`、`src/rtl/keys/key_mmio.v` 也没有改。

## 为什么需要它

| overlay | 三模式加速比 | PUF |
|---|---|---|
| PYNQ 发布版（`rtl_p0`，ID `PYNQ`） | 有，已上板 | 无 |
| pynq_puf（`src/rtl` PUF 版，ID `PFU1`） | 无（固件是 keys_rv32 自检） | 有，仍是 NOT_RUN |
| **pynq_puf3（本目录，ID `PQF3`）** | 有 | 有 |

pynq_puf 不能直接换成三模式固件，原因是 `src/rtl/soc_top.v` 会在 PUF 密钥就绪时
（复位后约 0.65 ms）**自动并永久**把 `key_hw_sel` 置 1。之后 `ascon_mmio` 忽略 CPU 写入的 KEY，
HW 模式就过不了官方 KAT。仿真反例证明了这一点：同一份固件配原 RTL，开机自检
mask 只有 `0x05`，HW 模式丢失（`reports/cosim_mutant_autolock.log`）。

## 改了什么

| 层 | 文件 | 变化 |
|---|---|---|
| RTL | `rtl/soc_top.v`（复制自 `src/rtl/soc_top.v`） | `key_hw_sel = hwkey_on & key_have`，不再在 `key_valid` 时自动锁定 |
| RTL | `rtl/key_mmio.v`（复制自 `src/rtl/keys/key_mmio.v`） | CTRL[3] HWKEY_ON、CTRL[4] HWKEY_OFF（OFF 优先，复位为关）；STATUS[6] key_hw_sel、STATUS[7] hwkey_on |
| 固件 | `src/firmware/pynq_svc_puf/` | 由 pynq_svc 加上 Y01P/Y01K 帧；固件 ID `pynq-svc-puf3`；开机自检和 Y01E 前先关 HWKEY |
| PS / board test | `src/pynq_puf3/pynq_puf3_board_test.ipynb` | 单文件 Notebook，内含 PQF3 驱动、`Puf3BridgeRegs`、`PynqPuf3Transport.puf_command()`、KAT、benchmark 和 PUF 流程 |
| BD | `build.tcl` | 与 pynq_puf 相同（FIXED_IO/DDR 外接、RO pblock、门禁），只换 COE、变体 RTL 和 ID `0x33465150` |

`puf_opt_pre.tcl` 是 `../vivado_zynq7000_xc7z020_pynq_puf/puf_opt_pre.tcl`（56929b0）的快照；
`pynq_puf3_timing.xdc` 是同目录 `pynq_puf_timing.xdc`（ro_clk 生成时钟）的快照，
内容与提交 5eb64a5 中的版本逐字节一致。

Y01Q/Y01R/Y01S/Y01E 的字节格式与发布版完全一致，所以三模式 cycles 的测量口径不变。
但加速比必须在本 bitstream 上**重新测量**，不能沿用发布版的数字。

### PUF 帧（Y01P → Y01K）

Y01P 16B：`'Y01P' | u32 version=1 | u32 cmd | u32 seq`。cmd：0 STATUS、1 ENROLL、
2 RECONSTRUCT、3 HWKEY_ON、4 HWKEY_OFF。

Y01K 112B：`magic | u16 version | u16 flags | u32 cmd | u32 seq | u32 result | u32 STATUS |
u32 DNA_LO | u32 DNA_HI | u64 op_mcycle | REF16 | MASK16 | RAW16 | DITHER16 | 8B 0`。
result：0 OK、1 TIMEOUT、2 NOT_ACCEPTED、3 BAD_CMD、4 BAD_VERSION、5 NO_PUF_KEY、6 BUSY_STUCK。

固件策略（不是硬件强制）：ENROLL/RECONSTRUCT 开始前关 HWKEY；HWKEY_ON 只在
key_ready=1、enrolled=1、mismatch=0、fallback=0、busy=0 时执行，否则返回 NO_PUF_KEY，
所以 DNA-only 降级密钥不会被当作 PUF 密钥使用。

## 构建与离线检查（仓库根目录）

```sh
python -X utf8 src/firmware/pynq_svc_puf/build.py
python -X utf8 sim/pynq_puf3/run.py
vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf3/build.tcl -notrace -tclargs Performance_ExtraTimingOpt 4
vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf3/ro_corner_sta.tcl -notrace -tclargs build/local/pynq_puf3/vivado/pynq_puf3.runs/impl_1/pynq_puf3_wrapper_postroute_physopt.dcp build/local/pynq_puf3/ro_sta
python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf3/package.py
```

`ro_corner_sta.tcl` 是 `../vivado_zynq7000_xc7z020_pynq_puf/ro_corner_sta.tcl`（5eb64a5）的逐字节快照。
`package.py` 会检查 `ro_corner_sta.txt` 第一行记录的 dcp，必须就是出 bit 的那个 checkpoint。

当前候选的实际流程：第一次 `build.tcl` 使用 RefinePlacement，未开布线后 phys_opt，WNS −0.123，
被门禁拦下、没有生成 bit。之后 `explore_impl.tcl -tclargs 2 Performance_ExtraTimingOpt
Performance_Explore Performance_RefinePlacement Performance_NetDelay_low` 在同一综合网表上
跑了 4 个实现，最后由 `finalize_run.tcl -tclargs impl_2 Performance_ExtraTimingOpt` 复查门禁并写 bit。
`build.tcl` 的默认值已改成同一配方（ExtraTimingOpt + 布线后 phys_opt），但还没有从头重跑验证。

`build.tcl` 拒绝复用已存在的 `build/local/pynq_puf3/vivado`。以下任一条件不满足就停止，
不复制 bit：setup/hold ≥ 0、没有 DRC Error/Critical Warning、没有 `Netlist 29-160`、
1280 个 RO LUT 全部分配到 `pb_ro_puf`。`package.py` 会复查这些门禁，并另外检查：
cosim 两个用例、固件 bin 哈希、变体 RTL 哈希，以及生成的 `.mif` 与 COE 逐字一致。

## 离线结果

候选（2026-10-30，离线门禁 PASS，board NOT_RUN），完整信息见 `candidate/manifest.json`：

| 项 | 结果 |
|---|---|
| 实现 | 综合使用 Vivado Synthesis Defaults；实现使用 Performance_ExtraTimingOpt，并开启布线后 phys_opt（impl_2），FCLK0 10.000 ns |
| Setup / hold | WNS +0.104 ns、TNS 0；WHS +0.041 ns、THS 0（73907 个端点） |
| 策略对比 | impl_1 RefinePlacement −0.123（未开布线后 phys_opt）；ExtraTimingOpt +0.104；RefinePlacement +0.025；Explore +0.016；NetDelay_low −0.244。违例路径都在 CPU 的 id_ex 前递 → dcache/id_ex CE，不在 PUF/HWKEY 逻辑 |
| DRC / PS 引脚 | 0 个 Error 或 Critical Warning；没有 `Netlist 29-160` |
| RO | 1280 个 LUT 全部分配到 `pb_ro_puf`；pblock 变为 soft，物理上只有 440 个落在区域内 |
| 资源 | 18674 LUT / 32002 FF / 34.5 BRAM tile / 4 DSP |
| BRAM 初始化 | 生成的 `.mif` 与 `pynq_svc_puf.coe` 逐字一致（32768 字） |
| HWH | `pynq_ctl_0` 位于 0x40000000，ID_VALUE 0x33465150；`pynq_mbox_0` 位于 0x40001000；FCLK0 100 MHz |
| 未签核 | 5120 个无时钟引脚（ro_en 根时钟）、15360 个无最大延迟约束的引脚、256 个有意保留的组合环；methodology TIMING-17 共 1000 条 |

### 三块电路的签核状态（与 pynq_puf 提交 5eb64a5 的方法相同）

| 部分 | 状态 | 依据 |
|---|---|---|
| CPU / Ascon / 总线（clk_fpga_0，100 MHz） | 已签核：WNS +0.104 ns，WHS +0.041 ns | 实现策略 ExtraTimingOpt + 布线后 phys_opt；每次尝试都记在 `reports/explore_impl.txt` |
| PUF 采样控制（ro_clk，25 MHz） | 已签核：WNS +24.822 ns，WHS +0.115 ns；ro_clk→clk 为 +3.742 / +0.216，clk→ro_clk 为 +6.994 / +0.428 | `pynq_puf3_timing.xdc` 把 ro_clk 声明为 FCLK0 四分频（只用于实现阶段，不加例外），无需测量 |
| 振荡环计数器（256 × 20 位） | **未签核** | 见下 |

`ro_corner_sta.tcl` 只做分析、不改 bit：它用 AMD 器件延时模型算出每个已布线环的周期，
再在每个角下用该角自己的环周期检查计数器。本候选的结果（`reports/ro_corner_sta.txt`）：

| 角 | 最快环 | 计数器 setup 最差 | 计数器 hold 最差 |
|---|---|---|---|
| Slow（周期 3.473 ns） | 288 MHz | −0.478 ns | −0.552 ns |
| Fast（周期 1.194 ns） | 837 MHz | −0.598 ns | −0.427 ns |

在两个角下，计数器都有负 slack（计数器时钟由 LUT 驱动）；快角下最快环超过 20 位计数器
在窗口内回绕的上限（400 MHz）。这一块只靠约束或上板测量签不下来，必须修改 PUF RTL，
本候选不宣称已签核。

cosim 用例：

- **normal**：54 步全部 PASS，覆盖开机自检、36 个三模式 KAT 请求和 PUF 流程。
  PUF 流程依次为：降级状态下拒绝 HWKEY → ENROLL → RECONSTRUCT → HWKEY_ON →
  HW 拒绝调用方 key（AUTH_FAILED）→ SW/ISE 不受影响 → HWKEY_OFF 后 HW KAT 恢复 →
  未知命令 BAD_CMD → Y01E 重新握手后 HWKEY 自动关闭。
- **mutant_autolock**：使用原 `src/rtl` 自动锁定 RTL，开机 mask 为 0x05，TB 以非零码退出。

## 上板

```sh
在 PYNQ Jupyter 中打开并按顺序执行
`src/pynq_puf3/pynq_puf3_board_test.ipynb`。
```

测试分四段，全部通过才 exit 0：
1. 身份检查：哈希、ID、FCLK 和固件 ID；
2. 三模式 KAT：6 个官方用例，加 `--full-kat` 则跑 289 个；
3. 基准：KAT #529，预热 5 次、采集 30 次，输出中位 mcycle 和相对 SW 的加速比；
4. PUF：enroll，5 次 reconstruct 稳定且 helper 不变；HWKEY 打开后 HW 拒绝官方密文；
   PUF 密钥往返成功；reconstruct 后密文相同；HWKEY 关闭后官方 KAT 恢复。

## 限制（不得宣称）

- 每次复位都要重新 enroll（helper 是易失的），只能证明同一会话内可重复；
  熵、BER、温度、唯一性、跨上电重建均为 not_measured。
- 振荡环计数器域没有签核（ro_corner_sta 在两个角下都是负 slack），需要改 PUF RTL；
  正的 WNS 只覆盖 clk_fpga_0 和 ro_clk 两个已声明的时钟。
- REF/RAW/MASK/DITHER/DNA 可经 MMIO 读出，不能宣称保密；HWKEY 是固件策略，
  CPU 软件可以随时打开或关闭。
- 板测结果在 Notebook 的 `result.json` 和 `mailbox_log.txt` 输出存在之前一律为 NOT_RUN。
