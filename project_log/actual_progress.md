# 实际进度

## 2026-10-27 23:48 阶段 4 板级通过 — PUF 密钥子系统 enroll + reconstruct 全链路成功

owner TBD。v3 固件（先等 idle 再发 START）烧录后，串口**全部通过**（原始日志待归档为
`data/ascon/results/board/uart_20261027_keys3.txt`，以下数字转录自截图）：

```
STATUS boot   : 00000001 busy=1 enrolled=0 done=0 quality=0
STATUS idle   : 0000003a busy=0 enrolled=0 done=1 quality=0
STATUS enrol  : 00008026 quality=128
DNA    : 008968143982d0b8
REF    : 58abef60 2834c32c fab29602 8816bf92
MASK   : ffffffff ffffffff ffffffff ffffffff
DITHER : 00000000 00000000 00000000 00000000
RAW    : 58abef60 2834c32c fab29602 8816bf92
STATUS recon: 00008026 quality=128
PASS key subsystem: enroll + reconstruct stable
DONE
```

**状态字解码**：
- `0x0000003A` = ready+mismatch+fallback+done → 上电自动 reconstruct 在无 helper
  （INIT_MASK=0）时**按设计降级**，不是错误。
- `0x00008026` = ready+enrolled+done，`quality=128`；enroll 与 reconstruct 两次读数完全相同，
  `mismatch=0`、`fallback=0` → 重建密钥与注册一致。
- `REF == RAW` → 本次 enroll 的对比结果与回读完全自洽；REF 的 1 个数 59/128 = 46.1%，
  接近理想 50%，**排除"比对器系统性偏一边"**（此前担心的 bias 不成立）。
- `DITHER=0` / `MASK=全 1` / `quality=128`：M=5 个窗口逐位一致，无抖动位。

**能写进材料的结论**（精确口径）：
- 256 路 RO-PUF + 57 位 Device DNA 的密钥子系统在 XC7Z020 实板上完成 enroll → reconstruct
  闭环，quality 128/128，密钥未出现在任何 CPU 可读地址。
- 无 helper 时的降级路径（mismatch+fallback）与设计一致。

**不能写/未验证**：
- **跨上电稳定性未验证**：helper 存在易失寄存器里，掉电即失效，每次上电都重新 enroll，
  所以"同一密钥跨上电可重建"这件事还没测过。需要先把 REF/MASK 持久化（BRAM 保留域或 PS 侧
  Flash/文件）再做多次上电对比。
- 温压/老化稳定性、误码率统计、唯一性（多板互比）均 `not_measured`。
- RO 采样域仍未纳入 STA（`no_clock 10930`），"PUF 时序已签核"不成立。
- `DITHER=0` 只能说明"本次 5 窗口无翻转"，不能外推为"永不翻转"；上次会话的 RAW 第 0 字为
  `58bbef60`（与本次差 1 bit），但那次读数是抢跑残值，不能作为跨会话不稳定的证据。

## 2026-10-27 阶段 4 第二次板上实测 — 硬件握手已修，固件与上电 reconstruct 抢跑（软件已修，待第三次烧录）

owner TBD。烧录 v2（新 RTL + 新固件）后串口日志关键行：

```
STATUS boot   : 00000001 busy=1 enrolled=0 done=0 quality=0
STATUS pre-enr: 00000001 busy=1          ← 上电自动 reconstruct 还在跑
STATUS enrol  : 00000023                 ← busy=1 且 done=1：done 属于 boot 那次操作
FAIL enroll not marked / FAIL quality=0  ← 读到的是"进行中"的残值
REF : 00000000 ...                       ← enroll 还没写完 ref
STATUS pre-rec: 00007f05 busy=1 enrolled=1 quality=127   ← 排队的那次 enroll 真的跑完了
STATUS recon  : 00007f26 busy=0 enrolled=1 done=1 quality=127  ← mismatch=0 fallback=0
FAIL                                     ← 汇总行，来自前面两条误判
```

- **结论 1（硬件）**：握手修复生效。v1 会直接超时；v2 里 `STATUS pre-enr busy=1` 说明 START 被**排队**
  而不是丢弃，随后 enroll 完成（`quality=127`，与首测一致），reconstruct 也完成
  （`0x7f26` = ready+enrolled+done，`mismatch=0`、`fallback=0`）。
- **结论 2（软件）**：固件与上电自动 reconstruct 抢跑。它没等 `busy` 落下就写 CLEAR+START，
  `wait_done()` 抓到的是 boot 那次操作的 done，于是把 enroll 的中途状态当成结果打印，
  连带 REF/MASK/DITHER/RAW 都是半写值。**不是"没匹配上"，mismatch 位自始至终是 0。**
- **固件修改（v3）**：新增 `wait_idle()`（每个操作前等 busy=0，含上电那次）、`start_op()`
  （CLEAR→START 后确认 busy 抬起或已完成，证明本次 START 被受理）、超时放宽到
  `TIMEOUT_LOOPS=800000` / `TIMEOUT_IDLE=400000`、新增 `WARN ref==0 (comparator biased)`
  告警（若 REF 仍全 0 则说明 128 位比对系统性偏一边、熵为零）。text 3019→3470 B。
- **镜像**：`ascon_keys.coe` sha256 `edd66d37…`，blk_mem_gen OOC 重生成，`.mif` 第 4 行核对
  `58818193`（v2 为 `3C818193`）。
- **流程约束（新发现）**：`write_mem_info` 对纯 `blk_mem_gen` 工程报
  `This design does not have any processors or XPM Libraries`，因此**不能**用 `updatemem`
  只换 BRAM 内容；改固件必须重跑 synth→impl→bitstream。已实测确认，不再尝试。
- **未验证**：v3 固件的板上行为（待第 3 次烧录）；REF 是否真的有熵，要等 v3 在 idle 之后读才有可能判断。

## 2026-10-27 阶段 4 修正 — 板上 reconstruct 超时的握手加固（仿真已验，板级待复测）

owner TBD。现象：板上 `ascon_keys` 首次烧录，enroll 成功（quality=127/128、DNA 可读、REF==RAW、
MASK 只屏蔽 2 位且与 DITHER 对应），但紧接着 `CTRL=0x4`→`CTRL=0x1` 的 **reconstruct 永远等不到 done**，
`FAIL reconstruct timeout`；按 PL RESET 重跑结果完全相同（确定性）。

- **定位到的两个脆弱点**（仿真 6 次连续操作不复现，属硬件才暴露的一类）：
  1. `key_mmio` 在 `key_busy=1` 时写 START 会**静默丢弃**（`if (wdata[0] && !key_busy)`），
     上层无从得知，只能超时；
  2. `ro_puf_core` 的 ro_clk 域 FSM 没有任何超时兜底：一旦卡在中间态（跨域计数在真实器件上
     可能因异步计数/亚稳态停滞），`done_tgl` 永不翻转，整条链路挂死。
- **修改（3 处）**：
  - `src/rtl/keys/ro_puf_core.v`：`req_event` 改为**权威重启**（任何状态收到请求都从起振重来）；
    新增 24-bit 采样看门狗 `WD_RO = M*(WINDOW+2*DWELL+8)+32*DWELL`，超时强制收尾并翻转 `done_tgl`。
  - `src/rtl/keys/key_mmio.v`：START 改为**排队**（忙时置 `start_pend`，空闲补发；模式在请求时刻快照；
    CLEAR 取消排队；ENROLL/RECONSTRUCT 模式不再被 CLEAR 覆盖）。
  - `src/firmware/keys_rv32/main.c`：每次操作前后打印 STATUS（含 busy/enrolled/done/quality），
    reconstruct 超时后 **重试一次**，并在 CLEAR→START 之间加空拍。text 2474→3019 B。
- **验证（仿真，全部实跑 PASS）**：`tb_puf_key`（原回归）、`tb_key_mmio`（原回归）、
  新增 `tb_puf_key_reuse`（单实例 6 次连续 op：boot-recon → enroll → recon ×4 全部 done）、
  新增 `tb_ro_reuse`（5 次正常 + 忙中请求合并 + 背靠背合并 + **force 卡死窗口验证看门狗出 valid**）。
  工程侧 `synth_design -rtl` **elaboration PASS**（49 个源文件）。
- **镜像**：`ascon_keys.coe` 重新生成为 sha256 `77c11ab0…`（与旧版差 **724 个字**），
  blk_mem_gen OOC 重生成后 `.mif` 第 4 行已核对匹配（`3C818193`，旧版 `1A818193`）。
- **未验证**：板上行为（需第 4 次烧录）；若下次仍超时，新固件会打印 `STATUS at rec`：
  **busy=1 → 卡在内部（查 DNA/KDF）；busy=0 → START 仍被吞（查 key_mmio）**，可直接定位。

## 2026-10-27 阶段 4 — PUF/密钥子系统纳入上板工程（RTL 已集成，板级待跑）

owner TBD。本轮改 `src/rtl`（两处集成补丁）+ 工程配置 + 新固件/COE；未 commit 前已验证 elaboration 与 IP 重生成。

- **RTL 集成**：对 f88e178 的 `src/rtl` 应用两个补丁（`git apply` 均干净）——
  `ascon/ascon_mmio.v` 加 `key_hw/key_hw_sel`（锁定后 CPU 写 KEY0..3 被丢弃；`run_key` 取硬件密钥）；
  `soc_top.v` 实例化 `puf_key`(u_puf_key) / `key_mmio`(u_key_mmio)，`ro_clk = clk/4` 过 BUFG，
  复位后等 `0xFFFF` 拍自动尝试一次 reconstruct，`key_valid_p` 到来即锁定 `key_hw_sel`。
  集成后源集哈希：`src/rtl/*.v`(31) **2a83bec0…**（原 `a323df37…`，只有 soc_top 变）、
  `src/rtl/keys/*.v`(5) **be9507ef…**、`src/rtl/ascon/*.v`(9) **96fe170d…**。
  ⚠ 三份已签核 bitstream 对应的是 **PUF 之前**的源集，不能从现在的工作区重现同一字节；其哈希已冻结在
  `docs/freeze_checkpoint_20261027.md`。
- **固件**：`src/firmware/keys_rv32` 构建成功（text 2474 B / 620 words）→ `ascon_keys.coe`
  sha256 `bebed9437961d774…`；`.mif` 第 3 字指纹 **1197**（sw=A197、ise=2197+1E018193、hw=2197+81018193、keys=1197）。
- **工程**：`riscv_vivado_project` 加入 5 个 keys 源（源文件 43→49）、`build/keys_ro_pblock.xdc`（约束 1→2）、
  `Coe_File = ascon_keys.coe`、`impl_1` 的 `STEPS.OPT_DESIGN.TCL.PRE = build/keys_ro_allow_loops.tcl`（RO 环豁免）、
  `include_dirs` 增加 `src/rtl/keys`；`synth_design -rtl` **elaboration PASS**；
  blk_mem_gen OOC 重生成完成（mif 19:17:42、dcp 19:19:27、`__synthesis_is_complete__`）。
- **预期指标**（依据同 RTL+补丁的 `build/reports/keys_sta_20261025_mmio2`）：WNS **+0.023 ns**、TNS 0、
  0 失败端点、WHS +0.022、LUT **17123**、FF **28498**、BRAM 34.5、DRC **0 条 LUTLP-1**（钩子生效）、布线 0 错；
  最差路径仍在 CPU（`mem_wb → if_stage/pc CE`），不在密钥子系统内。
- **串口预期**：`=== KEY SUBSYSTEM SELF-TEST ===` → `STATUS boot/enrol（含 quality）` → `DNA` →
  `REF/MASK/DITHER/RAW` 各 4 字 → `STATUS recon` → 通过时 `PASS key subsystem: enroll + reconstruct stable` + `DONE`。
  已知失败条件：`FAIL enroll timeout` / `FAIL quality=0`（RO 未工作）/ `FAIL puf mismatch` / `FAIL dna-only fallback`。
- **未验证**：板上任何一项（用户将烧第 4 个 bitstream）；DNA 位序（`SHIFT_SKIP`）需与 Vivado 读到的 Device DNA 比对；
  enroll 得到的 REF/MASK 需回填 `KEY_INIT_REF/KEY_INIT_MASK` 才能免去每次上电 enroll；P02 稳定性/纠错未测；
  本阶段 bitstream **不替代**已冻结的三套（P0 演示仍用 sw/ise/hw）。

## 2026-10-26 — 首次上板：软件版 Ascon 板级 KAT 6/6 PASS（100 MHz，WNS +0.087 ns）

owner TBD；本轮由用户在 Vivado GUI 手工建工程/综合/实现/烧录，我在旁核验报告与日志。未改 RTL/XDC。

- **工程**：`board/vivado_zynq7000_xc7z020_ascon/first_time/`（手工新建，非 baseline 副本；XPR=`first_time.xpr`，
  srcs=`riscv_vivado_project.srcs`）。Vivado 2025.2，part `xc7z020clg400-1`，top `top_pl_bram`。
- **源**：`f88e178` 的 `src/rtl/*.v`(31) + `src/rtl/ascon/*.v`(8，排除 `*_tb.v`)，**不含 keys/PUF**；
  旧 baseline `imports/rtl` 快照已重命名为 `rtl_baseline_snapshot_do_not_add`、未入工程。
- **约束**：baseline `const.xdc` 原样（U18 50 MHz、N16 复位低有效、T19/J15 USB-UART、H15/L15 LED、L14/K16 KEY）。
- **IP**：`clk_wiz_0`(PLL 50→100 MHz, RESET_TYPE=ACTIVE_HIGH)、`axi_bram_ctrl_0`(AXI4/32b/32768)、
  `blk_mem_gen_0`(32×32768, byte write, COE=`ascon_sw.coe` sha256 `3dcd59a0…`)。
- **综合**（Vivado Synthesis Defaults）：LUT 12214 / FF 15945 / RAMB18 5（BRAM 为 OOC 黑盒）/ DSP 4，
  **CRITICAL WARNING 0**（195 warning 为历史噪音）。报告：`first_time.runs/synth_1/top_pl_bram_utilization_synth.rpt`。
- **实现**（`Performance_ExploreWithRemap`）：**WNS +0.087 / TNS 0 / 失败端点 0 / WHS +0.021**，
  布线 24610/24610 全通、0 routing error，DRC 0 Error/0 Critical（仅 1 条 RTSTAT-10 提示）；
  placed LUT 12426 / FF 16156 / RAMB36 32 + RAMB18 5 = 34.5 / DSP 4。
  最差路径 `u_ascon_mmio/…/FSM_sequential_state_reg[3]/C → p12_in_reg[215]/D`，与 10-24 签核同一条。
- **bitstream**：4,045,687 B，sha256 `f4233827e3005e115bb30e31e64a75a4487f9dfdd9efe2946d9c924b8ffb5c2e`
  （已存档 `build/local/board_bitstream/top_pl_bram_sw.bit`，生成物不入 git）。
- **板级链路**：ATK-U18 下载器（FT232H，需装 Vivado 自带 cable driver）+ CH340 **COM7**，
  115200 8N1 无流控，底板 P5 短接 **3–5 / 4–6**（PL 串口），JTAG 下载（非 QSPI）。
- **板级结果（ascon_sw）**：banner → **KAT 6/6 PASS**（empty/1B/16B/16B+AD/17B/32B）+ **tamper reject PASS**
  → warm benchmark：enc16B **20806 cyc**/4495 inst/CPI 4.62、enc32B 25787/5600/4.59、
  dec16B 21360/4722/4.51、dec32B 26444/5857/4.51 → `===DONE===`。
- **与 2026-10-15 仿真基线的差异（+23.5% cycles、+7.6% inst、+14.6% CPI）暂不归因**：
  ①今天用 xpack GCC 15.2.0，10-15 仿真用 WSL GCC 13.2（text 39124 vs 38852 B 印证二进制不同）；
  ②10-15 之后 RTL 落了 B(dcache store buffer)/C(mult 寄存器化)/D(中断判决拆拍)；
  ③仿真是 `sim/ascon` 的简化 AXI BRAM 模型，板上是真 `axi_bram_ctrl`。
  已用同 RTL + 同编译器重跑 sw 仿真做对照（证据目录 `build/local/verify_teammate/build/local/board_cmp`）。
- **对照结论（同 RTL f88e178 + 同编译器 xpack GCC 15.2.0）**：仿真 enc16B **17353 cyc / 4493 inst / CPI 3.86**、
  enc32B 21515/5604/3.83、dec16B 17847/4730/3.77、dec32B 22094/5865/3.76，KAT 6/6 PASS。
  **指令数与板上逐项一致（4495 vs 4493、5600 vs 5604、4722 vs 4730、5857 vs 5865，差 ≤8 条）**，
  → 之前的 +7.6% inst 差额确认为**编译器版本差异**（GCC 13.2 → 15.2），不是算法或固件差异。
  剩余 **cycles 一致地高 +19.7~19.9%，折算 CPI +0.76/指令**（3.86→4.62），四个操作同比例
  → 归因为**存储子系统延迟**：板上走真实 `axi_bram_ctrl_0`，仿真是 `sim/ascon` 的简化 AXI BRAM 模型；
  具体到 icache/dcache miss/refill 的拍数差，需加 miss 计数器才能定量（V01 细化项）。
  因此：C04/I07 里记录的 16840 / 21018 / 17226 / 21461 是**仿真值**，板上实测比之高约 20%，
  报告必须分列，不能混用；板上三套之间的加速比仍以板上同条件测量为准。
- **ISE 版板上结果（第二轮，23:21）**：COE 换 `ascon_ise.coe`（sha256 `7ef0b829…`），OOC 重生成后
  `.mif` 第 3 字由 `A197` 变 `2197`（确认镜像切换，见 23:03:36 时间戳）；实现仍
  **WNS +0.087 / TNS 0 / 0 失败端点 / WHS +0.021**、24610/24610 全布通、DRC 0 Error，
  资源 FF 15945 / LUT 11266 与 sw 版**逐位相同** → 换 COE 未动逻辑。
  bitstream `f85eb1a63284059f5dbc785aa791d81c9a6f558a27843c2767d2414909144392`（4,045,687 B，
  与 sw 版差 31,505 字节）。
  串口：KAT empty/1B/16B/16B+AD + **dec round PASS** + **tamper PASS**，
  **warm 16B 加密 ISE cycles = 2570**（= 160.6 cpb）。
  → **板级加速比 20806 / 2570 = 8.10×**（同板同条件，20806 为第一轮软件版实测）。
  2570 与 `docs/cpu_pipeline_flow.md` 记的 ISE 2559 拍同量级；10-15 仿真的 1880 是旧 RTL/旧编译器口径，不可直接与板上相减。
- **ISE 版仿真对照（同 RTL f88e178 + 同编译器 15.2.0）**：仿真 **2496 cyc**（KAT 6/6 PASS），板级 **2570**，
  **仅差 +3.0%（+74 拍）**。与软件版对照（17353 → 20806，**+19.9%**）相比差异极大。
  → 说明板上那部分额外开销**与访存密度成正比**：ISE 把置换搬进硬件后指令数/访存大幅减少，
  对存储延迟不敏感；这也解释了为什么 **板上加速比 8.10× 反而高于同编译器仿真比 6.95×**
  （17353/2496）——软件版被存储延迟拖得更多。报告里应写这个解释，而不是把两者混为一谈。
- **同 RTL/同编译器口径汇总**：仿真 sw 17353 → ise 2496（6.95×）；板上 sw 20806 → ise 2570（**8.10×**）。
- **MMIO 版板上结果（第三轮，2026-10-27 18:56）**：COE 换 `ascon_hw.coe`（sha256 `3e464c48…`）；IP 重生成后
  `.mif` 第 3 字 `2197` + **第 4 字 `81018193`**（hw 独有指纹，ise 版是 `1E018193` —— **只看第 3 字会与 ise 混淆**，
  本轮新增的判据）。实现仍 **WNS +0.087 / TNS 0 / 0 失败端点 / WHS +0.021**、24610/24610 全布通、
  DRC 0 Error；placed LUT 12426 / FF 16156 / RAMB36 32；bitstream
  `2f6f24692533941f902deb812cd7a61192a722b20d3f8536e466e46e4579c544`（与另两份互不相同）。
  串口：KAT empty/1B/16B/16B+AD + dec roundtrip + tamper reject + **len reject**（16B 上限）全 PASS；
  **crypto latency 103 cyc / full MMIO 688 cyc**。
  同 RTL 同编译器仿真为 99 / 670 → 板上 **+4.0% / +2.7%**，与 ISE 的 +3.0% 同一量级（都是访存少的版本），
  再次印证「板上额外开销 ∝ 访存密度」。
- **板上三套齐全（warm 16B 加密，同板同 100 MHz）**：
  软件 **20806 cyc（1.0×）** → **MMIO 688 cyc 端到端（30.2×；裸 crypto 103 cyc ≈ 202×）** →
  ISE **2570 cyc（8.10×）**。三份 bitstream sha256：sw `f4233827…` / ise `f85eb1a6…` / hw `2f6f2469…`
  （均存于 `build/local/board_bitstream/`，不入 git）。
  日志注意：本版串口开头有约 2 行乱码（开串口瞬间的帧错），banner 之后全部干净，不影响判据，原始日志按原样保留。
