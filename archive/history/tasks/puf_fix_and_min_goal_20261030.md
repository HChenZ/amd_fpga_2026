# GOAL：PUF v2 修正 + 最小闭环 PUF（PUF-MIN）方案

> 2026-11-01：本页为10-30任务书，“构建未完成/尚无候选”等观察按当时读取，后续结果以各版本证据为准。
> 本轮不继续执行Track A/B，也不改已发布PUF3。PUF v2旧候选仍INVALID；PUF3使用PUF v1，不是该修正方案。
> 当前与历史入口见 docs/version_entrypoints.md，原失败/禁止项保留。

日期 2026-10-30；owner TBD；交付冻结 2026-11-01。本文件是给执行 AI 的任务书，
不是结果记录。执行前按 `AGENTS.md` 必读顺序读文档，先 `git status`，不 commit/push。

---

## 0. 已核实事实（执行方不得重新解释）

| # | 事实 | 证据 |
|---|---|---|
| F1 | `board/vivado_zynq7000_xc7z020_puf_v2/setup.tcl` 未执行 `make_bd_intf_pins_external` 导出 `ps7/FIXED_IO`、`ps7/DDR`（第 26 行注释明确跳过） | setup.tcl:26-31 |
| F2 | 因此生成的 `puf_ps7_0.xdc` 把 IOSTANDARD/PACKAGE_PIN/slew/PIO_DIRECTION 施加到内部 pin，产生一串 `CRITICAL WARNING [Netlist 29-160]` | `data/advanced/puf_soc/vivado_logs/impl_1.log:37` 起 |
| F3 | CPU-DMA 第一版因同一问题作废；修法是 BD 导出接口后重新生成，不手改生成 XDC | `project_log/lessons_learned.md:20`；`board/vivado_zynq7000_xc7z020_pynq_dma_cpu/setup.tcl:58-59`；门禁 `.../pynq_dma_cpu/collect.tcl:19` |
| F4 | 首次 route 真实违例：WNS −0.249 / TNS −1.615，路径 `u_dcache/bus_addr_r_reg[23]` → `u_puf/peripheral/input_data_reg[*]/CE`，10 级逻辑，82% 布线延迟，100MHz | `data/advanced/puf_soc/implementation/setup_paths.rpt` |
| F5 | 现有 candidate 只靠 post-route `phys_opt_design AggressiveExplore` 到 WNS +0.009，余量几乎为零，且该网表含 F2 缺陷 | `candidate/reports/verdict.txt`；`methodology_resolution_report.md` |
| F6 | 违例根因：CPU 地址 → `bus_interconnect_puf_v2` 24 位组合译码（`hit_dma`）→ `puf_mmio_v2` 的 `writable/busy/control/bus_error` 组合判断 → 128 位寄存器写使能，全部在同一拍 | `src/rtl/puf_soc_v2/bus_interconnect_puf_v2.v:132-137`；`src/rtl/keys_v2/puf_mmio_v2.v:54-65,165-212` |
| F7 | v2 规模：RV32 CPU + Ascon ISE + ascon_mmio + 两份 crypto_aead + puf_key_v2 + 镜像认证 + 诊断 helper ABI + 私有 128KiB BRAM + 邮箱/UART，约 39k LUT/40k FF/34.5 BRAM | `validation_20261030.md:95` |
| F8 | RO 域 7424 个无时钟 pin、19712 个未约束端点、TIMING-6/7（FCLK0/FCLK1 关系未定义）；不在本次修正范围，**只能保持标注 STRUCTURAL_DIAGNOSTIC_ONLY** | `validation_20261030.md:98-104` |
| F9 | 旧 `pynq_puf`（PUF v1 overlay）构建未完成：build.log 停在 placement，估计 WNS −1.183，`reports/` 为空，不能当退路 | `build/local/pynq_puf/build.log` |
| F10 | 主线 release 的 `board/vivado_zynq7000_xc7z020_pynq/build.tcl:33` 同样未导出 FIXED_IO/DDR | 仅记录，见 §3 |

