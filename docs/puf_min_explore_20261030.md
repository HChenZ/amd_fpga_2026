# PUF-MIN 探索记录（E1–E7）

任务号 `PUF-MIN`；日期 2026-10-30；owner TBD。
输入任务书：`tasks/puf_fix_and_min_goal_20261030.md` §4.4。

方法：读 RTL/脚本 + 小实验（Icarus 行为级仿真、两次以上独立 Vivado 实现）。
每条给出**选择 / 理由 / 风险**；实测数字都指向具体证据目录，未执行的写 `NOT_RUN`。

---

## E1 `ro_puf_core_v2` 在 `clk == ro_clk` 时是否正确

**结论：功能正确。** 但**功能正确不等于 100MHz 可收敛**——见 E2。

做法：把 `.clk` 与 `.ro_clk` 接到**同一个 wire**，用生产参数
（`BITS=128 CW=20 WINDOW=1024 RO_DEADLINE=8192 CORE_DEADLINE=65536`），
用例 `sim/puf_min/tb_ro_core_single_clock.sv`：

| 检查 | 结果 |
|---|---|
| 单次采样 | `done=1 valid=1 error=0`，`raw=0x5555…`（与行为级差频模型的预期逐位一致） |
| 连续 6 次采样 | **6/6 逐位一致**；`transaction_id` 每次 +1（START 请求没有被同源时钟吞掉） |
| busy 期间再 START | `error=0x40` 且 `locked` |
| 复位后 | 锁定解除，可再次成功采样 |

推理依据：`rq`/`cp` 都是 3 级延迟 + 1 拍 `capture_pending` 的翻转握手，
`ro_reset_release`/`reset_release` 只用异步 `rst_n`；同源时钟不会引入竞争，
只是把两次翻转的间隔从"3 个 ro 沿"变成"3 个 clk 沿"，编码方式不变。

证据：`data/advanced/puf_min/icarus_*/`（`e1_single_clock_*` 日志 + `results.json`），
XSim 侧同一用例见 `sim/puf_min/run_xsim.tcl` 的 `e1_single_clock`。

**风险**：行为级模型不能证明物理环在单时钟下的采样质量（见「未测」一节）。

---

## E2 单时钟能否消除 TIMING-6/7；RO 计数器还剩多少无时钟 pin

**结论：TIMING-6/7 归零；RO 计数器造成的 `no_clock` 一个也没少（7424），符合预期。**

证据：`data/advanced/puf_min/impl_20261030_120504/`（`check_timing.rpt`、
`methodology.rpt`、`clocks.rpt`、`route_status.rpt`）。

| 项 | v2（FCLK0 100 + FCLK1 25） | PUF-MIN（单时钟 100） |
|---|---|---|
| 时钟数 | 2 | **1**（`clk_fpga_0`，10.000 ns） |
| TIMING-6 / TIMING-7 | 各 2 | **0 / 0** |
| `no_clock`（无时钟 seq pin） | 7424 | **7424** |
| `unconstrained_internal_endpoints` | 19712 | **19712** |
| 组合环（TIMING-23） | 256 | **256**（RO 环本身） |
| TIMING-17 Critical Warning | 有（上限 1000 例） | 有（同样上限 1000 例） |
| 可布线 net / 布线错误 | 69141 / 0 | **29073 / 0** |

原因：`no_clock` 来自 256 个 RO 计数器（20 位计数 + `p0/p1` 同步器 + `ack` +
`overflow` + `reset_release`），它们由环振荡器驱动，而环不定义时钟。
这和是否单时钟无关；单时钟只消除了 FCLK0/FCLK1 关系未定义的 TIMING-6/7。

**风险**：`no_clock`/未约束端点意味着 RO 计数器那条跨域路径**没有 STA 保证**。
本设计用 `ro_counter_v2` 的四相 bundled-data 握手（计数在 stop ack 之前稳定）
来保证正确性，而不是靠时序签核；因此结论只能是 `STRUCTURAL_ONLY`。

---

## E3 环数取舍：256 环/128 bit vs 128 环/64 bit；资源与位置约束

**选择：256 环 / 128 bit，`CW=20`，`WINDOW=1024`，环阵列放进 `pb_ro_puf`。**

理由：
1. 与 v2 使用同一套 1280 LUT 环阵列与 256 个计数器，**审计工具、反馈网确认流程、
   `elaborate/synth` 口径都能直接复用**（`ring_ack.tcl` 逐环确认 256 个反馈网，
   `audit_rings.tcl` 复核 1280 LUT 全在 pblock 内）。