- **未做**：三套统一脚本化的板上 benchmark（当前是各固件自打印）、IO delay 约束、PS/PYNQ、PS 端到端、
  ISA 回归板上抽样。

## 2026-10-26 — 独立核验：队友 preboard 提交 / PUF 子系统 / 余量口径纠正（+0.087 而非 +0.039）

owner TBD；只读核验 + 文档改正，未改 RTL、未 commit/push。核验环境：Vivado 未启动；
Icarus 14.0 (devel)、riscv-none-elf-gcc 15.2.0、Python 3.14；队友代码用 `git archive origin/main`
导出到 `build/local/verify_teammate/` 后独立跑，不动本工作区。

- **余量口径定为 +0.087 ns。** `+0.039` 是 `run_prod_arm.tcl mode=hook`（生产策略 + 强制复制钩子）
  实验臂的数字，2026-10-25 01:10 的结论原文即「复制步骤**不进流程**，当前 100 MHz 最好成绩 =
  生产策略 + C + D = **+0.087 ns**」。无钩子生产流程已有 6 个臂逐位相同：`prod_ctl`、`pr_ctl`、
  `pr_ctl2`、`pr_mfonly`、`pr_selprops`、`pr_physopt_only`（另有 `r2_ctl`/`r2_popt`）。
  故：无密钥子系统 **+0.087**；PUF 集成 +0.051（RO 压成 1 LUT）/ +0.058（256×5 原语 RO）；
  PUF + key_mmio **+0.023**（`build/reports/keys_sta_20261025_mmio2/`，10-26 14:01）。
  本文件 2026-10-25 板卡段落的「按 +0.039 ns 记」与 `docs/key_subsystem.md` §5 的
  「不含密钥子系统 +0.039」两处已就地改正。
- **队友提交**：`origin/main = 4268b1f`（68fafc8 Navigator 交接 20 文件；4268b1f D-Cache TB 修订 +
  中断验证 + 公共记录）。本地 main 落后 2 个 commit；`git merge-tree --write-tree HEAD origin/main`
  试合并无冲突（本工作区 keys/PUF 为未跟踪新文件，不与之相交）。
- **独立复现（全部真跑）**：
  - `run_tests.py --mode smoke`：**6 PASS / 0 FAIL / 0 BLOCKED / 9 NOT_RUN，exit 0**。
  - `run_targeted_validation.py --mode interrupt`：6 个 RV32 场景 PASS，3 个负向门禁
    （NO_TIMER / BROKEN_MRET / 临时副本绕过 guard）均按预期 exit 1，overall PASS。
  - `--mode dcache` 全量：26 条命令结果与队友声明一致（legacy 臂按设计 exit 1；修订 TB、
    独立契约 TB、4 种子 trace 均 PASS）。本次在我机器上因 `pre_store_buffer_trace_1234567.txt`
    未落盘而整体判 FAIL；单独重跑该命令可正常产出 1.47 MB 文件 → 判为脚本未检查 `$fopen`
    返回值的偶发缺陷（建议加固），不影响 TB 结论。
  - **COE**：`build_firmware.py` 出 sw/hw/ise 三套；其中 ise / sw 的 `.coe` 与我按 hex 独立生成的
    `.coe` **逐字节相同**（sha256 `7ef0b829…` / `3dcd59a0…`，各 32770 行）。
- **「D-Cache 修好」的准确表述是 TB_STALE，不是 RTL 修复**：4268b1f 不含任何 `src/rtl` 变更；
  旧 TB 的 4 项 FAIL 源于 MISS_CAPTURE 拆拍后固定拍数假设过期，修订 TB 与独立 scoreboard 在
  改前/改后两版 RTL 上均 PASS，原 FAIL/exit1 证据保留。
- **PUF 侧**（仍为未跟踪工作区文件，未进任何分支）：`src/rtl/keys/` 5 模块、`sim/keys/` 6 TB、
  `docs/key_subsystem.md`、2 个集成补丁、`build/keys_ro_pblock.xdc`、`build/build_keys_sta.tcl`。
  复跑 `bash sim/keys/run_key_tests.sh`：**tb_puf_key PASS、tb_key_mmio PASS**（REF/MASK 可回读、
  reconstruct 一致、CLEAR 生效、窗口不暴露 key）。`git apply --check` 两个补丁在 f88e178 上干净。
  缺口不变：DNA 位序需上板对齐、enroll 结果需经 MMIO/ILA 搬出、P02 稳定性未测、未上板未集成。
- **未验证**：完整 regression（在跑）、板级任何一项、PS7/PYNQ 链路、ASCON 独立工程的 STA/DRC。

## 2026-10-25 — 扇出复制第二轮 12 臂：`sel_*` 一根都拆不出来；+0.184 定性为「布线解换盆」

owner TBD；未改 `src/rtl`、`board/`、XDC（全部变体是 `build/local/tests_20261025/` 下的副本），未 commit/push。
工具 Vivado 2025.2，part `xc7z020clg400-1`，top `top_pl_bram`，策略 `Performance_ExploreWithRemap`，核心 10 ns。

- **页面 R1 提的那个实验做完了：单根/双根定点复制也拆不出来。** 12 个臂（单根 / 2 根 / 4 根 /
  属性写网 / 属性写单元 / `MAX_FANOUT`=16 与 128 / 加 `AggressiveExplore` / 不写属性）**一律副本 51 → 51、
  FF 17187 → 17187**，日志一律 `Identified N candidate nets` + `Optimized 0 net. Created 0 new instance.`
  → `-force_replication_on_nets` 只是把网塞进候选清单，是否实例化由 Phase 2 判据决定，判据一致拒绝。
  对照：同一位置对 `u_crypto_aead/state[3]`（fo=628）则真的把扇出从 628 降到 25。
- **上一轮的 +0.184 与复制无关，是"定向扰动布线解"**（8 次逐位相同：R1 的 2 次 + 本轮 6 次）。
  机制用排除法钉死：两臂 **post-place 检查点 32579 个原语的 `NAME→LOC` 逐行 diff 为空**，
  布线后只有 **35 个单元**不同，净表（副本/FF/LUT）完全相同 → 收益只能来自布线解。
- **四味消融**：属性不是必需（`r2_noprop` 不写任何属性仍 +0.184）；**选点必需**
  （`r2_tiny` 点一根 fo=3 的无关小网 → +0.073，比对照还差）；连调两次不叠加（`r2_x2` 仍 +0.184）；
  **临时过约束逼 phys_opt 干活没用**（`r2_tight`：核心 9 ns 跑 AggressiveExplore，phys_opt 确实动手
  —— Fanout 相位 TNS +57.529、新增 13 单元 —— 但恢复 10 ns 后只有 **+0.057**，且 LUT +87 / FF +48）。
- **新墙换人了**：+0.184 网表的最差是 `sel_ex_mem_rs1_o_reg → if_id/pred_target_o_reg[12]/D`，
  13 级 / logic 3.520 / net 5.808，其中 **8 级是 `u_mem_wb/captured_addr_reg[*]_i_1/CO` 的 32 位增量链**
  （X57Y33→Y39 竖向，每级 0.114 ns），末端 `dcache_cpu_addr[29]` 一根网 0.988 ns；
  `sel_*` 自己的 171 扇出网只占 0.955 ns。
- **`-force_replication_on_nets` 不能用在 post-route**（preflight 实测：
  `ERROR: [Vivado_Tcl 4-265] ... not supported yet for post-route physical synthesis`），
  只能在 `PHYS_OPT_DESIGN.TCL.POST` 用。

验证命令（全部真跑，退出码 0）：
```bash
bash build/timing_tests/run_batchR2.sh      # 8 臂，14:17→14:40
bash build/timing_tests/run_batchR2C.sh     # 4 臂（r2_tight 重跑一次，见下）
python build/timing_tests/collect_r2.py     # 汇总
```
证据：`build/reports/tests_20261025/<tag>/result.txt`、`build/local/tests_20261025/logs/<tag>.log`、
`build/reports/tests_20261025/_place_cmp/*.txt`（32579 行 LOC 快照）、
`build/timing_tests/logs/preflight.log`；分析写进 `docs/timing_route_replication_r2.md`。

**返工记录**：r2_tight 第一版用 `set_property PERIOD` 改时钟 → `ERROR: [Common 17-107] Cannot change
read-only property 'PERIOD'`，臂在 phys_opt 前就退出（14:47），改成重新 `create_clock` 后重跑成功（15:31）。
另有一次 `run_batchR2.sh` 起跑后才发现钩子被拷进 run 目录会断掉 `r2_lib.tcl` 的相对 source，
杀掉重落后才正式跑（14:17 那次）。

**未验证**：+0.184 的机制只有排除法证据（没有布线器 criticality 的直证）；换 RTL 后是否仍成立（`r2_tiny`
已证明不是"必然变好"）；`docs/freeze_checkpoint_20261018.md` §2 全套功能回归未跑；8 级 CARRY4 增量链的
RTL 改法未做。**下一接收任务**：`sel_*` 复制到此结案，转 13 级路径的进位链结构性改法（owner TBD）。

## 2026-10-25 — 板卡确认（正点原子领航者 ZYNQ7020）；密钥子系统 RTL 落地并仿真通过

owner TBD；HEAD `f88e178`。未改 `src/rtl` 既有文件（新增 `src/rtl/keys/` 与两个补丁），
未综合、未上板，未 commit/push。

- **板卡身份确认**（资料盘 `3_开发板原理图和硬件相关文件/NAVIGATOR_ZYNQ_IO.xdc`）：
  正点原子 领航者 ZYNQ7020，`sys_clk`=**U18 50 MHz**、`sys_rst_n`=**N16 低有效**、
  USB-UART=**T19/J15**、`led[1:0]`=**H15/L15**、`key[1:0]`=**L14/K16**，与仓库 `const.xdc`
  **逐引脚一致**，`RESET_ACTIVE_LOW=1` 默认匹配 → 引脚不用改，50 MHz + MMCM ×2 = 100 MHz
  与 STA 前提一致，B03 的“板型未知”风险解除。资料盘另有《领航者 ZYNQ 之 PYNQ 开发指南 V3.2》
  → P1 的 PYNQ 路线可行。
- **时序现状**：`805b01a` 的 +0.039 是「生产策略 + 强制复制钩子」实验臂的数字（复制已否决、不进流程）；
  生产流程（无钩子）按 **+0.087 ns** 记（6 个无钩子臂逐位相同，见 2026-10-26 核验条目）；
  最差路径已变成 `u_crypto_aead FSM → p12_in`（1 级逻辑、9.29 ns 走线）。
- **密钥子系统**（用户决策：PUF+DNA 组合 / 内部直连 CPU 不可读 / 多数表决+片内 helper / 100 MHz）：
  新增 `src/rtl/keys/{device_dna,ro_unit,ro_puf_core,puf_key}.v`、
  `sim/keys/{tb_puf_key,tb_dna_min,DNA_PORT_sim}.v`、`sim/keys/run_puf_key.sh`。
  仿真 5 项全 PASS：DNA 读出正确、enroll/reconstruct key 一致、无 helper 正确降级、
  DNA-only 确定性、helper 被破坏时 fallback key == DNA-only key。
- **集成补丁**（`git apply --check` 均通过）：`key_subsystem_ascon_mmio_hwkey.patch`
  （加 `key_hw/key_hw_sel`，锁定后 CPU 写 KEY 被丢弃）、`key_subsystem_soc_top_inst.patch`
  （上电自动生成一次、key 就绪即锁定）。patched 源 + keys 全 SoC **elaborate 干净**。
- **风险/未完成**：① DNA 位序需上板与 Vivado Device DNA 比对一次（`SHIFT_SKIP`）；
  ② enroll 的 ref/mask 目前只能靠 ILA 读出（缺 MMIO 状态口）；
  ③ 约 +1.8k LUT / +6k FF，在 +0.039 ns 余量下必然要重跑 STA（RO 独立 pblock 或慢时钟域），
  否则演示走 80 MHz。
- 文档：[key_subsystem](../docs/key_subsystem.md)。
- 顺带修正 draft 的两个真实缺陷：`device_dna` 在 IDLE 每拍清零 `dna`（上层取不到值）、
  SHIFT 相位未对齐（加 `SHIFT_SKIP` 参数）；`puf_key` 里 `ref` 是 SystemVerilog 保留字，
  改名 `h_ref`。
- **追加（14:40–15:30）①RO 独立 pblock + 慢时钟域，③100 MHz 实测**：重写 `ro_puf_core`
  为「RO 自身当时钟计数 + ro_clk(25 MHz = clk/4, BUFG) 控制域 + req/done 翻转握手」；
  新增 `build/keys_ro_pblock.xdc`（pb_ro_puf，X60Y115:X113Y149）与 `build/build_keys_sta.tcl`。
  集成 STA（生产策略，`build/reports/keys_sta_20261025/`）：
  **WNS +0.051 / TNS 0 / 0 失败端点 / WHS +0.035**，LUT 13924(+446)、FF 22088(+4901)、
  BRAM 34.5(−4)；最差路径仍是 CPU 的 `id_ex→dcache/captured_wdata`，**不在密钥子系统中**。
  落点核查：u_puf 下 7275 个叶子单元 **全部**落在 pb_ro_puf（X56..113 / Y102..149），
  CPU 被压到 X27..96 / Y0..92，两者物理不相交。
- 顺带记录一个**真实设计缺陷**（草稿 `../IO/ro_puf_top.v` 同样存在）：用系统时钟去数 RO 上升沿
  在硬件上测不出频率（RO 150~300 MHz 快于采样时钟，直接混叠），已改为 RO 驱动计数器时钟、
  窗口结束停计数后取静态快照。另有 `device_dna` 在 IDLE 每拍清零 `dna`（上层取不到值）与
  SHIFT 相位未对齐（新增 `SHIFT_SKIP`）；`puf_key` 里 `ref` 是 SV 保留字，改名 `h_ref`。
- **追加（15:30–15:50）RO 原语化 + 复测**：DRC 发现第一版用 `assign` 链搭的 5 级环被综合
  压成 **1 个 LUT**（`1 LUT cells form a combinatorial loop`），`STAGES` 参数失效、部分 RO 被吞。
  改为显式 `LUT2(NAND, INIT=0010)` + 4×`LUT1(INV, INIT=01)`，每级 DONT_TOUCH；
  复测（`build/reports/keys_sta_20261025_r2/`）：**WNS +0.058 / TNS 0 / 0 失败 / WHS +0.020**，
  LUT 14802(+1324)、FF 22094(+4907)。DRC 变为 `5 LUT cells form a combinatorial loop`，
  报告覆盖 `g_ro[0..255]` 共 **256 根**（stdout 只打印 101 条是打印上限）。
  最差路径仍是 CPU `id_ex → dcache`，密钥子系统不在关键路径上。
- **追加（15:50–16:00）复现 + RO 结构定量核实**：第三次独立 run（`keys_sta_20261025_clean/`）
  WNS 仍为 **+0.058 / 0 / 0**，与 r2 逐位一致 → 结果可复现。
  钩子脚本 `build/keys_ro_allow_loops.tcl` 修正后实测 **ro_lut_cells=1280、nets_tagged=1280**
  （= 256 RO × 5 LUT），定量证明每根 RO 都是 5 级环、无合并。
  两个踩坑点：ALLOW_COMBINATORIAL_LOOPS 不能写在 XDC（综合前 net 不存在）；
  也不能用层次名过滤（综合后 `u_puf` 被打平，必须按引脚找 net）。
  已归档的 clean run 用的是旧钩子，所以 DRC 报告里仍有 256 条 LUTLP-1（预期、可容忍），
  下一次 build 会带上新钩子。
- **追加（16:00–16:20）key_mmio 落地**：新增 `src/rtl/keys/key_mmio.v`（挂在 Ascon 窗口 0x80 段，
  `ascon_addr_sel` 32..52，共 21 个字：STATUS/CTRL/DNA_LO/DNA_HI/QUALITY/REF×4/MASK×4/DITHER×4/RAW×4），
  `puf_key` 增加 `helper_ref_o/helper_mask_o` 输出；`soc_top` 用 `ascon_rdata = ascon_rdata_core | key_rdata`
  合并（不改共享的 `bus_interconnect.v`）。**窗口不暴露 key**。
  新增 `sim/keys/tb_key_mmio.v` 与 `sim/keys/run_key_tests.sh`，两套测试均 PASS：
  `tb_puf_key PASS`、`tb_key_mmio PASS`（窗口外读 0 / enroll→ready·enrolled·done·quality=89 /
  DNA_LO·HI 正确 / REF·MASK 回读一致且可用位非空 / reconstruct key 与 enroll 一致 / CLEAR 生效）。
- **钩子生效**：`RO_ALLOW_LOOPS: ro_lut_cells=1280 nets_tagged=1280`，DRC 里 **LUTLP-1 归零**
  （之前 256 条）。
- **key_mmio 集成 STA 已完成**（`keys_sta_mmio2`，生产策略）：
  **WNS +0.023 / TNS 0 / 0 失败端点 / WHS +0.022 / 布线错误 0**；
  LUT 17123(+3645)、FF 28498(+11311)、BRAM 34.5；最差路径是 CPU `mem_wb → pc CE`，不在密钥子系统里。
  DRC LUTLP-1 **归零**（钩子 `ro_lut_cells=1280 nets_tagged=1280` 生效）。
  代价：相比不含 key_mmio 的 +0.058，加了 21 字 MMIO 窗口后 WNS −0.035 ns；如余量吃紧可砍
  DITHER/RAW 回读或把 N_RO 降到 128。
  首轮 `keys_sta_mmio` 在布线中途进程消失（无 ERROR 行、无 result.txt），已用新 tag 重跑并完成。
- **新增自检固件 `src/firmware/keys_rv32/`**（main.c + 复用 crt0/uart/libc/ld，620 words）：
  enroll → 打印 STATUS/DNA/REF/MASK/DITHER/RAW → reconstruct → 判定 PASS。
  `bash src/firmware/keys_rv32/build.sh` 编译通过（text 2474 B）。
  新增 SoC 级 TB `sim/keys/tb_keys_fw.v` + `sim/keys/run_keys_fw.sh`（KEY_WINDOW=256 提速，
  `KEY_SIM_DNA` 注入 DNA），跑真固件结果：
  `===DONE[RESULT] tb_keys_fw PASS (framing_err=0)`，输出 STATUS boot=0000003a、
  enrol=00008026(quality=128)、DNA=000123456789abcd、recon=00008026、REF/RAW=75df75df 循环。
- **两处 RTL 修正（仿真暴露的真问题）**：
  1. `key_mmio` 的 mismatch/fallback 原为粘滞位，CLEAR 后会被 puf_key 的旧电平立刻重新置位
     → 改为**实时透传**（puf_key 每次 start 自清），只有 ready/done 仍粘滞。
     修正后 enroll 的 STATUS 从 `0000803e`（mism|fb 误置）变成 `00008026`。
  2. `soc_top` 增加参数 `KEY_SIM_DNA`（默认 0，仅仿真注入；硬件走 DNA_PORT 原语），
     否则 SoC 级仿真里 DNA 恒为 0，看不出位序问题。
- **注意**：仿真里 REF/RAW 是 `75df75df` 循环、DITHER=0、quality=128，这是 RO 行为模型的产物，
  不能当 PUF 质量证据；已写进 `docs/key_subsystem.md` §6 已知限制。
- **最终集成 STA（`keys_sta_final`，含 key_mmio + 固件验证过的 RTL，生产策略）**：
  **WNS +0.168 / TNS 0 / 0 失败端点 / WHS +0.015 / 布线错误 0 / LUTLP-1 = 0**；
  LUT 17022、FF 28543、BRAM 34.5；最差路径回到 CPU 内部 `id_ex_u/rs1_o→func_sel_o`。
  同配置的前一次 run（`keys_sta_mmio2`）是 +0.023，差的 0.145 ns 纯属布局差异 →
  **今后报 WNS 必须带 run 名字，不能说"设计已经到 +0.168"**。
- 余量仍仅 +0.058 ns（0.6%）；80 MHz 按周期差算术 ≈ +2.56 ns（cycles/加速比不变）。

## 2026-10-20 — V11 时序余量取证：P&R 空间关闭，建议降频；上板清单成文

owner TBD；基线 `3c6f134`（工作区 clean）。未改 RTL/XDC/XCI/COE，未 commit/push，未上板。

- **余量取证**：4 个 P&R 变体（同一 post-opt netlist，隔离目录）并行实测，
  WNS 分别 +0.008（无 pblock/ExtraTimingOpt）、+0.020（3-region pblock/ExtraPostPlacementOpt）、
  +0.001、+0.001（紧 pblock 两版）；TNS 0、失败端点 0。加上此前 33 策略扫掠与
  V09 修复，**P&R 侧余量空间判定关闭**，最佳 +0.020 ns 不构成可用余量。