**结论：现有 `puf_v2/candidate/puf.bit` 必须作废，不得上板，也不得合并。**

---

## 1. 全局禁止项

1. 不修改 / 删除 / 覆盖已有 candidate、证据目录、release、`src/rtl/keys_v2/`、原 CPU/Ascon RTL；新产物用新目录。
2. 不手改任何 generated 文件（`*.gen/`、生成 XDC、HWH）。
3. 不靠以下方式“通过”时序：放宽时钟 XDC 而不改 PS 实际 FCLK；全局 false_path / clock_groups；降级 DRC；虚构 RO 时钟周期。
4. 仿真、实现、板测结果分开记录；没有执行的写 `NOT_RUN` / `not_measured`。
5. Vivado：每个工程用独立 session，同 session 的 Tcl 串行执行；记录 tool version/part/top/IP 版本/命令/退出码。
6. 完成后更新 `project_log/actual_progress.md`、`tasks/task_board.md`、`data/advanced/current_candidates.json`（只追加/改状态，不删旧条目）；失败写入 `lessons_learned.md`。

---

## 2. Track A：PUF v2 修正（PUF-V2-FIX）

### A0 作废旧 candidate（≤15 min，必须最先做）

- 在 `board/vivado_zynq7000_xc7z020_puf_v2/candidate/` 增加 `INVALID.md`（不删、不改原文件），写明：F2 缺陷、F5 余量、禁止上板。
- `current_candidates.json` 中该条状态改为 `INVALID_DO_NOT_PROGRAM`，引用 INVALID.md。
- `capture.py` 增加防护：manifest 中 bit SHA 等于旧值 `05c955cd…3dc62` 时拒绝运行，exit≠0。

### A1 修 FIXED_IO/DDR（源配置）

- 修改 `setup.tcl`：`create_bd_cell ... ps7` 和 `set_property -dict` 之后加
  `make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]` 与 `... ps7/DDR`，注释与 pynq_dma_cpu 保持一致（overlay 模式，DDR/MIO 启动配置仍由 vendor SD image 提供）。
- 新工程目录（例如 `work_fix/`），不复用旧 `work/`。
- 门禁（写进 `build.tcl`，失败即 `error`、不写 bit）：
  - `impl_1` 和 `synth_1` 日志中 `Netlist 29-160` 计数 = 0；
  - `llength [get_ports DDR*] > 0` 且 `llength [get_ports FIXED_IO*] > 0`；
  - HWH 中出现 DDR/FIXED_IO 外部接口。

### A2 修时序（RTL/架构层面，二选一，**必须先做 A2-explore**）

**A2-explore（只读，≤1h）**：给出量化对比后再动手：
- 在 A1 新网表上先跑一次 route（不跑 phys_opt），记录 WNS/TNS 和前 20 条路径；导出 FIXED_IO 后布局会变化，F4 的数字不能直接沿用。
- 确认 CPU 对 MMIO 读的时序假设（`read_sel_q`/`dma_re_q` 固定 1 拍返回）以及写之后立即读状态的固件序列（`src/firmware/keys_v2/`）。

**方案 A2-a（推荐，最快、最诚实）：把 PS 的 FCLK0 实际降到 80MHz**
- 改 `PCW_FPGA0_PERIPHERAL_FREQMHZ 80`（这是真实硬件时钟，不是改 XDC），与 CPU-DMA 最终候选的处理方式一致。
- 同步更新：setup 回读检查、`context.txt`、`capture.py`/manifest 的时钟校验（100→80）、UART 分频（CPU 与邮箱同时钟，比例不变，需确认）、固件中以周期数表示的 deadline（CORE_DEADLINE/cipher_timer 只是上限，变慢不影响正确性，但要写明）。
- 仿真：`sim/puf_soc_v2/run.py` 和 `run_xsim.tcl` 改用 12.5ns 周期重跑，全部 PASS。