2. §4.6 的门限是 `popcount(MASK) < 64 则失败`。64 bit 方案下这条规则形同虚设
   （最多 64 个稳定位），128 bit 才有意义。
3. 环数减半省下的面积有限（见下），却让"同一份响应、同一套审计"的复用性消失。

**实测资源**（`impl_20261030_120504/utilization.rpt` 与 `utilization_hier.rpt`）：

| 项 | 实测 |
|---|---|
| 顶层总 LUT / FF | **18006 / 15255** |
| 其中环阵列 `bank`（1280 个 LUT 环） | 1280 LUT |
| 其中 `puf_core`（采样器 + 寄存器从机） | 17600 LUT / 14754 FF |
| BRAM tile / DSP | **0 / 0** |
| v2 全 SoC 对照 | 39077 LUT / 40051 FF / 34.5 BRAM / 4 DSP |

**没有达到任务书 §4.7 的参考值 "<5k LUT"**，必须如实记录。面积去向（结构分析，
非工具分层实测）：

- 256 × 20 位计数器（`count++`）≈ 5.1k LUT —— 环数 × 计数宽度决定，无法省；
- 5120 位 `snapshot` 载入 + 无时钟域到 `snapshot` 的打包；
- 每对环的 20 位比较 + 零值/饱和/相等/方向四类健康位归约 ≈ 4k LUT；
- 256:1 计数回读多路 ≈ 1.7k LUT；
- AXI4-Lite 寄存器从机 ≈ 0.4k LUT（BD 里 `axi` 互联另占 389 LUT）。

要到 <5k 只能砍环数（例如 64 环/32 bit ≈ 3.9k LUT 的量级），代价是放弃 128-bit
响应和 `popcount(MASK)≥64` 规则。**本次不砍**：任务书 §4.2 明确 256 环 → 128 bit，
且 §4.7 的资源项写的是"参考值……以实测为准"。

**风险**：18k LUT 在 xc7z020（53200 LUT）上仍只有 34%，但与"最小版"的直觉不符，
容易被误读成"又一个 SoC"。本文档和 `readme.md` 都写清了面积构成。

---

## E4 AXI-Lite 从机模板：复用 `pynq_ctl.v` 风格还是新写

**选择：新写 `puf_min_axil.v`，沿用 `pynq_ctl.v` 的握手风格。**

理由：
- `pynq_ctl.v` 已被实板验证（P0/P1 主链），其写通道（AW/W 各自 `done` 标志、
  `bvalid` 单拍应答）与读通道（AR 握手拍寄存 `rdata`）是低风险模板。
- 不复用 `puf_mmio_v2.v`：它捆了 AEAD/helper/镜像认证，PUF-MIN 不需要，且它是
  `src/rtl/keys_v2/` 的冻结文件。
- 增加了 `pynq_ctl.v` 没有的两点：`SLVERR` 语义（未映射/非对齐/写只读）与
  粘滞 `done/valid`（见 `src/rtl/puf_min/readme.md`）。

**关于"计数回读很贵"的实测更正**：第一版对 5120 位做 `core_counts[cnt_sel*CW +: CW]`
（`cnt_sel*20`），OOC 综合 **18170 LUT / 14754 FF**；改成 32 位对齐打包（下标乘法
退化为移位）后仍然是 **18170 LUT / 14754 FF**。

结论：**变量部分选择不是瓶颈**，Vivado 两种写法都归一化成同一棵 mux 树；
18k 的代价来自 E3 列的计数器/快照/健康归约。打包写法保留（等价且索引更清晰），
但**不要**把它当成省面积的优化。

---

## E5 Python Ascon 可用性

**选择：用仓库内 `ascon/pyascon/ascon.py`（参考实现，`ascon_encrypt/decrypt`，
`variant="Ascon-AEAD128"`）。**

证据：
- `src/pynq/test_puf_min.py::AsconTests` —— 导入、往返、错 key 必须 `None`；
- 钉住向量 `src/pynq/puf_min_ascon_vector.json`（key `00..0f`、nonce `10..1f`、
  ad 空、pt 16 个 `0x00` → `c8e2fccd…8d342`），用于防止依赖被静默替换；
- 标准 KAT 的既有证据是 `data/ascon/results/host_validation.log`（upstream-C
  Ascon-AEAD128 KAT PASS 记录）。**本次没有重跑标准 KAT**，不重复宣称。