- **根因修正**：不是单条坏路径。`acb_remap_routed.dcp` 实测 slack 分布
  <0.1 ns 55 条、<0.3 ns 334 条、<0.5 ns 1058 条、<1.0 ns 3731 条；
  4 个变体各自的最差路径互不相同（`id_ex sel_*_o → if_id CE / dcache DIADI`、
  `ex_mem → dcache lru`、`pc → icache tag → csr → ISE state CE`），
  说明这是一道整体 Fmax 墙（≈100.1 MHz），单点 RTL 断链只能防翻负、不能加余量。
- **布局实测**：`u_cpu_core` 分布 X32..106 / Y0..113，`u_dcache` 单模块跨 111 行，
  全设计仅 22% LUT；但 pblock 紧约束并未改善（+0.001），故布局不是解。
- **建议**：上板频率定 80 MHz；同一已布线网表只改时钟周期实测 WNS：
  90 MHz +0.965、80 MHz +2.340、75 MHz +3.165（折算到最终网表 ≈ +1.11/+2.48/+3.31），
  WHS 恒 +0.023；cycles/cpb/加速比不变。保 100 MHz 则只做 ISE CE 断链防翻负。
  任何上板版本必须重新 STA（PS7/IO/时钟源全变）。
- **文档**：[时序余量方案](../docs/timing_margin_plan.md)、[上板分步清单](../docs/board_bringup_plan.md)；
  新增脚本 `build/sweep_margin_phys.tcl`、`build/probe_timing_wall.tcl`、`build/probe_geometry{,2}.tcl`；
  证据 `build/reports/margin_20261020/*/`、`build/local/margin_20261020/`。
- **未完成**：降频后的实测 STA（需改 XCI，待用户决定）；L1 RTL 断链（属 RTL owner）；
  B02/B03/B04/V01/V03/Y01~Y05/S01~S05 状态不变。
- 首轮脚本用 `get_timing_paths -pulse_width` 取 WPWS 抛错（2025.2 无该选项），
  发生在写 result.txt 之前；RPT 正常，数字取自 `route_timing.rpt`，脚本已修正。

### 追加：砍 dcache 评估 + 架构改动方案（用户询问）

- 导出 14164 条 slack<2.0 ns 路径逐条分类（`build/probe_path_classes.tcl` →
  `build/local/margin_20261020/paths_lt_2p0.csv`）：
  `id_ex_u` 最差 **−0.140**（647 条 <0.5 ns）、`u_if_stage` −0.071（358）、
  `u_dcache` −0.071（308）、`u_icache` +0.074（124）、`u_ex_stage`/`u_ascon_ise` +0.133（206/198）、
  `u_ascon_mmio` +0.108（1670 条 <1.0 ns）。最差 10 条中 9 条从 `id_ex_u` 的旁路选择寄存器出发。
- **砍 dcache 结论：时序收益 0**（所有 dcache 相关路径消失后剩余 WNS 仍 −0.140，最差路径在
  id_ex 内部），性能为负（load 命中 1 拍 → AXI 读 ≥4 拍，且软件基线掉得比 ISE 多，
  会虚增加速比）。不做。
- 收益模型：单模块 +1.5 ns → 只有 id_ex 能到 −0.071；dcache+id_ex +0.089；再加 if_stage +0.108；
  全部模块才 +1.281 → **要 +1.0 ns 必须多模块协同**。
- 方案与门禁：[cpu_timing_architecture_plan.md](../docs/cpu_timing_architecture_plan.md)
  （B `bus_addr_r` CE 断链、C store buffer 一级、E ISE cancel 移出 CE 锥——均 0 周期；
  A id_ex 旁路网提前寄存、D if 控制、F mmio 内部拆拍）。估算 2.5 天 + 全套回归，与 10-27 冻结冲突。
- 并行免费尝试：`build/synth_margin_variants.tcl`（flatten full + PerformanceOptimized /
  AlternateRoutability / rebuilt+AlternateRoutability，实现统一 ExploreWithRemap），
  结果 `build/reports/synth_margin_20261020/<tag>/`；**已跑完**：
  `flat_perf`（full+PerformanceOptimized）**WNS +0.034** / TNS 0 / 0 失败；
  `flat_alt` −0.470（561 失败）；`rebuilt_alt` −0.008（3 失败）。综合选项不是解，
  但 flatten=full 可与方案 A 一起带。

### 追加 2：B + E 补丁落地并验证等价（用户指示“先做 B+C+E”）

- 补丁（可直接 `git apply`，未改 `src/rtl`）：`build/patches/timing_B_dcache_bus_addr_ce.patch`
  （dcache `bus_addr_r` 使能改为 `cache_access_fire`，去掉 cacheable 12 位比较与地址依赖）、
  `build/patches/timing_E_ascon_ise_cancel_ce.patch`（`cancel` 移出 320 位 `state` 使能，
  改为 `cancel_d` 延迟一拍物理清零 + `{cancel,cancel_d}` 读掩码，写入优先于清零）。
- 等价性（`build/check_bce_patches.sh`，控制组=当前 `src/rtl`，打补丁=隔离副本）：
  ise PASS/2496、ise+HOLD_ISE PASS/2496、ise+RESET_ISE PASS/2496、
  ise 安全套件 **402 checks PASS/0 failed**、hw PASS（99/670 cyc）、
  sw PASS（17353/21515/17847/22094 cyc）——**六种场景逐项一致，周期数完全相同**。
- 说明文档：[timing_bce_patches.md](../docs/timing_bce_patches.md)。
- STA（ExploreWithRemap，打补丁 RTL）已提交后台运行，结果待补；
  预期 WNS 仍在 −0.14/+0.01 量级（#1 在 id_ex CE 锥，B/E 碰不到）。
- C（store buffer）本轮未做：它解的是 #3/#4（−0.047/−0.019），需处理 back-to-back store、
  store→load 字节转发、fill 端口冲突，风险高于收益，排在方案 A 之后。

### 追加 3：B/E 判定净负，A1 落地（2026-10-20 22:50）

- **B/E 不落地**。功能/周期全等价，但 STA 实测：`e_only`（仅 ISE cancel −0.273 ns / 137 失败端点）、
  `e2`（dcache CE + 修正版 cancel，−0.643 ns / 649 失败端点），对照 control +0.007。
  原因：WNS 对网表扰动有 ±0.7 ns 敏感度，这两处只重排使能、不减逻辑深度。
- **A1 落地**（`build/patches/timing_A1_ex_stage_alignment_narrow.patch`）：
  `src/rtl/ex_stage.v` 非对齐判定改用 3 位部分和（`(a+b)[2:0] == (a[2:0]+b[2:0])[2:0]`），
  把 32 位地址加法器从 `trap → flush → ID/EX 使能` 锥里摘出。
  实测 **WNS +0.016 / TNS 0 / 0 失败端点 / WHS +0.012 / LUT 11821(+3)**；
  最差类由 13 级/8 CARRY4/logic 3.564 ns 变为 9~10 级/1~2 CARRY4/logic ~1.93 ns。
  功能与周期六场景逐项一致（ise/stall/reset 2496、安全 402/0、hw PASS、sw 17353/21515/17847/22094）。
- **100 MHz 天花板**：A1 + 4 个 floorplan/directive 变体 = +0.003 / +0.022 / −0.041 / −0.297，
  最优 **+0.022**（A1 + pblock X50Y0:X113Y99）。最差路径始终是 `pc → icache tag → CE`
  （logic ~2 ns、route ~7.6 ns 占 78%）。不改流水结构，100 MHz 余量就到 +0.02 量级为止。
- 下一步二选一：`icache` tag 打一拍（+1 取指周期，需重测全部 benchmark，与 10-27 冻结冲突），
  或演示/上板定 80 MHz（同网表实测 +2.340 ns，cycles/cpb/加速比不变）。
- 证据：`build/reports/bce_timing_20261020{,_a1,_a1_pr,_b_only,_e_only,_e2}/`、
  `build/reports/margin_a1_20261020/*/`、`build/local/patches*/`。



## 2026-10-18 — V10 数据复验一致；并行恢复产物按用户决定暂保留

owner TBD。用户明确选择保留最终双策略 RPT，清理旧报告/无用 BAT/JSON/TXT 及可再生缓存，
并要求删除后重检数据。曾执行删除564个文件（17.82MiB），含312旧RPT、66中间JSON、48TXT、4BAT；
随后并行会话恢复/重生成6个路径，用户最新决定暂时保留，当前并非只剩最终报告。
必要元数据、最终DCP、生产源、KAT、ISA控制/最终候选结果未删。逐文件删除hash及231项保留hash已记录。
8项CPU新label真实重编译/仿真全部PASS，源码/有效固件bin/测试输出/周期逐项一致；
安全/5单元一致，ISA仍49 PASS+ma_data既有1 FAIL；231项保留hash均不变。
原复验脚本exit 1及FAIL JSON保留：唯一失败是删除目标重新出现的留存检查，不是数据不一致。
复验判读为数据PASS、留存DEFERRED；本任务最终清理收口blocked，等待并行任务结束再确认。
本次不改RTL/固件/XDC，不重做布局布线；旧汇总脚本增加缺报告时的明确退出提示。
详见 [V10 清理与复验](../docs/workspace_cleanup.md)。未commit/push，未上板。

## 2026-10-18 — V09 100 MHz 芯片级 STA 收敛（已核验）

owner TBD；基线 f52bc49 + 工作区 dcache/ascon_ise/ex_stage/mult 修改（另一个 AI 完成，
本 Agent 独立核验）。未 commit/push；未上板。

- **收敛结果（已核验两份最终报告 timing_acb_20261018/）**：
  Performance_ExplorePostRoutePhysOpt WNS=+0.001/TNS=0/0 失败端点/WHS=+0.031；
  Performance_ExploreWithRemap WNS=+0.007/TNS=0/0/WHS=+0.023。100 MHz STA 通过。
  此前 93 个 ISE s_reg 复位端点与 48 个乘法器端点全部消除。
- **功能回归（ACB 套件，已核验）**：sw/hw/ise 与 security、stall/reset 注入全 PASS；
  ISA 49 PASS + 1 FAIL（rv32ui_ma_data），与修改前对照组完全一致（既有失败，非本次引入）。
  周期恢复：hw 670 / ise 2496（与 HEAD 持平）。
- **余量警示**：收敛余量仅 1-7 ps，处于布局噪声量级（s_reg 路径实测跨布局摆动
  -0.05~-0.128）。双策略同为正提供一定防误证，但此后任何 RTL 改动都可能重新翻负；
  建议以此为冻结检查点，再动必须全套复验。
- **未完成**：板级 IO delay/板型/pinout（B02/B03）、PS/PYNQ（P1）、Ascon 固件镜像
  替换（COE 仍 FreeRTOS）、板上 KAT/benchmark（V01/I08/Y01）。芯片级收敛不等于上板通过。