**方案 A2-b（若必须保持 100MHz）：在 `src/rtl/puf_soc_v2/` 内给 PUF 写通路打一拍**
- 只改 puf_soc_v2 自有文件（`bus_interconnect_puf_v2.v` / `soc_top_puf_v2.v`），不改 `keys_v2/puf_mmio_v2.v`。
- 把 `dma_we/addr/wdata/wstrb` 寄存一拍后送入 PUF；读通路保持原样。
- 必须处理写后读冒险：PUF 写尚未生效时出现 PUF 读，需要停顿 1 拍（`cpu_axi_stall_req`）或前递；用定向 TB 证明“写 CONTROL 后立即读 STATUS”的结果与原设计一致。
- bus_error / bus_fault 的语义要与延迟后的写对齐，并补负向测试（非法地址、busy 写、非法命令）。

**A2 验收（两种方案相同）**：
- `route_design` 后（**不依赖 post-route phys_opt**）所有已定义时钟 WNS ≥ +0.100ns，WHS ≥ 0，TNS/THS = 0；
- 若最终仍用 phys_opt，需同时报告 phys_opt 前后的数值；
- DRC 0 Error；Critical Warning 逐条列出，不允许出现 29-160；
- `audit_rings.tcl`：1280 个 RO LUT、256 个确认反馈网；
- Icarus 2 模式 + XSim 4 配置 PASS；`verify_delivery.py` 指向新 candidate 后 exit 0。

### A3 打包

- 新 candidate 目录：`board/vivado_zynq7000_xc7z020_puf_v2/candidate_fix_<日期>/`（不覆盖旧目录）。
- manifest 记录 bit/hwh/elf/coe SHA、FCLK 实际值、WNS（phys_opt 前/后）、29-160 计数=0。
- 结论仍为 `STRUCTURAL_DIAGNOSTIC_ONLY`（F8 未解决）；板测 `NOT_RUN`。

---

## 3. 旁路检查（只查不改，≤30 min）

F10：主线 PYNQ release 的 `build.tcl` 也没有导出 FIXED_IO/DDR。执行方只做以下检查：
- 找到主线 release 对应的 impl 日志（`build/` 或 release 证据目录），统计 `Netlist 29-160`；
- 把结果写进 `docs/advanced_offline_status_20261030.md` 的“待确认”小节，并提醒用户；
- **不得**改 release、不得重建 release。主线是否受影响由用户决定（它已有板测 PASS 证据）。

---

## 4. Track B：最小闭环 PUF（PUF-MIN）

### 4.1 为什么要做最小版

v2 把 PUF、内部 key、PL 内 AEAD、镜像认证、诊断 helper ABI、RV32 固件、邮箱全部塞进一个 SoC（F7），
时序违例正好落在 CPU→PUF 寄存器的路径上（F6）。展示 PUF 所需的闭环其实只有：

> 物理响应 → 注册（helper）→ 重建 → 派生密钥 → 用密钥做一次可验证的密码操作 → 统计

这些步骤只有“物理响应”必须放在 PL，其余都可以由 PS 上的 Python 完成。

### 4.2 架构（目标形态，执行方可在 4.4 探索后调整，但必须说明理由）

```
PS (PYNQ Python)
  │ M_AXI_GP0, FCLK0 100MHz（单一时钟）
  ▼
axi_interconnect ──► puf_min_axil (AXI-Lite 从机, 新 RTL)
                          ├─ ro_puf_core_v2 (复用, clk = ro_clk = FCLK0)
                          │     └─ ro_array_v2 (复用, 256 环 → 128 bit)
                          └─ device_dna (复用, 可选)
```

删除：RV32 CPU、私有 BRAM/COE、Ascon ISE/MMIO、crypto_aead、puf_key_v2、puf_aead_v2、镜像认证、邮箱、pynq_ctl、FCLK1。

### 4.3 寄存器 ABI（草案，4KiB，PS 地址 0x4000_0000）