**风险**：`seal()` 的 nonce 用 `os.urandom(16)`。PUF-MIN **不提供 TRNG**，
nonce 只是 AEAD 演示参数，不能宣称随机性来源。

---

## E6 是否保留 DNA

**选择：保留（`src/rtl/keys/device_dna.v`，57-bit）。**

理由：资源可忽略；helper 需要 `{dna, build_sha, K, REF, MASK}` 做设备/构建绑定；
去掉会让 helper 无法检测"换了板子/换了 bitstream"。

**位序 `not_measured`**：`DNA_PORT` 的 DOUT 相位由 `SHIFT_SKIP` 参数对齐，
默认 1。上板时必须把读回值与 Vivado Hardware Manager 的 Device Properties
（或 Programmer 的 Read Device DNA）逐位比对；整体错一位就把 `SHIFT_SKIP` 取反。
**这一步没做之前，DNA 只用于"同一板同一 bitstream 内的一致性检查"，不当作跨板身份。**

仿真侧 `sim/keys/DNA_PORT_sim.v` 是行为模型，`tb_puf_min` 用
`SIM_DNA=57'h0_1234_5678_9ABCDE` 验证了 `DNA_LO=0x789A_BCDE`、
`DNA_HI=0x0012_3456` 的打包关系。

---

## E7 v2 的 FCLK/BD 脚本中可直接复用的部分

| 复用项 | 来源 | 在 PUF-MIN 里怎么用 |
|---|---|---|
| `make_bd_intf_pins_external ps7/FIXED_IO`、`... ps7/DDR` + 回读检查 | `pynq_puf/build.tcl:40-42`、`pynq_dma_cpu/setup.tcl:58-59` | `puf_min/setup.tcl` 直接照抄，并在 setup 阶段就断言导出成功 |
| `Netlist 29-160` 计数门禁 | `pynq_puf/build.tcl:108`、`pynq_dma_cpu/collect.tcl:23` | `puf_min/gate.tcl` 对 `impl_1`/`synth_1` 两个 `runme.log` 统计并要求 0 |
| RO pblock（`SLICE_X60Y115:SLICE_X113Y149`） | `pynq_puf/puf_opt_pre.tcl:12` | `puf_min/ring_ack.tcl` 只把 `bank` 放进去（不把计数器/AXI 一起关进去） |
| `ALLOW_COMBINATORIAL_LOOPS` 逐环确认 | `puf_v2/ring_ack.tcl`、`build/keys_ro_allow_loops.tcl` | `puf_min/ring_ack.tcl` 升级为 `string map` 精确推导期望驱动端（原写法手工算字符偏移，差一位会静默匹配错） |
| 行为级 RO 模型 | `sim/puf_soc_v2/ro_array_model.sv` | `sim/puf_min/run.py` / `run_xsim.tcl` 直接复用 |
| AXI-Lite BFM / 寄存器风格 | `src/rtl/pynq/pynq_ctl.v`、`sim/puf_soc_v2/*` | `puf_min_axil.v` + `sim/puf_min/axi_lite_bfm.sv` |
| PS 侧 MMIO + 证据/seal 脚本结构 | `puf_v2/capture.py`、`seal.py` | `src/pynq/puf_min.py` 的哈希/证据写法 |

**不复用**：`puf_soc_v2/` 的总线译码与 CPU 集成（正是 PUF-V2-FIX 的 A2-b 要改的地方）、
`puf_mmio_v2.v`（捆了 AEAD/helper）、FCLK1（本设计单时钟）。

---

## 风险与未测（不宣称）

| 项 | 状态 |
|---|---|
| 物理 RO 频率 / 最小周期 | `NOT_MEASURED`，不定义 RO 时钟、不虚构周期 |
| 熵估计、唯一性（inter-HD）、温度/电压/老化可靠性 | `not_measured` / 不宣称 |
| ECC、安全提取器、helper 保密性 | 不提供；helper 里的 REF 就是响应比特，落盘即泄露 |
| 安全启动、防回滚、key 保密性 | 不提供；RAW 对 PS 完全可读 |
| 后仿（post-route SDF） | `NOT_RUN` |
| 板测（PYNQ、连续 5 次 reconstruct、断电重启、篡改被拒） | `NOT_RUN`（由人执行，见 `board/vivado_zynq7000_xc7z020_puf_min/readme.md`） |
| DNA 位序 | `not_measured`（需与 Hardware Manager 比对） |