- 证据：build/reports/timing_acb_20261018/{postroute,remap}/、
  data/ascon/results/key_lifecycle/*_timing_acb*.json、data/ascon/results/isa/{fix_r1_control,timing_acb}/。

## 2026-10-18 — V09 A→C→B 与双策略完成：既有 100 MHz STA 通过

owner TBD；用户要求先解除 93 个 ISE 私有复位端点，再处理乘法器 48 端点、恢复 store/MMIO 延迟。
已通过独立 fix_r1 DCP 端点导出证实基线分类 93/48/11/4（共 156），未改原 DCP/扫掠工程。
A 注册 ISE 局部 reset；C 注册乘法输入/输出、done 保持到 ack；B 仅让 load miss 走 MISS_CAPTURE。
A/C 定向 Icarus 与 XSim 测试通过，恢复的 50 项 RV32I/M 指令体全部重跑：49 PASS、ma_data FAIL；
控制快照同样失败（不支持硬件非对齐读），不隐去 exit 1 或宣称全绿。最终整机 8 项、
MMIO/ISE 生命周期及单元 5/5 全部 PASS，生产源码 hash 与当前工作区匹配。
软件、hw full MMIO、ISE 周期恢复到 HEAD 的 17353（enc16B）/670/2496，B 的性能代价已收回。
两策略同快照实现通过 Ross 完成（exit 0，3895.571秒）：PostRoute WNS=+0.001/TNS=0/WHS=+0.031；
Remap WNS=+0.007/TNS=0/WHS=+0.023，均 0 setup/hold/pulse 失败端点、0 路由错误。
**原 93 个 ISE、48 个乘法器、11 个 dcache 与 4 个其他端点类别全部归零**；未改 LRU/频率/时序例外。
40 个生产源 hash 与测试工作区一致，XDC 与 baseline 副本 hash 相同。
候选推荐 Remap（LUT11752/FF16040/BRAM38.5/DSP4）；只余 7ps，不宣称跨变更鲁棒性。
这仅是既有约束下 STA 通过：3 个输入/3 个输出仍缺 IO delay，方法学/板级电气与 DRC/实板未验收。
详见 [V09 验证](../docs/timing_acb_validation.md)。
V09 本轮范围 done；未 commit/push，未上板；完整特权/RV64/嵌套中断门禁仍未验收。
下一接收 B03/V01/I08，先做板卡与 IO/电气约束/DRC，再进行 bitstream/实板 KAT。

## 2026-10-18 — V08 dcache MISS_CAPTURE 功能修复 fix_r1 + Ross 接入 OpenCode

owner TBD；基线 f52bc49 + 工作区。按 [dcache_fix_plan_for_opencode.md](../docs/dcache_fix_plan_for_opencode.md) 执行。

- **Ross**：本机已有 vivado-mcp-server 2026.9.1；登记到 OpenCode 全局配置 `mcp.servers.vivado`
  （`--stdio`，VIVADO_PATH=2025.2），已实测连接并用于 vivado-rtl-lint。
- **dcache.v 修复**：MMIO 读改为固定延迟移位（对齐延后一拍的 bus_mmio_re）；MISS_CAPTURE
  全部改用 IDLE 拍寄存的请求类型标志，不再读活 hit/cacheable/cpu_re_i；总线请求一律单拍脉冲
  （原 bus_mem_re_r 在 FILL 期间保持高，会让互连排队第二个伪读突发）。接口不变。
- **功能门禁全 PASS**：HEAD 对照筛选、wt 筛选、sw/hw/ise、hw/ise --security（123/0、402/0）、
  单元 4/4、ise --stall/--reset；Ross lint 2 条 WARNING 与 HEAD 完全相同。
- **周期代价（同工具链对 HEAD）**：sw +0.3%，hw full MMIO 670→717（+7.0%），ise 2496→2550（+2.2%）。
- **时序（ExplorePostRoutePhysOpt）**：WNS=-0.128/TNS=-11.213/156 端点，WHS=0.005，路由无错误。
  **门禁 4.4（WNS≥-0.078）未过，100 MHz timing not met**。最差 20 条路径无 dcache，
  新最差为 pc_reg→ascon_ise s_reg/R（复位/冲刷扇出，布线占 80%）。证据见
  [清单 §11](../docs/dcache_fix_checklist_en.md)。
- 未 commit/push；未上板。下一步：ISE s_reg 复位扇出路径；可选只让 load miss 走 MISS_CAPTURE。

## 2026-10-18 — V08 全量 33 策略扫掠完成 + dcache 流水线评估

owner TBD；基线 f52bc49。用户授权补测"其余全部策略"并评估另一个 AI 的 dcache 优化。

- **策略扫掠**：四批共 35 个 run（33 个 2025.2 标准流程策略 + 2 个回退重复已剔除），
  全部 exit 0。最优 **Performance_ExploreWithRemap WNS=-0.118/TNS=-1.008/22 端点**，
  超过此前最优 ExplorePostRoutePhysOpt（-0.177）。33 策略完整排名与分析见
  [ascon_strategy_sweep.md](../docs/ascon_strategy_sweep.md)。
  高级实现流程（Vivado Advanced Implementation 2025）在 xc7z020 上不支持（12-25131
  静默回退），其 4 个独有策略批处理不可测，已记录。
- **dcache 流水线版（另一个 AI）**：独立实测（Performance_ExplorePostRoutePhysOpt）
  MISS_CAPTURE 版 WNS=-0.055/TNS=-1.122/40 端点（三版最佳，DONT_TOUCH 版 -0.078）。
  但功能回归 sw 模式 TIMEOUT：CPU 在 t=275、pc=0x100083f0 死锁（MMIO 读等待依赖
  bus_rdata_valid_i 而 bus_mmio_re_r 仅 1 拍脉冲，握手永不完成）。HEAD 原版 PASS 对照。
  两版均功能不可用；修复方案交付另一个 AI：[dcache_fix_plan_for_opencode.md](../docs/dcache_fix_plan_for_opencode.md)
  + [英文清单](../docs/dcache_fix_checklist_en.md)。遗留同名 module 实验文件已移入
  src/rtl/dcache_experiments/（Vivado 同名模块静默选文件的坑）。
- **收敛预期**：新 RTL（修复后）-0.055 + ExploreWithRemap 相对提升 ~0.059 →
  ≈+0.004 ns，100 MHz 极可能收敛；待功能修复后实测。
- 100 MHz timing not met 保持；上板门禁 B02/B03/V01/I08/Y01 不变。未 commit/push。

## 2026-10-18 — V08 实现策略扫掠（Strategy Sweep）

owner TBD；基线 f52bc49，本机 DESKTOP-5H4M0DR（V06 两轮在 xyq 机上）。用户授权
全量 10 策略扫掠并记录数据与分析；未改任何 RTL/XDC/XCI/COE，未 commit/push。

- 本机 Vivado 2025.2 原缺 Zynq-7000 器件库（open_project 报 part 不可用）；用户经
  "Add Design Tools or Devices 2025.2"（C:/ruanjian/.xinstall/2025.2/xsetup.exe）
  补装 Zynq-7000 后 `get_parts xc7z020clg400-1` 通过。
- 新脚本 build/sweep_strategy_timing.tcl（隔离工程、共享 synth、按最终步骤分组
  3 路×6 jobs 并行波、TSV 断点续跑）+ build/aggregate_strategy_sweep.py（.rpt 解析
  交叉核对）。多次中断续跑，最终 exit 0、SWEEP COMPLETE、10/10 策略完成、无真实 ERROR。
- 结果：最优 **Performance_ExplorePostRoutePhysOpt WNS=-0.177/TNS=-2.968/31 失败端点**，
  其次 Performance_Explore -0.273、NetDelay_high -0.325；最差 Default -0.942。
  与本机重跑的 Default/ExplorePostRoute 与 V06 xyq 机逐位一致（跨机可复现）。
- 结论：10 个内置策略无一收敛 100 MHz；策略空间已关闭，剩余 0.177 ns 属 CPU
  id_ex→dcache CE/DIADI 地址计算路径（路由主导），转入 RTL 修复。
  详见 [策略扫掠分析](../docs/ascon_strategy_sweep.md)，数据在 data/ascon/results/strategy_sweep_20261017/。
- 流程与踩坑沉淀为 skill vivado-strategy-sweep；报告在 build/reports/strategy_sweep_20261017/。
- 上板门禁不变：100 MHz timing not met，B02/B03/V01/I08/Y01 仍待接收。

## 2026-10-17 — V07 Ross/工程Skills评估与有限审查

owner TBD；先完成稳定检查点`2b48a8a730267787b399fe06304ae5e2b53ff203`并推送，草稿
[PR4](https://github.com/HChenZ/amd_fpga_2026/pull/4)明确100 MHz未收敛、未上板；原工作区保留。
Ross官方Windows Server下载遇AMD会话错误19，本机未安装/配置，MCP timing/utilization均not_measured。
文档核实2026.1完整测试基线及各Skill版本差异；当前2025.2/Tcl保留，未升级或启动网络控制服务。

只安装Matt Pocock code-review/diagnosing-bugs/tdd/pr四项，固定提交、无插件重复；12文件hash一致，
本机Codex skills/list四项enabled、0 errors。按code-review做只读双轴审查：需求0项，规范1项P2
（缺失/部分实现快照可能误判匹配）。修复证据门禁，5项测试PASS，独立复核关闭该发现。
新最终源码清单119文件，六组CPU输入和实现RTL未变，无需重跑长仿真或Vivado。

评估与优先级见[工具报告](../docs/ross_and_engineering_skills_evaluation.md)、
[双轴审查](../docs/ascon_branch_review.md)及`data/ascon/results/tool_evaluation/`。
V07评估完成不表示Ross接入或V06时序/板级门禁完成；下轮先核板型和CPU/cache剩余路径，Sweep延后。


## 2026-10-17 — V06 阶段性收尾与证据复核

owner TBD；工作区 E:/amd_fpga_2026_key_lifecycle，分支 fix/ascon-key-lifecycle。
2026-10-16的两轮实现均完整结束；本日只读复核源码/日志/报告，不重开Vivado，不做第三轮优化。
117个源码hash、所有物理报告hash、六组CPU测试输入和实现RTL快照均匹配；XDC/COE及原baseline未改。
blk_mem_gen独立副本仅有工具元数据/checksum改写，功能参数不变，双侧hash已保存。

- 最终软件/MMIO/ISE原KAT均PASS；动态密钥安全检查132/123/402项全部PASS。
  Host Final 28661项、C失败输出23965项、MMIO/ISE RTL 13212/1500项、4个CPU单测、
  4个RTL故障注入门禁与867请求逐周期等价检查均PASS。复用哈希一致证据，未重跑长测试。
- 最终Vivado2025.2、xc7z020clg400-1、top_pl_bram：WNS=-0.177ns、TNS=-2.968ns，
  31个setup失败端点；WHS=0.015ns/THS=0、WPWS=3.750ns/TPWS=0。
  LUT11636/FF15949/BRAM38.5/DSP4；23917个net fully routed，routing errors=0。
- **100 MHz timing not met**。DRC已报告95 Warning/0 Critical Warning/0 Error（部分规则达到上限），
  Methodology另23 Warning。cache地址/hold控制剩余路径、LUT派生复位、BRAM异步控制、PS7与板级IO覆盖仍需处理。
- 安全修复与时序分析可作为阶段性成果提交；V06保留in_progress，上板门禁未过。
  官方固定KAT与运行时参数边界明确，新增3组公开Key/Nonce；没有真实秘密或生成缓存纳入提交。

完整证据：[最终汇总](../data/ascon/results/key_lifecycle/final_validation_summary.json)、
[时序审查](../docs/ascon_timing_review.md)、[密钥审查](../docs/ascon_key_management.md)。
下一接收 B02/B03/V01/I08/Y01；先保存Git检查点，再进行用户授权的Ross/Skills低风险评估。


## 2026-10-16 — V06 密钥生命周期与上板前审查

owner TBD；基于最新 origin/main `c37ecae`，独立 worktree / `fix/ascon-key-lifecycle`。
用户本轮明确授权检查通过后自动 commit/push，原工作区未提交改动全部保留。

- 三套实现均已存在，不能沿用下文早期“未实现 ISE”的结论。新增 [密钥生命周期审查](../docs/ascon_key_management.md)
  与 [板卡清单](../docs/ascon_board_checklist.md)，详细结果索引为 `data/ascon/results/key_lifecycle/validation_summary.json`。
- 修复：MMIO idle CTRL[2] ZEROIZE、BUSY/失败/越界读保护、旧输出清理和尾字屏蔽；
  ISE 失败输出擦除/长度、部分密文 Tag 指针、状态清理、非法索引、完成保持；
  CPU 提前译码遗漏的 custom 操作数旁路/load-use；软件 C 本地敏感对象擦除。
- 固定官方 KAT 不变；3组公开动态 Key/Nonce、27个长度组合由锁定 Final C/Python 交叉核对。
  MMIO 只跑其中21例（AD/消息各<=16字节），不宣称多块接口。
- Host Final 28,661 PASS/0 FAIL，production C raw failure 23,965 PASS/0 FAIL；
  独立 RTL 全源集 Final KAT/置换/认证与故障注入通过。MMIO 13,212、ISE 1,500项检查通过；
  baseline bypass/regfile/EX ALU 与新增 execute cancel/hold 单测通过。
- CPU 软件/MMIO/ISE 的最终 KAT、安全测试和周期结果由上述 JSON/原始日志定稿；
  明确使用 GCC13.2/仿真50MHz，不与队友 GCC15.2 的历史数值混算。
- Vivado2025.2可运行，原始三个IP未锁定且再生成成功。独立副本综合0 errors/0 critical warnings；
  实现结果、时序、资源、DRC在最终汇总中列明。原 baseline、XCI、XDC、COE不改，579项恢复资产hash通过。
- 真实板型未知、未烧录；FreeRTOS COE未换为Ascon固件，PS/PL/PYNQ尚未建立。
  ISE完整抢占上下文、全部ISA/异常/外设回归、板上测量仍未完成。清零不等于抗侧信道/物理提取。

最终补记：三套CPU原KAT全部PASS；新增安全检查软件132/132、MMIO123/123、ISE402/402，
ISE含下游hold跨完成和计算中reset重启。16B warm加密仿真周期：软件18348、MMIO完整往返664
（START→轮询完成100）、ISE2559；软件32B enc22817，dec16B18886/32B23388。
六个最终源码loadable binary与已测镜像逐字节一致，ISE反汇编有实际custom-0编码。
Vivado布线完成exit0，但100MHz WNS=-1.641ns、TNS=-607.794ns（1971失败端点），
LUT11683/FF15960/BRAM38.5/DSP4；DRC已报告95项Warning、无Error（部分规则达到报告上限），
存在PS7缺失、BRAM/复位与IO delay覆盖告警。故V06保留in_progress，上板门禁未通过。
已完成的安全修复与仿真可审查，时序收敛/实板功能不可标完成。

下一接收 B02/B03/V01/I08/Y01，owner TBD。历史与中间失败保留，不把综合或仿真冒充上板。


## 2026-10-15 — Ascon-AEAD128 软件版在自研 RV32IM CPU 上运行并测得软件性能

owner TBD；用户授权"调用已有 C 代码库完成软件版、测试保证处理器可用、测软件性能"。
未改任何现有 RTL/TB/KAT/脚本；新增固件与仿真平台，全部落在约定目录。

- 新增 src/firmware/ascon_rv32/：crt0.S、riscv.ld（ORIGIN=0x10000000 对齐复位 PC）、
  main.c（`#include` 锁定生产 ascon/ascon_c/aead/aead.c）、uart.c/h、libc_min.c、
  bin2vhex.py、build.sh。工具链 riscv-none-elf-gcc 15.2.0，
  `-march=rv32im_zicsr -mabi=ilp32 -O2 -ffreestanding -nostdlib -lgcc`；
  64 位软件基线因此需要 libgcc(__udivdi3/__lshrdi3 等)。镜像 code=38852 B、data=0、bss=0。
- 新增 sim/ascon/axi_slave_bram.v（AXI4 行为 BRAM：4 拍 WRAP 读 + 单拍写 + $readmemh）
  与 tb_ascon_sw.v（soc_top @50MHz + BRAM + UART monitor 解码 txd、检测 DONE/FAIL 标记）。
  入口 sim/ascon/run_ascon_sw.sh 一次完成 交叉编译→iverilog 编译→vvp 运行。
- 实测（Icarus 14.0 devel / vvp，退出码 0）：6 组官方 KAT（empty/1B/16B/16B+AD/17B/32B）
  加解密全 PASS，tag 篡改拒绝 PASS；CPU RTL(soc_top) 确实执行 ISE 无关的纯软件 Ascon。
- 软件性能（warm，模拟实测，非上板）：enc 16B=16840 cyc(1052.5 cpb)、enc 32B=21018(656.8)、
  dec 16B=17226(1076.6)、dec 32B=21461(670.7)；CPI≈3.9~4.0。mcycle 用 CSR 0xB00/0xB80
  high-low-high 读取；指令数用 cpi_cnt MMIO(0x60000000/04)。UART@115200 主导 cycle 量
  （每字节 4340 clk），故加密/解密各运行两遍取第二遍作为 warm 测量。
- 未验证/未测：上板(B02/B03)、Vivado 综合/实现/PPA、CPU ISE、完整 1,089 KAT 的目标运行
  （仅 host 全量 + 目标 6 组代表向量 + 篡改）。cycle 为仿真实测，不是 board 实测；未改任何 RTL。

C02 目标编译/运行与 C04 CPU 级软件 benchmark 已在仿真层达成；C03 目标 KAT 为 6 组代表向量
（全量仍在 host）。板级与 ISE 仍依赖 B02/B03/V01 后续接收。

## 2026-10-15 — Ascon MMIO 加速器接入 CPU（第一次硬件优化）

owner TBD；用户授权"结合 IO 接口代码把已写好的硬件接入、做第一次优化并测试"。
复用队友 IO/ 的 ascon_mmio.v（寄存器文件+FSM+缓冲，基址 0x30000000）与已 KAT 验证的
crypto_aead.v，新写 ascon_aead_core.v（32-bit 流式接口 → 128-bit 并行 crypto_aead 的适配器）。
改了 bus_interconnect.v（新增 ascon MMIO 译码 + read_sel_q 扩 6 位）与 soc_top.v（实例化
ascon_mmio、ireq_external 并入 ascon_irq），均为 README 记录的增量接线；未动 crypto_aead.v。

- 新增 src/rtl/ascon/ascon_mmio.v（队友 IO 原件字节一致复制）、ascon_aead_core.v
  （streaming 适配器，≤16B AD/msg，超长立即 done+success=0 拒绝）。
- 新增 src/firmware/ascon_hw_rv32/（MMIO 驱动固件，code=3936 B）与 sim/ascon/run_ascon_hw.sh。
- 关键 bug：crypto_aead 的 mode=0 加密/1 解密，而 ascon_aead_core 的 encrypt=1 加密/0 解密，
  初版直连导致所有加密请求按解密执行（空消息 tag 恰好仍对，非空全错）。修 .mode(!encrypt_r)。
- 实测（Icarus 14.0/vvp，exit 0）：4 组官方 KAT(empty/1B/16B/16B+AD) 加解密 PASS、
  解密往返 PASS、tag 篡改拒绝 PASS、17B 超长拒绝 PASS——CPU 通过 MMIO 驱动硬件 Ascon 正确。
- 性能（warm，仿真实测，非上板）：16B 加密 纯 crypto 延迟 99 cycles、完整 MMIO 往返 544 cycles；
  对比纯软件 16840 cycles → crypto 核心 ~170×、端到端(含寄存器读写+轮询) ~31×。这是 ISE 前
  的第一级硬件加速，MMIO 开销(寄存器写+轮询+读回)是下一步 ISE 要压缩的部分。
- 未验证/未测：上板、Vivado 综合/PPA、>16 字节消息、真正的 CPU ISE(I02~I07)。未改 crypto_aead.v。

## 2026-10-15 — Ascon 置换 custom instruction (ISE) 完成（最后的优化）

owner TBD；用户授权"继续完成 ISE 优化并测试，这是最后的优化"。在 RV32IM 软核里加入
Ascon 置换 custom instruction（custom-0 opcode 0x0B），复用已 KAT 验证的 p12/p8 模块，
CPU 用 inline asm 跑置换、其余 AEAD 逻辑仍用 C。改了 defines.v / id_stage.v / ex_stage.v
（新增 opcode/func_sel、译码、执行与多周期 stall，仿 divider 的 ex_stall_req 机制），
未动 crypto_aead.v/p12/p8。

- 新增 src/rtl/ascon/ascon_ise.v：CPU 内 320-bit 状态寄存器 + p12/p8 握手。
  4 条指令（.insn r 0x0B, funct3, funct7=0, rd, rs1, rs2）：
  `ascon.w`(f3=0, rs1=data, rs2=word idx) 写状态字；`ascon.rd`(f3=1, rs1=idx, rd=dest) 读状态字；
  `ascon.p12`(f3=2)、`ascon.p8`(f3=3) 跑置换（多周期，perm_start 电平 + ex_stall_req=~perm_done）。
  状态字 0..9 对应 s.x[0..4] 的 32-bit 小端切片。
- 新增 src/firmware/ascon_ise_rv32/（inline asm + 完整 AEAD，code=6216 B）与 run_ascon_ise.sh。
- 关键坑：GAS `.insn r` 格式是 `opcode,funct3,funct7,rd,rs1,rs2`（funct7 在 rd 之前），
  不是 `opcode,funct3,rd,rs1,rs2`；写错会报 "bad value for funct7 field"。
- 实测（Icarus/vvp exit 0）：4 组官方 KAT(empty/1B/16B/16B+AD) 加解密 PASS、解密往返 PASS、
  tag 篡改拒绝 PASS。反汇编确认 142 条 opcode 0x0B 的 custom 指令，非静默 fallback。
- 性能（warm，仿真实测）：16B 加密 **1880 cycles**（vs 纯软件 16840 → ~9.0×，~117.5 cpb）。
  剩余开销来自状态字 load/store（每置换 20 条）与 LOADBYTES/STOREBYTES 字节搬运（未加速）。
- 未验证/未测：随机/边界/复位/连续请求的定向单元测试（I04 仅跑了 KAT 定向）；baseline 回归
  重跑（I05 只跑了 ISE 回归，未重跑软件/MMIO 全回归）；ISE-disabled 模式、中断/异常/flush
  与 ISE 交互；Vivado 综合/PPA（I08，需上板前补）。这些是 I04/I05 验收的剩余项，未标完全达标。

三级加速对比（16B 加密，均为 warm 仿真实测）：纯软件 16840 → MMIO 全卸载 544(~31×) →
ISE 置换 1880(~9×)。ISE 是 custom instruction 路径（CPU 编排、置换硬件化），MMIO 是全卸载
协处理器路径；两者互补。ISE 的编码/semantics/stall/inline-asm 落位；I03/I06/I07 已达标，
I01/I02/I04/I05 主体完成、上述未测项待补。

## 2026-10-10 — Ascon 加解密合并为统一 crypto_aead 模块

owner TBD；用户授权新建独立文件，未改现有 RTL/TB/脚本/KAT。将原独立
crypto_aead_encrypt / crypto_aead_decrypt 合并为单一 crypto_aead 模块，
用 mode(0=encrypt/1=decrypt) 选方向、共用一条状态机。关键洞察：Ascon 加
解密吸收的是同一份"明文 pad 版本"——加密直接喂输入明文，解密由 s^c 恢复
明文后吸收，故尾块 mask+0x01 逻辑可完全统一，输出恒为 s^data_in。

- 新增 src/rtl/ascon/crypto_aead.v：统一接口 clk/rst_n/start/mode/data_in/
  ad/npub/k/adlen/datalen/tag_in → data_out/tag/correct/done/busy/error。
  encrypt 输出密文+tag；decrypt 输出明文，仅 tag_in 匹配才置 correct 发布。
  17..31 长度两方向均 error 拒绝，decrypt 另保持 correct=0。
- 新增 sim/ascon/tb_crypto_aead.v：同一冻结向量同时测加解密，含逐拍
  data_out=0/correct=0 隐藏检查、tag 篡改拒绝、长度拒绝、连续调用。
- 新增 sim/ascon/prepare_crypto_vectors.py：无需 C 编译器（WSL 不可用），
  直接从锁定官方 KAT 取 289 组(PT/AD 0..16)生成 784-bit aead.mem，布局与
  既有 aead.mem 一致。
- 实测 iverilog 编译 exit0、vvp 运行 errors=0：加密 289、解密 289、篡改
  拒绝 289、长度拒绝 1470(735×2) 全 PASS；latency 空消息 34 cyc、16B 58~70
  cyc。全源集(新旧模块共存)编译 exit0、无重复 module。
- 未动 ascon_aead_2.v 及原 encrypt/decrypt，旧接口回归不受影响。合并模块
  尚未接入 CPU/ISE；Vivado/PPA/hardware cycles 仍 not_measured。

随后按用户方案 B，把 ascon_aead_2.v 的 crypto_aead_encrypt / crypto_aead_decrypt
改为实例化 crypto_aead 的薄 wrapper：端口名/方向/宽度/顺序不变，两条重复
状态机移除，底层逻辑单一来源（get_bytes 保留）。资源上，SoC 只实例化一个
crypto_aead 即可加解密复用一份，wrapper 为纯连线、综合可优化。

- 回归复验（wrapper 后）：队友 peer TB ALL PASS；加密 300 组+735 长度、解密
  310 有效+2,579 篡改+735 长度均 errors=0，数字与原 V05 一致；全源集编译
  exit0、12 模块无重复。tb_rtl_aead/decrypt 用 peer(5)+官方KAT(289)+tails(6)
  共 300 组向量（build/local/ascon_crypto/aead_full.mem）；WSL 不可用，故 peer
  ct/tag 取队友 TB 字面量、matrix 取官方 KAT 自带 expected，不重算。

下一接收：SoC 集成(I03/I05)时顶层直接实例化 crypto_aead（一个实例、mode
切换，加解密复用一份资源）；B02/B03/B04/V01 仍为在自研 CPU 运行 Ascon 前置。

## 2026-10-10 — V05/C03 功能分支提交前审查

owner TBD；用户授权在E:/amd_fpga_2026_integration将已验整合成果commit/push并创建
PR，base main；最终合并由用户确认。fetch确认main仍为0a425f9，整合分支正确。
本条记录提交前审查，不把尚未执行的push/PR写成完成；实际SHA与PR见Git历史及交付。
本轮仅更新发布审查文档/日志，RTL、TB、脚本及KAT均未改；已有PASS的源码哈希
重新核验。Encrypt所有现有实例均具名连接，无现有位置调用受追加error端口影响。
原工作区及外部备份只读核验，队友两份dirty结果不纳入；无CPU/Vivado/PYNQ改动。
提交消息feat(ascon): integrate RTL decryption and KAT validation；明确文件列表暂存，
不用git add .，不force、不推送main、不合并PR。V05/C03任务状态沿用前次实测边界。

## 2026-10-09 — V05/C03 最新main隔离整合与重新验证

owner TBD；重新fetch确认origin/main=0a425f9，独立worktree
E:/amd_fpga_2026_integration，分支feat/ascon-decrypt-kat-integration。
原E:/amd_fpga_2026保持7139a80/cleanup/remove-legacy-ascon-aead及全部28个未提交
文件。仓库外备份89文件7,636,392 bytes逐一SHA-256核验；包含队友原dirty结果。
未commit/push/创建PR/合并main；新分支不跟踪origin/main。

- 以remote为基础逐处修复，没有整文件覆盖旧本地RTL。保留队友初始化/AD、
  整块ciphertext吸收、尾块64-bit state masking/padding、P8/P12/finalization、
  full tag diff与计算tag输出；P8/P12和原队友TB逐字节未改。
- Decrypt原15端口名字/方向/宽度/顺序保持不变，无mlen/error/result新端口。
  done && correct读取接受请求的clen；认证前/失败m=0、correct=0。
  修reset/start未撤销旧认证/候选、完成后清候选；超长用correct=0拒绝。
  Encrypt追加error，所有现有具名调用兼容；整个AEAD加include guard。
- 原remote首请求busy时m/correct为X实测vvp exit1；原TBinclude+显式source编译
  exit6。首轮guard漏get_bytes编译exit2，失败全部保留，修源后重新完整回归。
- 新worktree新vector/新source：官方KAT289/289加密和解密，补充11/11；
  Encrypt311有效/控制调用、Decrypt310、篡改拒绝2,579、每方向超长拒绝735，
  全部0 FAIL；round264、P8/P12各28state比较PASS。接口具名/位置调用逐拍一致。
- 所有四个production.v编译exit0，10module无重复，全源加解密仿真exit0，
  原队友TB5组PASS。故障注入4/4，三个功能故障vvp exit1、坏向量runner exit1。
  参考全1,089 KAT gate12,936/0；软件四backend本worktree重跑28,661/0。
- 新证据rtl_integration_regression.*、rtl_integration_harness.json、
  host_integration_validation.*，记录0a425f9+实际dirty source/TB/scripts hashes，
  不是旧7139a80结果复用。工具版本/命令/退出码及保护说明见最新解密整合报告。
- 最终integration_review.json核验当前源码/验证源哈希、原28dirty和89备份未变，
  远程main仍0a425f9、diff --check exit0；暂存/提交/推送/PR为0。

V05整合子项done；C03 target仍in_progress，I03/I04/I05不因独立AEAD提升验收。
当前可供用户审查后commit/push功能分支并申请PR。本轮无Ascon仿真功能阻塞；
多块RTL、CPU/板级、Vivado、cycles/PPA仍未验证或not_measured。
下一接收B02/B04/V01/TBD→target KAT/mcycle→C04/I01/I02。下节保留先前本地历史。

## 2026-10-09 — V05/C03 standalone Ascon RTL 解密与生产全源集收口

owner TBD；基点7139a80，复用cleanup/remove-legacy-ascon-aead分支。
初始未提交rtl_regression.json/.log保留，新增rtl_decrypt_regression.*作为默认输出。
未commit/push/merge；CPU/Vivado/PYNQ/软件/锁定参考均未修改。

- 源码事实：crypto_aead_decrypt仍为空壳；35acd6a是C软件修复。
  本轮补齐RTL独立解密、完整tag认证与失败输出保护。encrypt新增error，
  加解密均拒绝物理总线不能承载的17..31-byte长度。
- before：permutation/encrypt/full-source compile PASS；runner因已删除legacy
  源路径exit1，保存rtl_decrypt_before.*。原encrypt实测17-byte请求正常done，
  长度probe simulation exit1，rtl_length_before.json保留真实失败。
- Icarus/vvp12.0：round264基础state比较PASS；P8/P12各22基础+6控制比较PASS；
  四个production.v全root编译exit0，10个module无重复；全源加解密仿真exit0。
- 官方RTL KAT：PT/AD各0..16的全部289组加密/解密均PASS，0失败；11组peer/尾零
  补充输入亦PASS。独立decrypt使用锁定expected C||T，不以encrypt反向自证。
  其余800官方组超出接口未运行RTL；完整1,089组C/Python reference gate
  12,936 PASS，软件四backend重跑28,661 PASS / 0 FAIL，均exit0。
- encrypt311有效调用；decrypt310有效调用、2,579篡改拒绝；加解密各735超长
  参数组合拒绝。每拍检查解密认证前m/mlen/result为0，失败当拍及之后仍为0。
  空/短/8与16边界/尾零、连续调用、busy-start忽略、reset中断/重新调用通过。
- RTL故障注入4/4：错误tag接受、错误明文、提前发布分别触发vvp exit1；
  损坏向量触发runner exit1。host harness 5/5通过。最终各入口exit0。
- 接口：rst_n同步低有效；start一拍；key/nonce/tag保持至done；显式length。
  decrypt新增c/tag/ad/clen/adlen与128-bit m/mlen/result/done/busy/error。
  完整契约、命令/版本/退出码/哈希与未测边界见
  docs/ascon_rtl_decrypt_validation.md、src/rtl/ascon/readme.md与results JSON/log。

看板：C01 done，C03 in_progress（target待验），新增V05 done；I03/I04真正ISE
保持todo。独立AEAD可以交付算法验证基础，但I05前置B02/V01和I02/I03仍未满足。
下一接收B02/B04/V01/TBD：CPU baseline与目标软件KAT/mcycle sanity，再C04/I01/I02。
阻塞：baseline/Vivado/固件依赖/板卡核验与CPU ISE未完成；当前Ascon仿真无功能阻塞。
Vivado综合/实现、CPU/板上、硬件cycles/speedup/PPA仍not_measured，多块RTL不支持。

## 2026-10-07 — 独立 RTL regression 提交收口

owner TBD；用户授权在 feat/ascon-kat-validation 创建
`test(ascon): add independent RTL regression`，不 push/merge。
审计原待提交 11 文件合计 190,057 bytes，最大 85,773 bytes；无重复大文件、缓存、
编译物或硬编码运行路径。结果中的绝对路径仅为实际命令证据，正式入口动态定位。
生产源/验证源与结果 hash 匹配，锁定来源/许可证完整；ignored pycache/vvp/so 不纳入。
暂存检查发现 Windows 报告换行问题，已修 runner 源输出为 LF 并重新生成/复验，
生产 RTL 不变。isolated PASS、旧接口 exit 2/full source exit 6 的 FAIL 原样保留，
整体 gate 未关闭；下一接收 RTL owner/TBD。

## 2026-10-07 — 同步最新 RTL 与独立回归追加

- owner TBD；用户授权 checkpoint/rebase。原 cba792c checkpoint 已无冲突 rebase 到
  origin/main `13d954f0755c2ec09290443e341cd5fb910fbf21`，新 checkpoint 为
  `a1d19dd7cd26da7d036d9b5612fb27f3cbf25680`。未 push/merge main；本地 main 未移动。
- 独立 C/Python 完整 KAT gate 重跑 12,936 PASS，队友五组 expected CT/tag 5/5
  与锁定 Final reference 一致；原始向量出处未记录，不能从 TB PASS 推断来源。
- Icarus/vvp 12.0：round/P8/P12 PASS，308 冻结基础用例及连续调用/reset/restart；
  新 isolated encryption 60 固定输入+9 控制请求 PASS（69 次 CT/tag 比较）。
  覆盖 mlen/adlen={0,1,7,8,9,15,16} 矩阵与尾零，没有伪造17-byte运行。
- 旧 AEAD isolated compile FAIL exit 2（reset/rst_n）；全部生产 .v compile FAIL
  exit 6（三个重复 module）。runner 整体 exit 1；isolated PASS 不等于可集成。
- decrypt=not_implemented。新 m/ad 各128 bits，目前能力上限各16 bytes。
  key 未锁存，须稳定到完成；busy-start 策略不一致、无效 c 位/empty 旧数据等
  观察与建议见 docs/ascon_rtl_regression_audit.md。

证据 `data/ascon/results/rtl_regression.json/.log`；新增入口及自己的 TB 在 sim/ascon。
生产 RTL 与 origin/main 相同，队友 TB 未修改。新回归/日志保留未提交，除授权
checkpoint 无新增 commit。看板仍不改；交接 RTL owner/TBD 修重复/接口后 I04 复验。
未做 Vivado/CPU/板级/PUF/PYNQ；硬件 cycles/PPA not_measured。

## 2026-10-07 — C01/C03 Final 标准与 host KAT 证据追加

本段为当前证据；下方 2026-09-21 表格保留历史快照。owner TBD。
初始 clean，main 从 ab458e5 fast-forward 到
`8c8634f80f55cff50ae1ffcaf6fb79d67e5a7a93`，含当天 `01 << (8*n)` padding 恢复。
创建 `feat/ascon-kat-validation`，本轮未 commit/push。

- C01：Final PDF、C/Python 固定 commit、许可与 18 文件哈希、独立完整上游 KAT
  已锁定；对照见 `docs/ascon_standard_baseline.md`。建议 done，待用户确认；看板未改。
- C02：现有 host C/Python AEAD 与 Final KAT 一致，WSL GCC 13.3 编译 C 通过。
  仍 in_progress：目标固件未编译/运行；C bad-tag 返回 -1 但留下明文和 mlen，
  failure contract 实测 exit 1。测试 adapter 丢弃输出不等于生产 API 已修复。
- C03：1,089 完整上游 KAT、64 补充 AEAD、308 permutation golden、16 短 tag 长度。
  四 backend 共 28,661 PASS / 0 FAIL，exit 0；harness 5 tests PASS。
  框架/host 子项完成，整体建议 in_progress，待 C02 前置与失败输出契约收口。
- reference gate 12,936 PASS；冻结数据重生成 byte-identical。真实 FAIL 与一次
  runner 共享库冲突原日志保存 `data/ascon/results/`；冲突已隔离构建并复验通过。
- 当前 RTL 已含完整 round、P8/P12 和 AEAD 草稿，09-21 的“只有 ror”是历史状态。
  本轮只记录长度推断/start 未接/输出截断/packed 数据推进/decrypt 空壳等问题，
  没有修改或仿真现有软件/RTL/CPU/Vivado；不能据此提升 Ixx 完成度。

证据：`data/ascon/provenance.json`、`results/host_validation.*`、
`results/failure_contract.*`、`results/audit_snapshot.json`；入口 `sim/ascon/readme.md`。
新增接口仅为独立 golden JSON/656-bit memory/CLI，生产接口未改。
硬件 cycles/PPA/RTL 功能 not_measured；接收 C02/C03/TBD，再 C04→I01/I02。

截至：2026-09-21，含 ZIP 恢复及 repository foundation 收口。owner 全 TBD；原 rename/生成元数据清理已在 fe66fd8；恢复资产已在 fc9147785cc4490b1673a0b86e16f337f256f122 本地提交。本文件随独立 foundation 文档提交保存；本轮未 push、未 merge main。初始审计基点仍为 e35d42f，不能将其误作当前开发分支 HEAD。

| 任务 / 范围 | 实际结果 | 证据 | 状态 / 局限 |
|---|---|---|---|
| B01 / D00 | 初始仓库审计、协作骨架已完成；现补充归档审计与结论更正 | docs/repository_audit.md、docs/cicc1000023_recovery_audit.md | done；审计不是功能验收 |
| B02 | Rebuild and verify recovered XC7Z020 CICC baseline；原始 XC7Z020 XPR、31 RTL/header、3 XCI、XDC/COE 恢复；活动文件引用闭合；Kintex 保留 | board/vivado_zynq7000_xc7z020_baseline；manifest 双哈希 | in_progress；未运行 Vivado/IP 再生成/综合/实现 |
| B03 | 原始 target xc7z020clg400-1、PLL 50→100 MHz、128 KiB BRAM 配置已知 | 原 XPR/XCI/XDC 与恢复审计 | blocked；target part 已确认，physical board model pending；revision/引脚适用性/PYNQ image 未核验 |
| B04 | CoreMark RV32/RV64、FreeRTOS 应用、RISC-V tests 源与构建输入共 465 文件恢复 | src/firmware/cicc1000023；原名还原脚本 | blocked；准确 kernel/bootloader 源不在所供 ZIP；未编译/加载 |
| V01 | 原始 RTL top elaboration、tb_bypass 7 项与 tb_regfile 15 项通过 | build/metadata/cicc1000023_recovery_verification.json | in_progress；ISA/Cache/AXI/中断/counter 完整回归待做 |
| 历史硬件输出 | ZIP 有 bitstream、综合/实现成功日志；100 MHz 下 WNS 0.056 ns；placed LUT 4806 / FF 3129 / BRAM 38.5 / DSP 4 | 精选 6 个报告/日志与 archive_inventory | historical_archive_evidence；有未设 IO delay，非本轮重建或实测 |
| RTL 比较 | 31 共有文件：14 字节同、17 仅换行差异；repo-only 两个 Ascon helper | docs/cicc1000023_rtl_diff.md | 没有选择哪个更新；当前 src/rtl 未改 |
| C02 | 既有 Ascon C/Python 保留 | ascon/ | in_progress；未移植或运行最终标准 KAT |
| C01/C03/C04 | 无锁定的最终标准 KAT 及板上 benchmark | 尚无相关结果 | todo；Ascon cycles/code size 均 not_measured |
| Ixx | Ascon RTL 仍只有 ror/load_bytes/store_bytes | src/rtl/ascon/ | I01-I08 todo |
| D01 / Yxx / Sxx | 当前/目标架构与待定接口已记录；PS/PYNQ/Skill 实现未开始 | docs/architecture.md、docs/interfaces.md | D01 in_progress，其余按任务表 |
| Pxx | 未开展 PUF/启动认证 | tasks/task_board.md | gated |

## 验证边界与当前阻塞

579 个恢复资产的 SHA-256 核验通过；两套 XPR/XDC、当前 RTL 与 Ascon 保持原字节。Kintex 经 git mv 归并，旧生成元数据两项已清理。文件名还原脚本成功在 ignored build/local 生成隔离工作副本；不执行原包中的安装或清理脚本。

没有运行 Vivado/Vitis、固件编译、完整 ISA、JasperGold、软件 KAT、板上测试或 PYNQ。两个模块仿真与历史 Vivado 报告分开记录。PATH 未发现相关构建工具不等于全盘无安装。

下一步：B02 重建真实 baseline；B03 核板；B04 取得准确 kernel/bootloader 来源、核验入口并适配旧测试层次；C01 锁定标准 reference/KAT。Git HEAD 缺资料用 not_in_current_repo；ZIP 已提供的资料用 available_in_archive / recovered_uncommitted，不再写成 not_available。

首次审计曾复现 top_pl_bram 缺三个 IP module 的 Icarus 报错；该历史结果保留在 repository_audit。如今 XCI 已恢复，但 XCI 不是 Icarus 可直接编译的 Verilog 模型，仍需 Vivado 生成对应产物。

foundation 收口的 579 资产分类：A source 485、B build/config input 85、C test/reference data 3、D historical evidence 6。最终 board 仅两个工程，未改 RTL、未跑 Ascon。提交准备与 Git 检查见 [收口检查](../docs/repository_foundation_closeout.md)。

## 2026-10-07 — C02 production C 认证失败输出收口

owner TBD；基线 `origin/feat/ascon-kat-validation` 的
`c34728558469f0d4e4068730801dea59e0ca2100`；分支
`fix/ascon-c-auth-failure`。本节不修改任务看板。

| 项 | 本轮真实结果 | 状态建议 |
|---|---|---|
| 原问题 | bad tag 返回 -1，但 mlen=17、buffer=原明文；原门禁 1 PASS/1 FAIL/exit 1 | 失败证据保留 |
| 扩展 raw 门禁修复前 | 15,039 PASS / 8,926 FAIL / exit 1；包括短输入保留 stale mlen | 失败证据保留 |
| production C 最小修复 | 仅 decrypt：失败清零已知候选区域并设 mlen=0；短输入仅设 mlen=0；完整 tag XOR/OR 比较保留 | host 子项关闭 |
| 修复后 raw 门禁 | 23,965 PASS / 0 FAIL / exit 0；直接读完整 buffer，检查两侧 canary | C03 软件失败输出子项 PASS |
| 四 backend host validation | 修改前后均 28,661 PASS / 0 FAIL / exit 0 | Final 固定 KAT 无回归 |
| harness/golden | 5 tests PASS / exit 0 | 错输出/假接受/hash 故障确实非零退出 |
| 加密不变 | 1,153 固定 AEAD 输入输出拼接 SHA256 修改前后一致 | encryption 无改动 |
| C01 | 锁定来源、标准、许可、KAT/hash 与软件证据已可用 | 可评审 done |
| C02 | host API 安全契约已收口；target build/port 与 B04 仍未验 | 保持 in_progress，不能 done |
| C03 | 软件验证全部 PASS；target/整体前置未验收 | 不自行 done |

实际命令、编译器/源文件哈希、前后 raw 示例、原始日志与限制见
[C API 与修复记录](../ascon/ascon_c/aead/readme.md) 和 `data/ascon/results/`。
锁定 reference、固定 expected、Python、生产 RTL/CPU/Vivado 均未修改。
目标固件、上板、cycles/PPA、buffer overlap/异常指针/超大长度与全面 timing proof
未验证或 not_measured。下一接收：C02 target/B04 → C03 target KAT → C04 real
mcycle，owner TBD；RTL integration/decrypt blocker 仍由 RTL owner 处理。


## 2026-10-20 — 100 MHz 时序工作台站点（仓库外）+ 两处证据性发现

owner TBD。用户要求：不做 RTL 优化（由用户自己动手），改为把 CPU 逐块拆解、给出当前实测标定、
把已做过的时序优化步骤连同判定放到一个可复核的网站上。站点落在仓库外
`../html/`（`C:/wenjian/game/FPGA2026/ours/html/`），**未修改 src/rtl、未改 board 工程/XDC、
未 commit**。被用户确认的口径：以 control（HEAD 3c6f134，+0.007）为“当前”，
14164 条路径 CSV 标注为 −0.136 探针快照（偏悲观 0.143 ns）。

- 新增（仓库外）：8 个静态页面 + `assets/{style.css,data_static.js,data_probe.js,app.js}`
  + `trace/`（定向程序、TB、轨迹 CSV/JSON）+ `probe/`（只读探针脚本与输出）+ `check_pages.js`。
- 新增实测（只读）：`probe/per_module_paths_detail.tcl` 打开最终 routed DCP
  （`bce_timing_control/.../top_pl_bram_postroute_physopt.dcp`），对 26 个模块与 15 个路径族
  各取最差一条，输出 slack / DATAPATH_DELAY / DATAPATH_LOGIC_DELAY / DATAPATH_NET_DELAY /
  LOGIC_LEVELS / 单元构成 → `probe/module_paths_detail.csv`。未 launch run、未改工程。
- 新增实测（仿真）：`trace/tb_trace.v` 在 soc_top @50 MHz 上跑 41 条定向指令，
  每拍采样 41 个信号（pc/有效位/stall/flush/两个 cache 状态机/多周期握手/isE）
  → `trace/trace.csv`（231 拍）。据此把逐拍流水做成可点选的 10 个场景。
- 站点数据交叉核对：模块级族条数与 `paths_lt_2p0.csv` 重算一致（id_ex 内部 315 / →dcache 289 /
  →if_id 165 / →icache 148 / pc→ise 647 / dcache→mmio 8858）。
- 发现 1（文档错误，已写入站点）：`docs/cpu_timing_architecture_plan.md` §5.0 表把
  “−0.643 / 649” 标成 B+E-v2；实测那是 `rtl_E2` 单独结果，B+E（rtl_patched）是
  −0.723 / TNS −93.442 / 502 端点。不影响“B/E 均回滚”的结论。
- 发现 2（功能/计数口径，未修）：多周期指令（mul/div）执行期间 `id_ex_inst_valid = 0`
  （trace cycle 61–63、64–97），原因是此前 icache miss 的 `flush[2]` 清零 `inst_valid`，
  而 `id_ex` 的 flush 分支不清 `pc_o/rs1_o/rs2_o`，随后 stall 分支把 0 保持。
  `cpi_cnt` 与 `probe_inst_valid` 依赖它 → 指令计数偏小、CPI 偏大，影响既有 cpb 数字口径。
  未改 RTL，仅记录；建议单独立项核（接收：RTL owner / TBD）。
- 验证：`node html/check_pages.js` 8 页脚本全部无异常；Chrome headless 渲染 8 页人工核对布局；
  轨迹与探针均在本机重跑通过（Vivado 2025.2 / Icarus 14.0 devel）。
- 未验证 / not_measured：板级 XDC（IO delay/PS7）后的时序；80 MHz 改频后的实现结果；
  上板 cycles；每类 stall 占比；p12 单独实测周期（现为按 p8 折算，站点已标注）。
- 下一接收：用户按站点 `next.html` 自选路线（A/D/C/F/R）；站点不改 RTL，只提供标定与判定依据。

## 2026-10-21 — 后端战役：控制锥复制 + 依赖驱动 floorplan + 疏松布局（夜间 33 臂）

owner TBD；起点网表 `acb_remap/top_pl_bram_opt.dcp`（HEAD `3c6f134` 生产策略 +0.007 的
post-opt 快照）。**未修改 `src/rtl`、`board/`、baseline XDC 与工程；未 commit**
（`git status` 仅新增 `build/backend_opt_20261021/`、`build/reports/backend_opt_20261021/`
与 `docs/backend_placement_campaign.md`）。用户要求：复制同义寄存器本地化控制锥、
按依赖强度摆模块、布局尽量疏松、从后端而非 RTL 找余量。

| 项 | 本轮真实结果 | 状态 |
|---|---|---|
| 实验装置 | `run_variant.tcl` + `run_wave.sh`（每臂独占目录）+ `floorplan.py` + `dep_analysis.py` + `summarize.py` + `fanout_compare.py` + `probe_*.tcl` | 可用，可复现 |
| 臂数 | 35（8 个波次，含 2 个重复对照臂） | 覆盖复制/floorplan/疏松/放置与布线 cost model |
| 最好一档 | `pl_ndh_crit200_ntr`：WNS **+0.138** / TNS 0 / 失败 0 / WHS **+0.017** / Slice LUT 11690 / Slice Reg 16042（生产参考 11752/16040）/ 0 布线错误 | 重复臂逐位相同 |
| 生产指令锚点 | `prod_place`（opt Explore/place Explore/phys_opt Explore/prout ExploreWithHoldFix）= **+0.016**，与既有 +0.007/+0.016 同级 | 说明本 harness 与生产可比 |
| 全局复制 | `rep128/256/512` = −0.074 / −0.188 / −0.295；`rep256_nofrn` 与 `ctl` **逐位相同**；`rep256_noeq` = −0.398 | 复制确实发生（9650/3989/1280/661/457 pin 网络全部跌破 256 pin），但**不推动时序墙** |
| 定向复制 | 只复制最差 N 条路径的 CE 锥（Slice Reg 仅 +9）：N=20/60/120/200 → +0.030/+0.068/−0.039/+0.074（加 NoTimingRelaxation 后 −0.154/+0.117/+0.138/+0.003） | 非单调，量级与一次布局重抽同阶 |
| floorplan | fp2 +0.007、fp3 +0.017、fpc −0.065、fp3_prod −0.061、fp3_ndh −0.228；pblock 确实被遵守（pb_cpu 仅 275/10404 单元被 phys_opt 溢出到区间外） | 生效但无稳定收益 |
| 疏松 | `place_design` 无 `-place_density`；pblock `PLACE_DENSITY` 在 2025.2 不存在（`fp3_loose` 因此失效，脚本已改 catch 保护）；`AltSpreadLogic_medium/low` = +0.002 / −0.027 | 器件 22% 占用本来就松，人为散开无益 |
| 时序墙分布 | `ctl` <0.2=179 / <0.3=319；`prod_place` 127/278；**冠军 7/44** | 唯一真实收益：接近临界端点数量下降 10 倍 |
| 最差路径构成 | `ctl` dp 9.979 / logic 2.882 / net 7.097 / lv 11 → 冠军 9.502 / 3.193 / 6.309 / lv 11 | 累计走线 −0.79 ns，逻辑 +0.31 ns |
| 未验证 / not_measured | 功能回归（`src/rtl` 未改，变换为 Vivado 等价实现变换，但未跑 KAT）；板级 XDC + PS7 在场后的时序；bitstream 与上板；80/90 MHz 改频后的实现 | 不宣称 |

结论：**纯后端手段无法把这道墙抬到 +1.0 ns**。35 个臂的 WNS 区间 −0.514 ~ +0.138，
最好一档已达 0 失败端点、0 布线错误，但只有周期的 1.4%；真正改善的是脆弱性
（<0.2 ns 端点 127→7）。要余量仍是降频（90 MHz 折算 ≈ +1.11 ns）或 RTL 深度削减。
完整表格、机制证据与复现命令见
[backend_placement_campaign.md](../docs/backend_placement_campaign.md)。
下一接收：决定是否把 `pl_ndh_crit200_ntr` 做成 baseline 工程的独立 impl 入口并跑全套回归，
或按 80/90 MHz 收口；owner TBD。


## 2026-10-21 — 布局布线可视化（真实 SITE 坐标 + 逐跳延迟）

owner TBD。用户要求：在站点里加一张能看出"当前布局布线是什么情况"的图，每个模块有对应的线，
并把每一条最坏路径画出来。站点仍在仓库外 `../html/`，**未改 src/rtl、未改工程/XDC、未 commit**。

- 新增只读探针 `html/probe/floorplan_probe.tcl`：打开 `bce_timing_control/.../top_pl_bram_postroute_physopt.dcp`，
  输出 ① 器件栅格（max_x=113 / max_y=149，BRAM 列 X0–X5、DSP 列 X0–X4）
  ② 22 个模块的 placed bbox + 质心 + 模块内 BRAM/DSP 数（`fp_modules.csv`）
  ③ 12 条最差路径 + 15 个路径族的 `full_clock_expanded` 报告（`fp_paths/*.rpt`）。
  新增 `parse_floorplan.py` 把报告里的 Location 列解析成 (x, y, 本跳 ns, 累计 ns) 的折线 → `assets/data_layout.js`。
- 新增页面 `html/layout.html`：楼层图（SVG）+ 单路径/模块分布/模块互联三种模式 + 跳数表。
- 实测发现（新）：
  1. dcache 的 8 个数据 BRAM 在 **RAMB18_X4Y0…X5Y5**（芯片最左 BRAM 列），而 dcache 逻辑在 X35–X106；
     最差路径 #1/#2/#3 的终点就是 `RAMB18_X5Y4`，最后一跳从 `SLICE_X98Y16` 横跨 93 列。
  2. `dcache.bus_addr_r → ascon_mmio MSG_BUF` 那族有一跳 **跨 90 格 / 3.09 ns**（Y22 → Y104）：
     MMIO 缓冲被放在芯片下半部，与数据通路相距 80+ 行。这条解释了 8858 条路径为何都在 7.7 ns 走线上。
  3. 最差 #1 的 11 跳全在 X64–X98 / Y4–Y20 的局部区域内绕（曼哈顿 166 格），
     说明"先在局部绕一圈、最后再横跨整块芯片"是本设计的典型形状。
- 修正一处探针自身缺陷：`LOC` 正则原先写成 `^[A-Z]+_X…`，会把 `RAMB18_X4Y2`/`DSP48_X1Y3` 全部漏掉，
  导致模块 bbox 不含 BRAM（dcache 被算成 X35..106 而不是 X4..106）。已改为 `[A-Z]+[0-9]*`。
- 验证：`node html/check_pages.js` 9 页全通过；Chrome headless 渲染 9 页人工核对；
  三种模式各截图核对（`preview_layout*.png`）。
- 未验证：路径折线是按 report_timing 的元素顺序连线，**不是布线资源的逐段走线**（Vivado 文本报告不含 PIP 级路径）；
  因此图中线段表示"逻辑单元之间的顺序与距离"，真实走线拓扑仍是 not_measured。


### 追加（同日）— 布局图支持图层开关与自动聚焦

用户要求：图不能只是"全部画出来"，要能取消一部分，让剩下的部分居中放大显示。已改为三栏：
左侧模块图层（22 个勾选框 + 只看 CPU / 只看 Ascon / 全关 预设）、中间楼层图（滚轮缩放、拖动平移、
点模块框压到该 bbox、「全屏看图」收起两侧栏）、右侧路径信息与逐跳表。
`fitView()` 按「可见模块 bbox ∪ 可见路径 bbox」计算 viewBox 并保持器件比例，所以取消图层后视图自动
缩放到剩余部分；路径图层支持多选叠加（非当前路径画虚线）。URL 参数 `?p=` / `?preset=` / `?hide=`
可复现任意视图。文件：`../html/layout.html`（未改 RTL/工程，未 commit）。

### 2026-10-21 补测 — WHS 侧 5 个 post-route 修复臂（全部空操作）

从冠军 `pl_ndh_crit200_ntr_routed.dcp` 起，只做布线后修复、不重布局（`run_holdfix.tcl`）：

| 臂 | 动作 | WNS | WHS | Δ |
|---|---|---|---|---|
| hf_explore | `-directive ExploreWithHoldFix` | +0.138 | +0.017 | 0.000 / 0.000 |
| hf_aggr | `-directive ExploreWithAggressiveHoldFix` | +0.138 | +0.017 | 0.000 / 0.000 |
| hf_aggr_both | 上 + `-aggressive_hold_fix` | +0.138 | +0.017 | 0.000 / 0.000 |
| hf_clock | `-clock_opt` | +0.138 | +0.017 | 0.000 / 0.000 |
| hf_clock_hold | `-clock_opt` + `-aggressive_hold_fix` | +0.138 | +0.017 | 0.000 / 0.000 |

结论：WHS 为正时 hold 修复指令无事可做（help 只对 "hold violators" 生效），LUT 数也不变。
hold 薄的结构原因是 Ascon 核内 0~1 级逻辑的相邻寄存器对（数据 0.30~0.44 ns，最差
`p12_inst/s_out_reg[315] → u_crypto_aead/s4_reg[59]`，靠 +0.271 ns 时钟偏斜撑到 +0.017）。
35 臂统计 `corr(WNS,WHS) = −0.516`，WHS ≥ +0.05 的 7 个臂 WNS 全部 ≤ −0.102（setup 违例），
官方生产也只有 +0.023/+0.031 → 建议把 hold 门限改为 "hold 失败端点 = 0 且 WHS > 0"。
证据：`build/reports/backend_opt_20261021/hf_*/`，说明见 `docs/backend_placement_campaign.md` §4.7。


### 追加（同日）— 新 run 的自动接入管线（等 campaign 结束后生效）

用户要求"等完成后接入数据"。已建成并**用同一网表自测过**（Δ 全为 ±0）：
`intake_run.sh <dcp> <tag>` = 只读探针（探针已参数化，可对任意 routed DCP 取模块 bbox + 27 条路径的逐跳 SITE）
→ `parse_floorplan.py --tag` → `assets/data_layout_<tag>.js` → `update_manifest.py`（从 campaign 的 `RESULT` 行取 WNS）。
`layout.html` 新增「对比基准」下拉：base 画灰虚线、新布局画彩线，右侧给出 slack/data/logic/route/hops/
曼哈顿/峰值单跳的 Δ 表；`experiments.html` 增加「后端 campaign（自动接入）」表。
并发保护：`intake_run.sh` 检测到 `vivado.exe` 在跑即拒绝执行（`--force` 才跳过）。
已挂后台等待器 `watch_campaign.sh 6`：等 `vivado.exe` 全部退出 + 90 s 冷却后，自动接入
`build/local/backend_opt_20261021/` 下新建的 checkpoint（日志 `html/probe/watcher.log`），最多 6 个。
当前 campaign 仍在跑（`vivado.exe` PID 40068，最新 checkpoint 11:16），故站点数字仍为 10-20 21:37 的基线。

### 2026-10-21 补测 2 — 用 pblock 把 hold 关键寄存器对拉开（2 臂）

`floorplan_hold.py`：把 `u_crypto_aead/p12_inst`（1628 cells / 646 FF）从
`u_ascon_mmio` 切出去单独一块，其余沿用冠军指令（place ExtraNetDelay_high、
crep 200、route NoTimingRelaxation）。

| 臂 | WNS | WHS | 失败端点 | 结论 |
|---|---|---|---|---|
| `hfp_split_near` | **−0.110** | **+0.032** | 73 | hold +0.015，setup −0.248 → 净亏 |
| `hfp_split`（远） | 未完成 | — | — | placer 卡在 Phase 4.1.1.2 超 30 min，已终止 |

切分后最差 hold 路径从 `p12_inst/s_out → s4`（0.381 ns）换成
`p8_inst/s_reg_reg[109]`（0.389 ns）、`nonce_r_reg[47]`（0.375 ns）等 ——
WHS 由一整群 0~1 级逻辑的寄存器对决定，不是单点。**结论：WHS 是结构量，
不建议再花时间；把 hold 门限改为"失败端点 = 0 且 WHS > 0"。**


### 追加（同日）— campaign 结束，接入两版并与基线逐跳对比

等 `vivado.exe` 全部退出后，等待器自动接入 `hfp_split_near`（12:07），随后按 `results.tsv` 的最优行补接
`pl_ndh_crit200_ntr_dup`（12:1x）。站点现有 3 个数据集（base + 2 个 run），`experiments.html` 增加 campaign 表
（58 次运行 / 36 个有 RESULT）。

- 实测对比（同类路径按「起点寄存器 + 终点模块/引脚」匹配）：
  - `pl_ndh_crit200_ntr_dup` WNS +0.138：原 #1（`w_reg_waddr_o_reg → dcache DIADI`）从 +0.007 → **+0.538**，
    逻辑级数 10→8、route 8.01→7.73、曼哈顿 166→141；`multiplier → dcache` +0.088→+0.934（级数 19→17）；
    `pc → ex_mem/CE` +0.101→+0.916。唯一倒退是 `dcache.bus_addr_r → mmio/CE` +0.525→+0.345，
    原因是**时钟偏斜**从 −0.024 恶化到 −0.252（数据路径本身 9.152→9.103 是变好的）。
  - `hfp_split_near` WNS −0.110：`sel_ex_mem_rs2 → dcache DIADI` 逻辑级数 16→7（logic 3.24→1.32），
    但 route 6.17→8.30、沙盘曼哈顿 174→53 → 净 −0.29。**曼哈顿↓ ≠ route↓**：pblock `pb_hf_rest`
    把 239 个 hop 收进一块，距离短了但绕线/拥塞变重。
- 修复两处会产出假数据的问题：① `worstN` 名次不可跨网表对比 → 改身份匹配；② 带 PBlock 列的
  `report_timing` 使旧列解析整行失败 → 改 token 解析并记录 pblock。
- 未验证：这些数字仍是芯片级 STA（无板级 XDC/PS7）；campaign 里 22 次 EXIT=1 未接入；pblock 的拥塞结论是
  由 route vs 曼哈顿的背离推出的，未用 `report_design_analysis` 的拥塞指标交叉验证。

### 2026-10-21 12:30 · 时序工作台：campaign 数据全站刷新

- 对象：`C:\wenjian\game\FPGA2026\ours\html`（仓库外，纯静态）；未改 `src/rtl`、`board/`、XDC，未 commit。
- 新跑只读探针：`probe/per_module_paths_detail.tcl -tclargs <dcp> pl_ndh_crit200_ntr_dup`（最优版 +0.138），得到 21 个模块的进来/出去最差路径；与 control 版逐模块配对（`assets/data_probe2.js`）。
- 15 个路径族按**起点寄存器 + 终点模块/引脚**身份匹配（不是 worst1/2 名次），生成 `assets/data_families_cmp.js`：**14 族变好，1 族变差**。
- 关键归因：
  - 变好：`id_ex internal` +0.285、`waddr→dcache` +0.531（级数 10→8）、`mult→dcache` +0.846、`pc→ex_mem` +0.815。
  - 变差：`dcache bus_addr_r → ascon_mmio/CE` +0.525→+0.345。数据路径 9.152→9.103（更快 0.049），**clock skew −0.024→−0.252**（DCD −1.675→−2.146）；同时 `u_crypto_aead` 进来 slack 也正好 −0.180 → 同一时钟路径改动带下两个端点。
  - `hfp_split_near`(−0.110)：`sel_ex_mem_rs2→dcache` 曼哈顿 174→53 格，route 6.17→8.30 ns → 距离↓不代表延迟↓（pblock 拥塞，未用 congestion 报告交叉验证）。
- campaign `results.tsv` 58 行重解析：**36 RESULT / 5 SMOKE(place-only，非失败) / 17 EXIT=1**（此前误报 22 次）。
- 17 次 EXIT=1 归因：**15 次为 Tcl 脚本错误**（`vspec` 的 `array set` 收到奇数元素，`run_variant.tcl:57`，启动 4 s 即退，5 份 backup 日志有相同 trace；另 10 次日志被后续成功 run 覆盖，只能判同类）；1 次 `fp3_loose` PLACE_DENSITY 非 pblock 属性（Netlist 29-177）；1 次 `hfp_split` 在 phys_opt Phase 4.1.1.2 被外部终止（无 ERROR/无 COMPLETE/无产物）。证据见 `html/probe/campaign_failures.md`。
- 站点：新增每页「数据版本条」+ `?v=20261021c` 缓存戳（解决"改动看不到"）；index/modules/paths/history/experiments/next 数据全部重算；`check_pages.js` 改为按页面真实 `<script src>` 加载（此前漏了 campaign.js/version.js，导致误报）。
- 验证：`node check_pages.js` → `ALL PAGES OK`（9 页）；截图核对 index/modules/paths/experiments/next。
- 未做：campaign 最优版的 WHS 未进 `results.tsv`（记 `not_measured`）；拥塞交叉验证未做；`src/rtl` 未动（用户自己改）。

### 2026-10-21 13:06 — 冠军网表出 bitstream（xc7z020clg400-1）

- `build/local/backend_opt_20261021/pl_ndh_crit200_ntr/pl_ndh_crit200_ntr.bit`
  （4,045,687 B，sha256 `6cff4f2f7443e68c38549ed8db2b8aed13259ba60c2d1b5adcff66c8614e4baa`），
  `.bin` 同时产出；Bitgen 自带 DRC 仅 warning，无 error。
- 出 bit 前复测 WNS +0.138 / WHS +0.017；引脚沿用 baseline `const.xdc`
  （clk=U18 假设 50 MHz、reset=N16、uart T19/J15、led H15/L15、button L14/K16）。
- **未验证**：板上任何现象（未烧录）；板型/时钟引脚未核实（`xc7z020` 是器件不是板型）；
  IO 无 delay 约束；BRAM 内是 baseline 的 `freertos_demo.coe`（8333 字），**不是 Ascon 固件**。
- 下一步（T0.2/T0.3）：`ascon_ise.hex` 32768 行 = 板级 BRAM 深度 32768 字（32×ramloop，
  32-bit 宽），可 1:1 转 COE → 换 `blk_mem_gen_0` → 重新 synth+impl → 新网表重测时序
  （+0.138 不保留）→ 再出 bit；另需板级自检固件与串口回归框架。

### 2026-10-24 16:40 · 布局布线双页 + 复制寄存器 + 时钟偏斜归因（站点）

- 起因：用户指出「布局图里看不到复制寄存器」。核查确认：`layout.html` 的 27 条路径全部来自 base run，ndh 只在对比模式里叠色；而**复制寄存器从来没有被画过**。
- 新页 `html/layout_ndh.html`：主图 = `pl_ndh_crit200_ntr_dup`，默认叠加 base 灰虚线；与 `layout.html` 双向跳转（导航栏「布局(最优版)」+ 页内按钮）。
- 新探针 `probe/replica_probe.tcl`（只读 DCP）：导出 replica 单元的 `REF_NAME/LOC/CLOCK_REGION` 与原单元坐标。结果：**base 5 个副本 / ndh 52 个副本**（ndh 的副本集中在 `*_BUF[*][31]_i_1` 这类使能译码 LUT，每个复制 2 份，覆盖 4 个 clock region）。
- base 的 5 个副本里包含 `clkout1_buf_replica` —— 即 **clk_out1 上串了两个 BUFG**（`clkout1_buf_replica → clkout1_buf`）；ndh 只剩一级。
- 时钟偏斜归因（回答用户提问，数据来自 `probe/fp_paths*/dcache_to_mmio.rpt` 的 Clock Path 段）：
  | 项 | base | ndh |
  |---|---|---|
  | BUFG(clk_out1) | 2 | 1 |
  | dcache `bus_addr_r` FF | SLICE_X81Y20 · X1Y0 | SLICE_X65Y21 · X1Y0 |
  | MMIO `MSG_BUF`（2048 FF） | SLICE_X45Y114 · **X0Y2** | SLICE_X36Y85 · **X0Y1** |
  | 全局时钟 net 到 dcache / MMIO | 1.723 / 1.699 | 1.718 / 1.466 |
  | SCD / DCD / CPR | −2.156 / −1.675 / −0.504 | −2.423 / −2.146 / −0.528 |
  | **skew** | **−0.024** | **−0.252** |
  | data path | 9.152 | 9.103 |
  → 结论：唯一倒退不是数据路径变差（快 0.049），而是 **MMIO 那 2048 个 FF 从 clock region X0Y2 搬到 X0Y1**，捕获时钟提前 0.233 ns，skew 由 −0.024 变 −0.252。同一搬动也解释了 `u_crypto_aead` 的 −0.180。
- 全站 16 条路径的 skew 分布：base −0.225…+0.052，ndh −0.252…+0.054 —— **离散步长几乎不变（0.28 vs 0.31 ns）**，变的是「哪条路径抽到下签」。所以设计的时钟树本来就带 ~0.25 ns 的落地差，WNS 只有 0.1 ns 余量时等于听天由命。
- 站点修正：Δ 列改为「本页 − 对比」；彩线恒为本页网表；路径列表标题与 Δ 表头改为动态 tag；`next.html` 的 ndh WHS 由 `not_measured` 更正为 **+0.017**（比基线 +0.023 更差）。
- 验证：`node check_pages.js` → 10 页 `ALL PAGES OK`；截图核对 layout / layout_ndh（含 ?preset=ascon）。
- 未做：`mult_to_dcache` 仍无直接探针值；拥塞交叉验证未做；RTL 未动。


### 2026-10-24 17:25 · next.html 路线实测：F（MMIO 写译码寄存化）+ R（80 MHz）

- 起因：用户要求按 `html/next.html` 的建议顺序（先 R 后 F）真跑一遍看效果。基线 `3c6f134`，
  `src/rtl/dcache.v`/`ascon_ise.v` sha256 与 2026-10-20 control 记录一致；`src/rtl`、`board/`、
  XDC 全部未改，变体都在 `build/local/tests_20261024/` 副本里。工具 Vivado 2025.2，
  part `xc7z020clg400-1`，top `top_pl_bram`。
- **F（补丁 `build/patches/timing_F_mmio_wdecode.patch`，只改 `ascon_mmio.v` +35 行，把写请求打一拍）**：
  - 100 MHz，ExploreWithRemap：WNS **+0.007 → −0.072**（TNS −1.289、**35 失败端点**），WHS +0.030，LUT +1.8%；
  - 100 MHz，ExplorePostRoutePhysOpt：WNS **+0.005 / 0 失败端点 / WHS +0.051**（对照第二策略 +0.001/2 端点）；
  - 目标族 `dcache/bus_addr_r → ascon_mmio`：**8858 → 60 条**（worst +0.525 → **+1.233**），
    MMIO 终点 <1.0 ns **1667 → 701**，全设计 slack<2.0 ns **14161 → 10245**；
  - 新墙 = A 族 `id_ex_u/sel_ex_mem_rs1_o_reg → u_dcache/valid_way*/D`（11 级 / logic 3.004 ns），
    与 next.html 预测一致 → **F 是清场，不是提余量；必须配 A**。
  - 仿真 6 场景（`build/local/tests_20261024/check_F.sh`）：7 项硬件 KAT 全 PASS、crypto latency 99 不变、
    软件 4 workload cycles 完全相同；**硬件 MMIO 全卸载 670 → 675 拍（+5）**，
    按 next.html 给 F 的"拍数不许变"门禁**不合格**。
- **R（80 MHz）关键纠正**：同一份未改 RTL，把核心约束改 12.5 ns **重跑综合+实现**只有
  **WNS +0.483**（0 失败端点、WHS +0.018）；原因是 P&R 按松约束松手——最差路径 route 9.167 ns
  （100 MHz 网表同类 ~7.6 ns），物理质量损失约 1.9 ns。站点"80 MHz +2.340 / 折算 +2.483"
  只对**已按 10 ns 布线**的网表成立。→ 正确做法：实现仍按 10 ns 过度约束，只改 MMCM 输出；
  验收用 post-route `reset_timing` + 12.5 ns 重算（`build/probe_freq_headroom.tcl`）。
  F 在 12.5 ns 下为 +0.456（比 control 的 +0.483 低 0.027，噪声带内）。
- WHS 在两种频率下都 <+0.05 门禁（+0.018~+0.051，只有 F+pr @100 MHz 的 +0.051 刚过）。
- 证据：`docs/timing_route_tests_20261024.md`、`build/reports/tests_20261024/{f_100,f_100_pr,ctl_80,f_80}/`、
  `build/local/tests_20261024/{paths_ctl.csv,paths_f100.csv,sim/*.log}`。
- 未做：C（store buffer）、A、D；板级 XDC/PS7 在场时序；MMCM 80 MHz 重生成网表 A/B；拥塞交叉验证。


### 2026-10-24 20:45 · 第二波：F+A（A 已在 RTL 里）+ F×后端配方

- 用户选定"F+A 合并测"。核实：**路线 A 描述改动已在 RTL 里**——旁路选择在 ID 段算
  （`cpu_core.v:373-386`，注释"在 ID 阶段提前计算旁路选择信号"）、ID/EX 边界寄存
  （`id_ex.v:183-186`）、EX 只用寄存位做 3 输入 mux（`bypass.v:25-40`）。
  → **F+A = F**，本波不新增 RTL 改动。
- F 之后真正的墙：`sel_*_o` 起点 1072 条 slack<2.0 路径，其中**只有 192 条压时序**
  （`dcache/valid_way0|1_reg` D 64+64 worst −0.072、`lru_reg` D 64 worst −0.063）；
  其余是 MMIO 缓冲区（worst +1.44~+1.87）。这 192 条来自 `dcache.v:471-505`
  「store 命中清另一路 / load miss 清 victim / hit 更新 LRU」必须同拍做 tag 比较，
  与 store 同拍写 BRAM 同源 → **只有 C（store buffer）或 tag 读打一拍能摘，A 摘不掉**。
- F + campaign 冠军配方（起点 F 的 post-opt dcp，脚本 `run_backend_F.tcl`）：
  - `F_pl_ndh_crit200_ntr`：WNS **−0.226** / TNS −9.028 / 102 端点 / WHS +0.015；
  - `F_pl_ndh_crit200_prod`：WNS **−0.225** / TNS −21.172 / 228 端点；
  - 对照：同配方打在未改 RTL 上是 +0.138。→ **campaign 收益不能迁移到 F**；
    可查原因：F 网表上 `crit_ce_nets` 只 13 条（最差 200 端点里 CE 网很少），
    而 F 的墙在 D 端，CE 复制打不到。
- 定向扇出复制臂（`run_selrep.tcl`，4 条 `sel_*_o` fo=172/141/172/140 + 309 条 forward 位网，
  MAX_FANOUT=8 + EQREG NO）与不做复制的 placeonly 臂**逐位相同**（−0.175 / 81 端点 / LUT 13799）；
  `probe_mf.tcl` 确认 `MAX_FANOUT=8` 写进去了但扇出仍 172、**没生成副本**——
  post-opt checkpoint 流程里 `MAX_FANOUT` 不触发复制，要复制得走
  `phys_opt_design -force_replication_on_nets`。**该臂是空实验，不作结论**。
- 顺手清理：这两臂因脚本 root 少了一层，把 `build/build/` 建进了仓库；报告已移到
  `build/reports/tests_20261024/F_pl_ndh_crit200_*`，DCP 移到 `build/local/tests_20261024/backend/`，
  仓库内无残留（`git status` 只剩新增 docs/与既有 untracked）。
- 净结论：F 不值得单独上（100 MHz 与 control 同级、80 MHz +0.456 vs +0.483、还要 +5 拍 MMIO）；
  F 的价值是暴露 C 要摘的那一族。要 100 MHz 余量只能做 C 或 tag 打拍；要立刻可交付
  用「control RTL + 10 ns 过度约束 + MMCM 80 MHz」。
- 证据：`docs/timing_route_tests_20261024.md` §7。


### 2026-10-24 21:25 · 路线 C（dcache store buffer）实测通过，0 周期

- 补丁 `build/patches/timing_C_dcache_store_buffer.patch`（只改 `src/rtl/dcache.v`，`git apply -p1` 干净）：
  ① store 当拍只进 1 项 buffer，下一拍提交；`data_way0/1` 改成真正的 SDP（Port A 只读，
  Port B 由 fill 与 buffer 提公共用，fill 优先）② valid/LRU 更新寄存一拍（`upd_*` 记录）
  ③ store→load 定向转发（`sb_valid && sb_addr == rd_addr` 按字节掩码覆盖）。
- **实现结果（Vivado 2025.2，xc7z020clg400-1，Performance_ExploreWithRemap，10 ns）**：
  | 变体 | WNS | TNS | 失败端点 | WHS | LUT | FF | BRAM |
  |---|---|---|---|---|---|---|---|
  | control（10-20 记录） | +0.007 | 0 | 0 | +0.023 | 11509 | 16040 | 38.5 |
  | **c_100（C）** | **+0.057** | 0 | **0** | +0.019 | 11476 | 16146 | **34.5** |
  | fc_100（F+C） | +0.005 | 0 | 0 | +0.013 | 11784 | 16189 | 34.5 |
  → C 是第一个既把目标族打穿、又在 100 MHz 上正收益的 RTL 改动；**F+C 不如 C 单独**（F 的 +202 LUT 纯负担）。
- **等价性两道**：① 全 SoC 6 场景（`check_C.sh`）KAT 全 PASS，cycles 与 control 完全相同
  （ise/ise_stall/ise_reset 2496、hw full MMIO **670** 与 latency 99 不变、sw 17353/21515/17847/22094 不变）；
  ② 新增 dcache 逐拍差分激励 `tb_dcache_trace.v`（伪随机 + 定向 store→load / store→store→load 同地址），
  4 个种子逐字节相同（含末尾存储器校验和）。
- **路径族证据**（`paths_c100.csv`）：`dcache/valid_way*|lru` 终点 192（control）→224（F）→**12（C）**，
  worst −0.072 → **+1.752**；`->u_dcache` 489→343（worst +0.249）；起点 `sel_*` 1218→505。
  C 之后最差单条变成 `pc_reg[5] → u_ex_mem/ex_rd_data_o_reg[0]/CE`（+0.057，9 级 logic 2.0 route 7.59），
  第二大族 `pc_reg[5] → u_ascon_ise` 649 条 worst +0.224 → **下一刀是 D（取指/stall 环），A 仍无事可做**。
- 未验证：板级；WHS +0.019 仍 <+0.05 门禁；C+campaign 冠军配方的叠加测试（21:07 启动，phy_opt 阶段长时间无输出，
  报告时未出结果 → not_measured）。
- 证据：`docs/timing_route_tests_20261024.md` §8、`build/reports/tests_20261024/{c_100,fc_100}/`、
  `build/local/tests_20261024/{rtl_C,rtl_FC,tb_dcache_trace.v,diff/}`。


### 2026-10-24 22:05 · 路线 C 落地到 src/rtl + 修掉队友 include 导致的 elaboration 失败

- `src/rtl/dcache.v` 应用 `build/patches/timing_C_dcache_store_buffer.patch`（1 项 store buffer +
  valid/LRU 更新寄存一拍 + store→load 定向转发）。落地后 sha256
  `79af461cf53545e79c294814e7f4869c341dbb745527885c0ee1755c1b5c1113`，与 `c_100` 实测那版**逐位相同**
  → WNS +0.057 / TNS 0 / 0 失败端点 / WHS +0.019 / LUT 11476 / FF 16146 / BRAM 34.5 这组数字对入库代码直接成立。
- 撤掉 `fb852b5` 在 `ascon/{ascon_mmio,ascon_ise,ascon_aead_core}.v` 顶部加的 `` `include ``：
  这三个文件无 include guard（同目录 `crypto_aead.v`/`ascon_permutation.v`/`ascon_round.v`/`ascon_word.v`
  都有），而它们同时作为独立源文件编译 → `'ascon_aead_core' has already been declared`，
  整库 elaboration 失败、回归跑不起来。撤掉后全 RTL elaboration 通过。
- 落地后回归：`build/local/tests_20261024/check_final.sh`（control = HEAD 的 dcache.v + 当前其余源
  vs 当前 `src/rtl`）6 场景，KAT 与 cycles 需逐条相同。
- 同步：main 上先提交了实测报告/补丁/报告归档（`431695b`），与 origin/main 的 `fb852b5` 做增量合并
  （`38e96fb`），已验证 5 个补丁合并后仍 `git apply --check` 干净。
- 未验证：板级 STA；C 之后 100 MHz 仍只有 +0.057 ns 芯片级余量（自定门禁 +1.0 未达），
  WHS +0.019 < +0.05 门禁。


### 2026-10-24 22:45 · 路线 D（中断可接受判决拆拍）实测 +0.087 ns 并落地

- 目标路径（C 之后整机最差 +0.057，9 级 / logic 2.0 / route 7.59）：
  `pc_reg → u_icache tag RAM → hit_way0 → icache_stall → csr_file/inter_req → flush[1] → u_ex_mem/CE`。
  根因在 `cpu_core.v` 的 `inter_accept_ready` 把 pc 衍生的 `!icache_stall` 和当拍快条件放同一个与门。
- 改法（补丁 `build/patches/timing_D_interrupt_guard_register.patch`，只改 `cpu_core.v`）：
  `inter_slow_ok = id_ex_inst_valid && !icache_stall` 只驱动一个触发器 `inter_slow_ok_q`，
  `inter_accept_ready` 当拍再与 `inter_slow_ok_q` + 全部快项（id_ex_inst_valid /
  dcache_stall / dmem_axi_stall_req / ex_stall_req / fence_i_stall）相与。`csr_file` 的一次脉冲语义未改。
- 实测（ExploreWithRemap / 10 ns）：WNS **+0.057 → +0.087**、TNS 0、0 失败端点、WHS +0.021、
  LUT 11483（+7）、FF 16156（+10）。
- **机制证据**（`paths_c100.csv` vs `paths_d100.csv`）：起点含 `pc` 的路径 **1389 → 1 条**
  （worst +0.057 → **+1.491**）；终点 `u_ascon_ise` +0.224 → +0.794；终点 `ex_rd_data_o_reg` +0.057 → +0.648。
- **D 之后新墙不再是 CPU**：`u_crypto_aead/FSM_sequential_state_reg[3] → u_crypto_aead/p12_in_reg[215]/D`
  （+0.087，**1 级逻辑**、route 9.290 = 94%）——Ascon 核心 p12_in 状态搬运的物理跨度问题。
- 等价性：全 SoC 6 场景（control = C 落地后 src/rtl，patched = C+D）KAT 全 PASS，
  cycles 逐条不变（2496 ×3、hw 99/670、sw 17353/21515/17847/22094）。
- **风险**：全部固件/单元/ISA TB 都没开中断（无 mtvec/mret/mie），所以本改动在功能上等价空操作；
  一旦启用中断必须先补定向 TB 验证"晚一拍接受"不会让 trap_pc 指向气泡。
- 落地：`src/rtl/cpu_core.v` 已应用补丁，与 `d_100` 实测所用 RTL 逐位相同。
- 当前 100 MHz 芯片级余量：**+0.087 ns**（基线 +0.007 → C +0.057 → C+D +0.087），WHS +0.021。

### 2026-10-24 23:05 · 队友提出的 RTL 纪律 skill 收入 `skill/`（只加文档，不动 RTL）

- 起因：队友 2026-10-17 指出 AI 写 Verilog 的通病（同一逻辑写出一堆等价废话、打补丁式改代码、
  电路层优化意识差、生成无必要的组合逻辑），据此形成的 skill 已落在 agent 侧
  `skills/verilog-design/rtl-design-discipline/SKILL.md`；本轮把同一份文件复制进仓库受控目录
  `skill/rtl-design-discipline/SKILL.md`（sha256 `ca5413cd…c7ed`，与 agent 侧逐字节相同，
  155 行），供队友与提交材料直接取用。
- `skill/readme.md` 改写为「已交付 / 预留」两段：写明依赖、输入输出、执行步骤、成功判据、
  失效条件、来源案例，并明确标注**非 Ascon 示例上的对照效果 not_validated**，
  据此不满足 S05 要求的「已验证效果」一项。
- 未改 `src/`、`board/`、XDC、XCI、COE，未跑仿真/综合，未 commit。
- 未验证：该 skill 是否真能降低 LUT/FF 或缩短最差路径（需要的对照实验见 readme 的
  「已验证效果」段，`not_measured`）。



### 2026-10-25 00:10 · 大扇出节点本地化复制（state[3] fo=628）+0.130 ns

- 定位（C+D 之后最差路径）：`u_crypto_aead/FSM_sequential_state_reg[3]/Q → net state[3]
  （fo=627、**单根走线 9.290 ns**）→ LUT5 → p12_in_reg[215]/D`，整条 9.870 ns、**1 级逻辑**。
  `state[3]` 是 `crypto_aead.v:99` 的 FSM 状态位，扇出到整条 datapath 的使能/选择锥。
  全局最大扇出是复位分发网 `u_ascon_mmio/rst_sync_reg[2]` fo=9757（但不在关键路径上）。
- 新脚本 `build/timing_tests/{rep_fanout.tcl,probe_fanout.tcl}`：
  从**布线后** DCP 选点（post-opt 视图看不出走线）→ opt 前给驱动设
  `EQUIVALENT_REGISTER_REMOVAL NO`（防折叠）→ place → `phys_opt_design -force_replication_on_nets`
  + `MAX_FANOUT 128` → 复制体再设 EQREG NO（不用 DONT_TOUCH，否则冻结放置）。
- 结果（同流程 optExplore+placeDefault+physAgg+routeAgg）：
  | 臂 | 复制对象 | WNS | WHS | 失败端点 | replica |
  |---|---|---|---|---|---|
  | rep_ctl | 无 | +0.003 | +0.024 | 0 | 51 |
  | **rep_ff400** | **只 state[3]** | **+0.130** | +0.013 | 0 | 60 |
  | rep_any150 | 24 根宽网 | +0.124 | +0.013 | 0 | 93 |
  | e_100 | RTL `max_fanout=64` + 生产策略 | **−0.008** | +0.028 | **1** | — |
  → **只复制一根网就 +0.127（同流程对照），复制 24 根反而略差**；
  **合成期复制（RTL 属性）是反例**：放置后复制才能把 628 个负载分给就近副本。
- 复制后 `state[*]` 从 fo≥128 清单消失；新最差 `sel_ex_mem_rs1_o_reg →
  u_ascon_ise/state_reg[182]/CE`（+0.130）与 `→ dcache/captured_wdata/CE`（+0.130），
  即下一根要拆的是 `sel_*` 那 4 条 fo≈171 的 1 位网。
- 性质：**不是 RTL 改动**（`src/rtl` 未动），是实现流程的一步；仿真无影响
  （`e_100` 的 6 场景 cycles 与对照完全相同）。
- 未验证：minfo/副本数量未扫；复制步骤尚未接进生产策略（`rep_ctl` +0.003 说明该流程本身
  比生产策略差 0.08，+0.130 不能直接当最终余量）；WHS +0.013 仍 < +0.05。
- 追加臂 `rep2_sel`（以 rep_ff400 网表为种子再复制 9 根：`pc_o[5/6]` fo=218/215、
  `func_sel_o[0]` 137、`ascon_mmio/Q[0]`、`p12_inst/Q[0]`）：WNS **+0.055**，
  比只复制一根（+0.130）差 0.075 → **复制必须停在"使能锥上的一根"，继续加反而变差**。


### 2026-10-25 01:10 · 复制步骤接入生产策略后重测：收益不复现（+0.087 → +0.039）

- 新脚本 `build/timing_tests/run_prod_rep.tcl`：仍用 `-strategy Performance_ExploreWithRemap`，
  只给 `STEPS.PHYS_OPT_DESIGN.TCL.POST` 挂一个复制钩子（放置后、布线前），策略/directive 一字不改。
- 结果（起点=当前 src/rtl，C+D 已落地）：
  | 臂 | 钩子 | WNS | 失败 | WHS | replica | 最差路径 |
  |---|---|---|---|---|---|---|
  | prod_ctl | 无 | **+0.087** | 0 | +0.021 | 51 | state[3]→p12_in_reg，9.870/net 9.290/1 级 |
  | prod_rep1 | 只复制 state[3]（fo 628） | **+0.039** | 0 | +0.020 | 60 | ex_mem/ex_rd_data_o_reg[11]→if_id/pred_target/CE，9.595/logic 3.183/11 级 |
  | prod_rep | 复制 2 根 | +0.039 | 0 | +0.020 | 60 | 同上 |
  - `prod_ctl` 逐位复现 `d_100`（+0.087，同一条最差路径）→ 新 run 流程与 run_variantF 等价。
  - 钩子确实生效：`fo=628 → after fo=25`，那根 9.29 ns 网从关键路径消失；
    但整机 −0.048：**省下的走线被 ~50 个副本 FF 的布局扰动吃掉**。
- 结论：**§10.3 的 +0.127 ns 是自定义流程上的收益，不能迁移到生产策略**；
  复制步骤**不进流程**，脚本留作工具与证据。
  **当前 100 MHz 最好成绩 = 生产策略 + C + D = +0.087 ns**（prod_ctl 与 d_100 互证）。
- 现在剩余的墙是 logic 型：11 级 / 3.183 ns logic 的 `ex_mem → if_id/pred_target/CE`、
  以及 pc→icache→id_ex CE 一族 —— 继续做扇出/复制没有边际，得动 if_id/if_stage 控制结构（D2）或 icache tag 打拍。

### 2026-10-25 01:40 · 时序工作台 v2 站点 + 生产流程复制臂矩阵（复制不可迁移；属性与 phys_opt 只在组合下有效）

**任务**：用户在夜间授权做两件事：① 等上一轮复制实验跑完后，把「新一轮工程」做成一个完整的可视化站点
（参照 `ours/html/` 的旧站，不复用其页面结构，只复用其探针数据）；② 重点放在后端（布局布线）优化，
再由布局布线的证据推出改 RTL / 改约束的建议。站点在仓库外 `ours/html_v2/`，未改 `src/rtl`、`board/`、XDC，
未 commit。

**站点**（10 页，纯静态，`file://` 直开）：
`index / wall / attribution / layout / backend / experiments / rtl / pipeline / next / method`。
数据全部由 `html_v2/build/build_data.py` 从 `build/reports/**/result.txt`、`path_csv/paths_*.csv`、
逐跳 `route_paths.rpt`、旧站探针产物（模块 bbox / 复制寄存器）重新抽取 → `data/*.js`；
`build_site.py` 把 `build/pages/*.html` 套进统一外壳；`build/check_site.py` 用无头 Chrome 逐页
dump-dom 查 JS 异常/空容器/NaN（当前 10/10 通过）。旧站探针产物被重新打包成 `data/layout.js`
（base / ndh 两个数据集 + 52 个复制单元），没有重跑那 20 分钟的探针。

**本轮新增的实现臂**（全部 `Performance_ExploreWithRemap` 全流程、核心 10 ns、RTL = 当前 `src/rtl`，
唯一差别是 `PHYS_OPT_DESIGN.TCL.POST` 钩子；脚本 `build/timing_tests/run_prod_arm.tcl` +
`hooks/rep_hook.tmpl` / `hooks/physopt_only.tmpl`，批次 `run_batchA/B/C/D.sh`）：

| 臂 | 钩子做的事 | WNS | 失败 | WHS | 复制单元 | FF |
|---|---|---|---|---|---|---|
| `pr_ctl` | 无 | **+0.087** | 0 | +0.021 | 51 | 17187 |
| `pr_ctl2` | 无（独立第二次） | +0.087 | 0 | +0.021 | 51 | 17187 |
| `pr_mfonly` | 只设 `MAX_FANOUT`，不复制 | +0.087 | 0 | +0.021 | 51 | 17187 |
| `pr_rep_state` | 按**单元名**选点 → `candidates=0`（空臂） | +0.087 | 0 | +0.021 | 51 | 17187 |
| `pr_rep2_state` | 复制 `state[3]`（60 副本） | **+0.039** | 0 | +0.020 | 60 | 17196 |
| `pr_state_b` | 同上（复跑） | **+0.039** | 0 | +0.020 | 60 | 17196 |
| `pr_rep2_sel` | 属性 + 多一次 `phys_opt_design`（0 副本） | **+0.184** | 0 | +0.021 | 51 | 17187 |
| `pr_sel_b` | 同上（复跑） | **+0.184** | 0 | +0.021 | 51 | 17187 |
| `pr_selprops` | 只设属性、**不跑**那次 phys_opt | +0.087 | 0 | +0.021 | 51 | 17187 |
| `pr_rep2_both` | state + sel 属性 + phys_opt | +0.149 | 0 | +0.023 | 80 | 17216 |
| `pr_both_b` | 同上（复跑） | +0.149 | 0 | +0.023 | 80 | 17216 |
| `pr_physopt_only` | **只多跑一次裸 `phys_opt_design`**（不设属性、不复制） | +0.087 | 0 | +0.021 | 51 | 17187 |
| `pr_physopt_b` | 同上（复跑） | +0.087 | 0 | +0.021 | 51 | 17187 |
| 协作方 `prod_ctl` / `prod_rep` / `prod_rep1` | 独立实现：对照 / 复制 state | +0.087 / **+0.039** / +0.039 | 0 | +0.020 | 51 / 60 / 60 | — |

**三条结论（全部有复现）**

1. **复制不能从自建流程迁移到生产流程。** 同一根 `u_crypto_aead/state[3]`（fo=628、单根 9.29 ns）：
   自建流程（`opt Explore / place Default / phys_opt Aggressive / route Aggressive`，对照 `rep_ctl` +0.003）
   复制后 **+0.130（+0.127）**；生产流程（对照 `pr_ctl` +0.087）复制后 **+0.039（−0.048）**。
   本站 `pr_rep2_state` 与协作方 `prod_rep` 是不同脚本/不同钩子写法，给出**逐位相同**的 +0.039、相同失败端点、
   相同 `dp/logic/net/levels`。原因：自建流程本身比生产策略低 0.084，复制修的是那条流程自己的病灶；
   生产策略的 opt 已经把布局调到"刚好合适"，再插复制会把 CPU 侧 11 级路径顶上来
   （新墙 `ex_mem/ex_rd_data_o_reg[11] → if_id/pred_target_o_reg[13]/CE`，11 级 / logic 3.183 / net 6.412）。

2. **`sel_*` 复制一个副本都不生成。** 4 条网（12 个别名，fo 172/141/172/140）设 `MAX_FANOUT 128` +
   `-force_replication_on_nets` 后副本仍 51、FF 仍 17187 —— 工具按**物理收益**决定是否复制，不是按扇出阈值。
   这条只能靠"数副本数"得到，只 WNS 会误读。

3. **唯一剩下的余量来自一个「组合动作」，而且与复制无关（2×2 消融，每格都有两次独立复现）。**

   |  | 不跑额外 phys_opt | 多跑一次 `phys_opt_design` |
   |---|---|---|
   | 不设属性 | `pr_ctl`/`pr_ctl2` **+0.087**（逐位相同） | `pr_physopt_only`/`pr_physopt_b` **+0.087**（逐位相同） |
   | 设属性（`EQREG NO`+`MAX_FANOUT 128` 于 4 条 `sel_*`） | `pr_selprops` **+0.087** | `pr_rep2_sel`/`pr_sel_b` **+0.184**（逐位相同） |

   也就是说：**属性单独是空操作、裸 pass 单独也是空操作，只有"带着 `MAX_FANOUT/EQREG` 提示要求工具重做那几条网"
   才拿到 +0.097**。它**没有生成任何副本**（副本 51、FF 17187，与对照一致），收益出现在别处：
   `state[3]` 那条 slack 从 +0.087 抬到 **+0.284**，新最差变成
   `sel_ex_mem_rs1_o_reg → if_id/pred_target_o_reg[12]/D`（13 级 / logic 3.52 / net 5.81）。
   **机制未定论**（没有 `report_design_analysis`、没有前后 placement 逐单元对比），只能当经验结果。

**新踩的坑**（已写进 `project_log/lessons_learned.md`）：
钩子 `.tcl` 花括号提前闭合（两臂 00:24:41 双退）；选点按驱动单元名而非网名（`state[3]` vs
`FSM_sequential_state_reg[3]` → `candidates=0` 空臂）；给 `vivado.bat` 传 MSYS 路径
（`Failed to create directory 'C'`，日志全丢）；`report_timing` 元素表 net 行没有 edge 字母。

**可比性**：18 个生产流程臂的 `build_context.txt` 里 `dcache.v 79af461c…` / `cpu_core.v 95d78121…` /
`crypto_aead.v 722bf1e3…` 三个 sha256 全部一致；期间 HEAD 从 `3cfbe51` 前进到 `805b01a`（协作方提交了
prod_rep 的负面结果），但 `git diff --stat 3cfbe51..805b01a -- src/ board/` 为空 —— 所以 2×2 的差异只可能来自钩子。

**站点补记**：布局页已接入第三个数据集 `pr2`（本轮 `pr_rep2_sel` 的真 routed DCP 现跑探针：
`html/probe/floorplan_probe.tcl -tclargs <dcp> pr2` → `parse_floorplan.py --tag pr2` → `data/layout.js`）。
探针顺带给出一个独立证据：`pr2` 上 `pc_to_dcache/pc_to_ex_mem/pc_to_ise` 三个路径族**一条路径都抓不到**，
与 `paths_d100.csv` 里「起点含 pc 的 1389 → 1 条」互相印证 D 的效果。

**未验证**：+0.184 的**第三遍**复现与机制归因（是否换一批 net 名字仍成立）；把该组合动作写成独立 impl 入口后的
全套功能回归（`docs/freeze_checkpoint_20261018.md` §2）；板级 XDC/PS7 下的 STA；`minfo`/副本数扫掠；
`pr2` 数据集的复制寄存器探针（未跑，故布局页该层为空）。


## 2026-10-25 — Navigator成果提交与V01定向验证

owner TBD；用户明确授权首次commit/push，后续新增测试保留本地未提交。

- 已发布20文件至feat/navigator_preboard，commit `68fafc8eca095ce8afdf203edf4aea726151dfbc`；远程main仍`f88e178`。逐文件暂存/敏感信息与生成产物核对/cached diff --check通过；没有Skill/PUF/生产RTL/baseline改动。
- D-Cache原4项FAIL分类**TB_STALE**：旧TB在36ns三项、206ns一项检查，MISS_CAPTURE实际45/215ns发总线请求。f52bc49（miss流水前）旧TB PASS；38e96fb（Store Buffer前）与当前同4 FAIL。Store Buffer前后4种子逐拍信号/最终MEMSUM完全一致。
- 新tb_dcache_contract在前后版本均PASS：578 loads、671 stores、404 reads、1616 fill beats；独立参考内存与总线顺序/掩码/回填检查，错误回填/丢写注入均exit1。没有改dcache或原TB来消除失败。
- CPU+真实CLINT的6个RV32场景均实际接受一次timer interrupt并执行一次handler/mret；覆盖I-Cache miss、DIV、外部存储停顿、D-Cache miss、branch flush/guard延后，检查mepc/mcause/mstatus、真实指令PC、恢复结果。NO_TIMER、BROKEN_MRET及临时副本绕过inter_slow_ok_q都触发exit1。生产CPU/CSR/CLINT/SoC未改。
- `python -B sim/board/run_targeted_validation.py --out build/local/preboard_targeted_final_03` PASS/exit0（45命令、5额外检查）；Icarus/vvp12 devel、GCC13.2/binutils2.42、Python3.14.3。当前smoke `build/local/preboard_followup_smoke_01/` 6 PASS/0 FAIL/9 NOT_RUN，exit0；中断有测试后在smoke标NOT_RUN、regression实际调用新套件。旧D-Cache FAIL条目及历史全回归报告保留，不宣称完整regression全绿；未重跑耗时Ascon全SoC验证。
- 局限：未验SoC CLINT MMIO路由、完整AXI/Cache一致性、嵌套/全部优先级、RV64及全部多周期抢占；V01保持in_progress。板级/PYNQ真实链路仍NOT_CONFIGURED/NOT_RUN，FPGA cycles/PPA NOT_MEASURED。
- 独立PL工程可开始配置/离线重建准备；正式下载前核实实物速度等级、板级clock/reset/UART、重建IP/COE和STA/DRC；先JTAG/LED/UART，再SW→MMIO→ISE，最后PS/PYNQ。镜像优先向厂家取得，备选锁定2.7/2020.2 BSP+sdbuild。未运行Vivado构建或下载。

证据与文件：`board/atk_navigator_7020/validation_followup.md`、`validation_evidence.json`、`next_bringup.md`、`sim/board/run_targeted_validation.py`及3个RTL/assembly测试输入。用户本轮允许后仅追加公共记录并同步V01；这些后续修改未再次commit/push。下一接收V01/B03/B02/Y01/Y02，owner TBD。


## 2026-10-25 — V01 D-Cache测试契约修订与完整回归PASS

owner TBD；分支feat/navigator_preboard，HEAD仍68fafc8，保留既有13项未提交工作，本轮未commit/push/merge。

- 独立连续两次复现原TB四项FAIL/exit1，保留修改前文件与日志。根因是IDLE接受请求后经过MISS_CAPTURE才发单拍request；旧36/206ns检查早于45/215ns合法事件。分类TB_STALE，不是生产RTL修复。
- 仅修订sim/cicc1000023/unit/dcache/tb_dcache.v：8拍有界请求事件等待、独立预期事务队列、方向/地址/data/mask/qualifier/次数和回填检查；完成上限仍30拍，negedge驱动/posedge NBA后采样。原场景和expected保留，增加byte lane、连续store、跨拍stall、半条line reset中止以及已有效line的reset失效检查。
- 修订TB在Store Buffer前与当前生产源码均PASS：116检查、13事务、18回填beat；独立事务TB保持578读/671写/404读事务/1616beat PASS；4种子逐拍差分一致。
- 修订TB的坏回填、缺读、重复读、错地址、错写data、错mask、缺写7种反例均exit1；原事务TB的坏回填/丢写和中断3种反例也全部按预期失败。历史原TB+RTL按已发布68fafc8冻结，只用于历史复现，不驱动当前正常测试的FAIL豁免。
- 按要求实际执行python -B sim/board/run_tests.py --mode smoke：6 PASS/0 FAIL/0 BLOCKED/9 NOT_RUN，exit0，16.394s。完整--mode regression：15 PASS/0 FAIL/0 BLOCKED/1 NOT_RUN，exit0，757.713s；SW/MMIO/ISE、完整Host KAT、Mailbox、COE/CPU镜像一致性、修订TB、独立事务TB与6个真实CPU+CLINT中断场景均实际运行。
- 唯一regression NOT_RUN是实板UART/Overlay；hardware cycles NOT_MEASURED。正常测试未发现未解释功能性FAIL，仍不等于全部ISA/RV64/异常/SoC/板级门禁；V01保持in_progress。生产RTL、Skill/PUF/密钥管理、原baseline、PYNQ文件未动，前后原始SHA核对PASS。

证据：build/local/dcache_tb_revision_20261025_01/final_report.json；smoke=build/local/preboard/20261025_111612_829523_smoke；regression=build/local/preboard/20261025_111629_599017_regression（targeted_baseline含历史FAIL/负向日志与VCD）。说明sim/board/dcache_tb_revision.md。建议先审核/提交本地必要测试文件后再评估合并，远程68fafc8尚不含修订，本轮没有自动提交。下一接收V01/B02/B03，owner TBD。


## 2026-10-25 — 用户授权发布preboard测试修订（owner TBD）

用户在完整回归通过后明确指示“提交并合并到main”，覆盖前轮仅留本地待审的限制。发布前再次fetch，origin/main仍f88e178、功能分支HEAD68fafc8；15项本地改动均属于前两轮已交付的测试/板级交接与公共记录。正常smoke6 PASS、完整regression15 PASS的证据与当前测试输入SHA逐项一致，受保护文件原始字节不变，未发现凭据/私人home路径/大型生成物。仅对明确列出的文件暂存，执行cached diff检查后提交；main满足快进条件，发布结果以Git提交/远程引用及本轮交付为准。V01仍为in_progress，实板NOT_RUN和既有历史FAIL/负向证据继续保留。
## 2026-10-26 — CPU 流水线现状文档（只读，未改 RTL）

- 新增 `docs/cpu_pipeline_flow.md`：当前的 5 级顺序流水线底图（层级 / 逐级职责 / 控制优先级 / 冒险 /
  存储 / 多周期 / 可改点 / 测量方法）。行号按当前 `src/rtl`（`dcache.v` 611 行含 store buffer）核对。
- 结论边界：周期数均为代码推导（标「推」）；未跑仿真、未改 RTL、未碰时序。下一步应先复现
  `docs/board_bringup_plan.md:91` 的 16840 / 664 / 2559 三个基线再谈任何改进收益。owner TBD。

## 2026-10-27 — C 线 PYNQ overlay 通道与端到端骨架（M2/M3 代码就位，未上板）

分支 `feat/pynq-overlay`（自 `bd10697` 新建），未 commit/push；owner TBD。
任务号：Y01/Y02/Y03（板级部分 B03/C 线 M1–M3）。**所有板级数字仍为 not_measured。**

- **架构决策（必须记录）**：任务书 M2 原写"AXI-Lite 控制 + 共享 BRAM"。查证冻结 RTL 后不可行：
  (a) RV32 的外设访问全在 `bus_interconnect.v` 内部译码，没有通向 PL 边界的 MMIO 出口；
  (b) `dcache.v:52` 只有 `0x100x_xxxx` 是 cacheable，且全设计没有 d-cache 失效指令，
  所以"PS 直写共享 BRAM"必然读到旧 cache 行，靠 volatile/fence 不能修。改/复制 SoC 顶层又要
  在 WNS +0.087 ns 上重新签核。→ 采用 **方案 A'**：复用 RV32 已有的 UART MMIO（0x20000000）
  当 PS↔PL 数据通道，新增 `pynq_mbox.v` 在 PL 里做"串口的另一端"；冻结 RTL 一行未改。
  代价：PS 端到端 ≈200–300 µs（估算，未测），CPU cycles（20806/688/2570）不受影响。
- 新增 RTL（4 个文件，全部是新增）：`src/rtl/pynq/pynq_ctl.v`（控制/状态 AXI-Lite）、
  `pynq_mbox.v`（TX64B/RX256B FIFO + uart_tx/uart_rx + CNT）、`pynq_soc.v`（SoC+BRAM 封装）、
  `top_pynq.v`（三块组合的单模块顶层）。AXI 口带 `X_INTERFACE_*` 属性，BD 能自动识别为 AXI4Lite。
- 新增固件 `src/firmware/pynq_svc/`：单槽邮箱服务，帧格式与 `src/pynq/mailbox_protocol.md` 一致，
  另加两个服务帧 `Y01S`（能力/自检/mcycle，64B）与 `Y01E`（PS 下发 epoch，20B）。
  SW 模式直接 `#include ascon/ascon_c/aead/aead.c`（与 host golden 同一份参考），
  ISE 模式用 custom-0 置换指令，HW 模式走 ascon_mmio，三种模式开机各跑 6 项官方 KAT 自检。
- 新增 Python：`src/pynq/pynq_transport.py`（Transport 实现：MMIO、帧解析、批量压入、
  绝对 deadline、epoch/ACK 语义）、`test_pynq_transport.py`（13 项寄存器级模型测试）、
  `make_pynq_profile.py`（.hwh → navigator profile，并调用 `validate_overlay()` 自检）。
- **钉住 RTL 源集**：工作区 `soc_top.v`/`ascon_mmio.v` 已被 PUF 补丁改过，`key_hw_sel` 在
  `key_valid` 后无条件锁存，会让 ascon_mmio 忽略 CPU 写的 KEY → HW 模式 KAT 无法复现。
  故 `board/vivado_zynq7000_xc7z020_pynq/rtl_p0/` 存放 `8a86afd` 版这两个文件
  （其余 29 个 `src/rtl/*.v` 与 `8a86afd` 逐文件 git blob 相同，已全量核对）；keys 不进工程。
- 实测（本机）：`iverilog 14.0` 桥单元测试 **PASS**；`bash sim/pynq/elab_check.sh`
  42 文件整树 elaborate **PASS**（Xilinx IP 用 `sim/pynq/ip_stubs.v` 空壳）；
  `bash src/firmware/pynq_svc/build.sh` **exit 0**，text 46104 B/bss 336 B，custom-0 共 22 条
  （`0x200b`×1、`0x300b`×4），`pynq_svc.bin`=`dba0a861…`、`pynq_svc.coe`=`d7e9382f…`；
  `python src/pynq/test_pynq_transport.py` **13/13 PASS**；
  `python src/pynq/make_pynq_profile.py --selftest` **PASS**；既有
  `test_mailbox.py`(24 tests OK)/`test_navigator.py`/`golden_checker.py --backend mailbox --mode ise`
  (KAT 1089 PASS、TAMPER 4290) 无回归。
- **未验/阻塞**：Vivado 综合/实现/bit/hwh NOT_RUN（本机另有 Vivado PID 16988 在跑 PUF 版，
  按"同时只允许一个实现"未并发）；上板 KAT/PS 端到端时间/串口时序全部 not_measured；
  M_AXI_GP0 是否在厂家 FSBL 里使能未验证（若未使能 MMIO 会读回 0xFFFFFFFF）。
- 审计附带发现：`docs/freeze_checkpoint_20261027.md` §2 的 `src/rtl/*.v` 合并哈希
  `a323df37…` 用 6 种常见口径在 `8a86afd`/`f88e178` 上都无法复现；本轮独立口径为
  `8d4589e2…`（keys 合入后 `f4ad6ab6…`）。建议补记该哈希的计算口径，否则不能当复现凭据。
- 文档：`board/vivado_zynq7000_xc7z020_pynq/readme.md`（架构/位表/地址/GUI 建工程分步/
  验收/降级阶梯/风险）、`docs/pynq_bringup_m1.md`（M1 纯 GUI 分步 + 证据清单）。
- 下一接收：M1 起板（用户执行，按 `docs/pynq_bringup_m1.md` 交 boot log/env/jupyter 证据），
  然后 M2 建工程出 bit+hwh，再 `make_pynq_profile.py` 出 profile 过 `validate_overlay`。owner TBD。


## 2026-10-27 — 板级 IO 时序签核变体（B03/I08 的 IO 门禁）

owner TBD；分支 feat/board-bringup（期间并发工作线把工作区分支切到 feat/pynq-overlay，
并在 20:04 提交 `8623ea3` 改了 `src/rtl/keys/ro_puf_core.v`、`key_mmio.v`）。本轮未 commit/push，
未改 `src/rtl`、未改 `const.xdc`、未重建/覆盖三份冻结 bitstream。

- 新增 `board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/riscv_vivado_project.srcs/constrs_1/new/const_io.xdc`：
  7 个板级端口各给「`false_path`（与 RTL 一致的异步语义）+ 一条只用于覆盖计数的 IO delay」，
  另加两个虚拟参考时钟。`const.xdc` 原样（1 时钟 + 7 引脚 + reset false_path）。
- 关键负结果（本轮花时间最多的地方，全部带实测数字）：**"给异步 IO 编个宽松 input/output delay"
  在这块板上不可能成立**。Vivado 的 requirement 取"最小正边沿对"，只要 delay 数值 > 捕获时钟
  周期（本设计 10 ns）就为负，而负 requirement 会被当作**违反**报出来：
  变体A（参考端口 clk 20 ns、in 20/out 15）→ WNS −18.481 / TNS −5785.882 / 7972 失败；
  变体B（虚拟位时钟 8680.556）→ uart_rxd −17.623、uart_txd −27.105（req 仅 9.444/0.556）；
  变体D（8680.000，与 10 ns 网格可公度）→ uart_rxd −17.067、uart_txd −17.661（req 10.000）；
  变体E（LED 用 10 µs 虚拟时钟 + 20 ns 预算）→ led setup −13.888 / hold −18.452。
  另实测：`false_path` **不会**让 check_timing 的 `no_input_delay`/`no_output_delay` 豁免该端口
  （只加 false_path 时计数仍是 4/3），两者必须同时存在。
- 最终变体（false_path + 形式 delay）在钉住的源快照 `8623ea3` 上跑 synth+impl：
  `no_input_delay`/`no_output_delay` **4/3 → 0/0**，WNS **+0.152**、TNS 0、失败端点 **0/59513**、
  WHS +0.034，DRC **0 Error**（825 checks / 12 条 Warning 类别），TIMING-8 = 0。
  与同源同脚本、唯一差别是不加 const_io.xdc 的对照组**逐项相同**（WNS/TNS/端点数/最差路径全同），
  即可归因代价 = **0.000 ns**。
- 未达成项（不是 IO 问题，交 keys 线）：`no_clock`=10944、`unconstrained_internal_endpoints`=27312，
  100% 在 `u_soc_axi_top/u_soc_top/u_puf_key/u_puf/*`，根时钟脚 `ro_clk_div_reg[1]/Q` 被常量折叠为 HIGH
  （5824 个寄存器无时钟）；`TIMING-17` 1000 条同域；DRC `UTLZ-3` 报 `pb_ro_puf` 超容
  （CARRY4 需 1681 > 1470、Slice 需 2707 > 1470）。上述在"无 IO 约束"对照组里同样存在。
- 证据：`docs/io_timing_signoff.md`（约束推导/四种被否写法/判据/复现命令）、
  `build/reports/io_sta_20261027/{io,noio,io_clkframe,noio_rtl_bd10697}/`、
  `build/local/io_sta_20261027/`（工程副本、钉住源快照、STA 探针日志）、
  `build/{build_io_sta.tcl,collect_io_sta_results.py,collect_applied_constraints.tcl}`。
  三份冻结 bitstream 哈希复核未变：sw `f4233827…`、ise `f85eb1a6…`、hw `2f6f2469…`。
- 局限：板级真实 IO 延迟 **not_measured**（无示波器/眼图/环回抖动）；本轮不产出 bitstream，
  加约束后的布线未上板验证；`+0.152` 与 P0 的 `+0.087` 之差**不能**归因于 IO（源集不同 + P&R 波动）。
  下一接收：B03（板级 IO 实测 / PYNQ）、keys 线（RO 域 no_clock 与 pblock 超容）、owner TBD。