| 偏移 | 名称 | R/W | 说明 |
|---|---|---|---|
| 0x00 | ID | R | `0x4E494D50`（"PMIN"），不得与已有 ID 冲突 |
| 0x04 | VERSION | R | 1 |
| 0x08 | CTRL | W | bit0 START（脉冲），bit1 CLEAR |
| 0x0C | STATUS | R | bit0 busy、bit1 done、bit2 valid、bit3 locked、bit4 dna_ready |
| 0x10 | ERROR | R | ro_puf_core_v2.error_code |
| 0x14 | TXN | R | transaction_id |
| 0x20..0x2C | RAW[0..3] | R | 128-bit 响应，仅在 valid=1 时有效，否则读 0 |
| 0x30/0x34 | DNA_LO/HI | R | 57-bit DNA |
| 0x40 | CNT_SEL | W | 可选：选择第 i 个计数器（诊断用） |
| 0x44 | CNT_VAL | R | 可选：对应计数值（用于测频/健康统计） |

只做寄存器读回，不存储 key，不存储 helper。必须明确声明 RAW 可读，**没有保密性**。

### 4.4 探索任务（实现前，只读 + 小实验，≤2h，产出 `docs/puf_min_explore_20261030.md`）

| ID | 问题 | 判定方法 |
|---|---|---|
| E1 | `ro_puf_core_v2` 在 `clk==ro_clk` 时是否正确（同步器、WINDOW、deadline） | 读 RTL + 用现有 `sim/keys_v2` TB 把两时钟接到同一源后跑 |
| E2 | 单时钟方案能否消除 TIMING-6/7；RO 计数器无时钟 pin 预计还剩多少 | 综合后 `check_timing`，给出数字 |
| E3 | RO 环数取舍：256 环/128 bit vs 128 环/64 bit；资源与位置约束 | 参考 `src/rtl/keys_v2/physical_constraints.tcl`、`pynq_puf/puf_opt_pre.tcl` 的 pblock |
| E4 | AXI-Lite 从机模板：复用 `pynq_ctl.v` 风格还是新写 | 选简单的一种，读写都要寄存 |
| E5 | Python Ascon：使用仓库内 `ascon/pyascon/ascon.py`（Ascon-AEAD128） | 先跑一次已知 KAT 确认可用 |
| E6 | 是否保留 DNA | 资源/风险对比；保留则必须与 Hardware Manager 读数对比，否则标 not_measured |
| E7 | v2 的 FCLK/BD 脚本中可直接复用的部分（含 A1 修复） | 列出复用行 |

探索结论里每项写：选择、理由、风险。若 E1 不成立，备选方案是写一个最简的
“使能窗口 → 停振 → 冻结计数 → 两级同步读出”采样器，并把冻结计数器读路径的时序处理理由写清楚
（不得用全局 false_path）。

### 4.5 实现产物（新目录，不碰 v2）

- RTL：`src/rtl/puf_min/puf_min_axil.v`、`src/rtl/puf_min/puf_min_top.v`、`readme.md`
- 工程：`board/vivado_zynq7000_xc7z020_puf_min/{setup.tcl,build.tcl,ring_ack.tcl,reports.tcl,package.py,readme.md}`
  - setup 必须包含 A1 的 FIXED_IO/DDR 导出；ring_ack/pblock 复用 v2/pynq_puf 的做法。
- 仿真：`sim/puf_min/`：AXI-Lite BFM + 行为级 RO 模型（复用 `sim/puf_soc_v2/ro_array_model.sv`）；
  覆盖 START→done/valid、CLEAR、busy 时 START、锁定恢复、RAW 在 valid=0 时读 0、非法地址。
- 主机：`src/pynq/puf_min.py`（驱动 + enroll/reconstruct/key/demo/stats），带离线 mock 单测。
- 证据：`data/advanced/puf_min/<run_id>/`。

### 4.6 软件闭环流程（`puf_min.py`）

1. **health**：读 ID/VERSION/DNA；若有 CNT 接口，统计计数分布、零值/饱和/相等对。
2. **enroll**：采样 K 次（默认 15）→ 逐位多数表决得 REF；全部一致的位组成 MASK；
   `popcount(MASK) < 64` 则失败。helper JSON 保存 `{dna, build_sha, K, REF, MASK, sha256}`。
   明确标注：REF 落盘会泄露响应，这只是演示用的 helper，不是安全 sketch。
3. **key**：`key = SHA-256("PUF-MIN-v1" || DNA || (REF & MASK) || MASK)[:16]`，标注不是经过验证的提取器。
4. **seal**：用 key 对固定明文做 Ascon-AEAD128 加密，把 nonce/ct/tag 存入 JSON（key 不落盘）。
5. **reconstruct**（重载 bitstream 或重启后执行）：采样 M 次 → 对 MASK 内的位做多数表决 → 与 REF 比较，
   记录 masked BER；重新派生 key → 解密 → **tag 验证通过即闭环 PASS**；篡改 1 bit 的 ct 必须被拒绝。
6. **stats**：intra-HD（同板多次）、汉明重量/均匀度、稳定位比例、每次 RAW 的原始比特；
   inter-HD/唯一性只有一块板，记为 `not_measured`。

### 4.7 验收门禁

| 层级 | 必须满足 |
|---|---|
| 仿真 | `sim/puf_min` 全部用例 PASS，日志含退出码；`puf_min.py` mock 测试 PASS |
| 实现 | Vivado 2025.2 / xc7z020clg400-1；`route_design` 后（不靠 phys_opt）WNS ≥ +0.5ns、WHS ≥ 0；DRC 0 Error；`Netlist 29-160` = 0；DDR*/FIXED_IO* 端口存在；RO LUT 数 = 设计值且全部在 pblock 内；每个反馈网单独确认 |
| 时序标注 | 列出剩余无时钟 pin / 未约束端点数量（RO 计数器）；TIMING-6/7 应为 0（单时钟），否则说明原因 |
| 资源 | 报告 LUT/FF/BRAM；预期远小于 v2（参考值 <5k LUT，以实测为准） |
| 打包 | candidate 含 bit/hwh/manifest（SHA、FCLK、WNS、29-160 计数）；主机脚本加载前校验 SHA |
| 板测 | 由人执行；PASS = 连续 5 次 reconstruct 全部 tag 验证通过 + ID/DNA 一致 + 篡改被拒；另做 ≥1 次断电重启后的 reconstruct。未执行前写 `NOT_RUN` |

### 4.8 明确不宣称

熵、安全提取器、ECC、温度/电压/老化可靠性、多板唯一性、安全启动、防回滚、key 保密性（RAW 可读）。

---

## 5. 优先级与时间（冻结 11-01）

| 顺序 | 任务 | 预计 | 可并行 |
|---|---|---|---|
| 1 | A0 作废旧 candidate + capture 防护 | 15 min | — |
| 2 | §3 主线 29-160 只读检查 | 30 min | 与 3 并行 |
| 3 | B 探索 E1–E7 | 2 h | 与 4 并行（不同 Vivado session） |
| 4 | A1 + A2-explore | 2–3 h（含一次实现） | |
| 5 | B 实现 + 仿真 + 构建 | 4–6 h | |
| 6 | A2 修复 + 重建 + 打包 | 3–4 h | 与 5 并行 |
| 7 | 文档/日志/候选索引收口 | 1 h | — |

**取舍建议**：如果时间不够，优先保证 PUF-MIN 拿到实现门禁通过的 candidate，作为 PUF 展示入口；
PUF v2 只完成 A0+A1，标为“已作废/修复中”。不能用 v2 的仿真 PASS 冒充 PUF-MIN 的结果，反之亦然。

---

## 6. 交付格式（每个 Track 各一份）

任务号（PUF-V2-FIX / PUF-MIN）、改动文件、接口变化（地址/ID/时钟）、验证命令 + 工具版本 + 退出码 + 证据路径、
时序数字（phys_opt 前/后）、29-160 计数、未验证内容、阻塞、下一接收任务（owner TBD）。
