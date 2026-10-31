# PUF与DMA验证失败原因排查

- 工具：opencode；模型：claude-opus-5-5；会话：`ses_e7547f3b5ffdkn77Np6Fd50QbM`
- 开始：2026-10-30 10:51；用户提示 8 条；工具调用 198 次

## 用户提示（2026-10-30 10:51）

我认为当前的100Mhz，现在的目标仍是先完成skill的验证，然后先去尝试对于现在高速通道的尝试，因为他已经在100Mhz收敛，我来检查当前对于PUF和DMA为什么没过的检验。之前我记得加入PUF已经通过了，为什么现在又不通过了呢

<details><summary>工具调用 3 次</summary>

- `shell` git status --short; git log --oneline -15
- `read` tasks/release_plan_20261101.md
- `grep` project_log/actual_progress.md

</details>

<details><summary>工具调用 2 次</summary>

- `read` docs/advanced_offline_status_20261030.md
- `read` docs/skill_test_guide_20261030.md

</details>

<details><summary>工具调用 3 次</summary>

- `read` data/advanced/puf_soc/validation_20261030.md
- `read` src/rtl/keys_v2/synchronous_timing_20261030.md
- `read` project_log/actual_progress.md

</details>

<details><summary>工具调用 1 次</summary>

- `grep` data/advanced/dma_cpu

</details>

<details><summary>工具调用 2 次</summary>

- `read` data/advanced/dma_cpu/vivado_20261030_025251/readme.md
- `read` data/advanced/dma_cpu/vivado_20261030_015408/readme.md

</details>

<details><summary>工具调用 1 次</summary>

- `glob` board/vivado_zynq7000_xc7z020_{puf_v2,dma_direct,pynq_dma_cpu}/verify*.py

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 board/vivado_zynq7000_xc7z020_puf_v2/verify_delivery.py; "exit=$LASTEXITCODE"

</details>

<details><summary>工具调用 1 次</summary>

- `glob` **/verify_direct_evidence.py

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 build/advanced/verify_direct_evidence.py; "exit=$LASTEXITCODE"

</details>

<details><summary>工具调用 1 次</summary>

- `grep` .

</details>

### 模型回答（2026-10-30 10:52）

结论：**功能上没有退步。** 之前说"PUF 通过"和现在说"PUF/DMA 没过"，判断的不是同一件事，用的也不是同一个设计。

刚才重跑了 `python -X utf8 board/vivado_zynq7000_xc7z020_puf_v2/verify_delivery.py`，exit 0，10 项检查全部为 true。但输出里同时写着 `"board": "NOT_RUN"` 和 `"timing_signoff": false`，"没过"指的就是这两项。

## PUF：之前通过的是旧版，现在检查的是 v2

| | 之前"通过"（10-27，keys v3） | 现在（PUF v2 SoC，10-30） |
|---|---|---|
| 设计 | 旧 `src/rtl/keys/` 集成在原 SoC 里 | 新 `src/rtl/puf_soc_v2/`：加了内部 key AEAD、错误关闭、超时、健康检查、小镜像认证，还有私有 128KiB BRAM |
| 通过的依据 | 实板 enroll/reconstruct，quality 128/128 | 仿真全部通过（Icarus 2 种模式、XSim 4 种配置）+ 生成了 bit |
| 有时钟约束的路径时序 | +0.023ns（keys_sta_20261025_mmio2） | 首次布线 −0.249ns，布线后物理优化到 +0.009ns |
| RO 振荡环 | `no_clock 10930`，当时就没签核 | 7424 个无时钟引脚、19712 个未约束端点，同样没签核 |
| 上板 | 已测 | 还没测 |

所以 v2 没过的原因有三个：

1. **新 bit 还没上过板。** 旧版的板测结果不能拿来证明 v2。
2. **时序签核的标准变严了，但问题本身旧版也有。** RO 振荡环没有时钟约束，这是旧版就存在的；当时只是把它记为"已知限制"，结论仍写了 PASS。v2 把同样的问题明确定为 `STRUCTURAL_DIAGNOSTIC_ONLY`（只能当结构诊断用），不算正式签核。
3. **v2 规模大了一倍多，100MHz 下余量几乎为零。** 资源从约 17k 涨到 39077 LUT（旧数字 16934 来自 PUF 版 impl 报告）。新的关键路径是 dcache 的 `bus_addr_r[23]` 到 PUF 的 `input_data[82]/CE`，10 级逻辑。靠物理优化才拿到 +0.009ns，这个余量很脆弱。

## DMA：两个变体的结果不一样

- **HW_DIRECT（"高速通道"）在 100MHz 过了**：WNS +0.345 / WHS +0.031，no_clock 和未约束端点都是 0，DRC 0 个 Error、0 个 Critical。候选文件在 `data/advanced/dma_direct/vivado_20261030_024214/candidate/`。你说的"已经在 100MHz 收敛"就是这个。
- **CPU-DMA 在 100MHz 不过**，记录在 `data/advanced/dma_cpu/vivado_20261030_025251/readme.md`：
  - 第一版其实过了 100MHz（+0.144），但它的 PS DDR/FIXED_IO 没有引到顶层端口，日志里有 `Netlist 29-160` critical warning，所以作废。
  - 把端口正确引出后，布局变了，结果是 **WNS −0.046ns**，12 个端点失败。
  - 最差路径在没改动过的 CPU 里：`id_ex rs1` → 地址加法 → dcache tag 查找 → `captured_addr/CE`。其中 72% 是布线延迟，`address[4]` 的扇出是 367。
  - 试过 `phys_opt AggressiveExplore`，没有任何改善。所以最后改成真实的 80MHz FCLK 出了候选（WNS +0.601），没有通过修改约束来冒充 100MHz 过了。

## 建议顺序

1. **先按 `docs/skill_test_guide_20261030.md` 做 Skill 验证。** 这一步不依赖 PUF 和 DMA。
2. **高速通道用 HW_DIRECT 的 100MHz 候选**，按 `docs/advanced_board_handoff.md` 的顺序做实板 smoke、KAT 和恢复测试。CPU-DMA 用 80MHz 版本，或者先不上。
3. CPU-DMA 要回到 100MHz，就得改 dcache 的 RTL，比如复制 `address[4]` 的驱动、拆开 tag 查找到 CE 这条路径。这会动到生产 CPU，需要重新做全量回归，不建议在 11-01 冻结前做。
4. PUF v2 上板前要清楚：它的余量只有 +0.009ns，RO 也没签核。如果只是要展示，旧版 v3 已有实板日志，可以直接用。

另外，`build/advanced/verify_direct_evidence.py` 需要 `--implementation/--vendor-test/--rtl-test/--lifecycle/--output` 这几个参数。日志里没记录当时的调用参数，所以这次没有重跑。如果你要我按 `data/advanced/dma_direct/` 下的目录补上参数重验，我可以接着做。

## 用户提示（2026-10-30 10:54）

我想问这几个V2和之前的版本区别的意义是什么

<details><summary>工具调用 1 次</summary>

- `read` docs/dma_puf_implementation_plan.md

</details>

### 模型回答（2026-10-30 10:54）

这几个 V2 都不是为了让指标更好看，而是为了补上旧版里几处**说法上站不住的地方**。依据是 `docs/dma_puf_implementation_plan.md` 第 1 节列出的缺口，那些缺口是对照旧代码查出来的。

## PUF v2 对比旧版 keys v3（已上板那版）

| 旧版的问题 | 会导致什么 | v2 怎么改 | 意义 |
|---|---|---|---|
| 采样超时（watchdog）后**强制 done**，没有错误输出 | 可能把上一次的旧 raw 当成新结果发出去，并显示"成功" | 增加明确的采样错误和事务新鲜度；核心时钟域另设截止时间，RO 时钟停了也能报错退出 | 出错时报失败，而不是悄悄沿用旧值 |
| 无 helper 或不匹配时**退化成只用 DNA 生成 key** | DNA 能读出来，这样的 key 不是秘密 | 正常模式禁止这种退化，失败就拒绝做 AEAD | 能说"失败即关闭"（fail-closed） |
| REF/RAW/MASK/DNA 都能从 MMIO 读出，派生过程又是确定的 | 别人能直接算出 key，"key 不可读"实际不成立 | 正常模式和诊断模式的 MMIO 分开，正常模式不导出 | 正常模式下读不到这些原始数据。这还不等于完整保密（helper 方案尚未定） |
| 板上只检查状态位 quality=128 | 没证明这个 key 真被拿来用了 | 由内部 key 直接驱动 Ascon AEAD，检查重建前后同输入得到同样的 CT/tag，坏 tag 会被拒绝 | 证明了"key 被实际使用"，而不只是"状态显示 OK" |
| helper 放在易失寄存器，断电就丢 | 跨上电重建没法测 | helper 绑定版本、设备、构建、参数后持久化（诊断用） | 为跨上电重建测试铺路 |
| 没有使用场景 | — | 加入 1–16B 镜像认证演示 | 只是演示，不算安全启动 |

**一句话：** 旧版证明的是"PUF 能出稳定的位"，v2 想证明的是"PUF 能**安全地**当 key 用"。代价是电路多了一倍多，时序余量只剩 +0.009ns，而且还没上板。

## DMA 两个变体对比原 PYNQ 主线

原主线的数据路径是 PS → AXI-Lite 字节 FIFO → UART → RV32。Python 每次按字节访问，单次调用约 4.3–5.2ms，瓶颈在**传输**上，不在算法上。另外 HW 模式只能处理 ≤16B 的单块消息。

| 变体 | 改了什么 | 意义 | 局限 |
|---|---|---|---|
| **CPU-DMA**（80MHz 候选） | 用 AXI DMA 加上 RV32 可直接访问的不缓存端点，替代 UART 字节通道；SW/ISE 支持到 32B | 去掉逐字节和串口这个瓶颈，三种模式仍在**同一颗 CPU** 上比较，和主线叙事一致 | CPU 仍要搬运数据；100MHz 卡在原 CPU 的 dcache 路径上 |
| **HW_DIRECT**（100MHz 收敛） | DMA 直接接一个新的**多块** Ascon AEAD 核，PT/AD 各支持 0–1024B；解密认证通过前不输出明文 | 第一次在硬件上做标准的多块消息，而不是把消息切成 16B 再拼起来冒充；也是真正的"高速通道" | 不经过 RV32，所以是独立加速器，**不是 ISE**，不能和 CPU 周期混在一起比较 |

## 对 11-01 提交有什么用

- 已经上板验证过的主线（PYNQ 三种模式 + 旧 PUF v3 板测日志）**不受影响**，仍然是主要成果。
- 这些 V2 都还没上板，只能写成"离线实现与仿真已完成"的扩展工作。它们的价值在于能明确说出旧版哪里不足、新版怎么补上。
- 如果只能挑一个去上板，**HW_DIRECT 最值得做**：时序干净（100MHz、无未约束路径），也最能体现"高速"和"多块标准 AEAD"这两点。PUF v2 的时序余量太小、RO 没签核，上板的风险和收益都不如它。

## 用户提示（2026-10-30 11:01）

今天我们发现之前做的测试中PUF并没有接入，所以我们准备重跑测试，我让他直接进行PUF-V2的测试，加上这个高速通道的测试；所以你需要直接给一个他们结合在一块的版本，你先给我说一下你的思路，我确认后，你进行操作并提交推送到main中

<details><summary>工具调用 1 次</summary>

- `shell` Get-ChildItem board/vivado_zynq7000_xc7z020_puf_v2, board/vivado_zynq7000_xc7z020_dma_direct -File | Select-Object Directory,Name,Length | F

</details>

<details><summary>工具调用 4 次</summary>

- `read` board/vivado_zynq7000_xc7z020_puf_v2/setup.tcl
- `read` board/vivado_zynq7000_xc7z020_dma_direct/setup.tcl
- `read` board/vivado_zynq7000_xc7z020_puf_v2/readme.md
- `read` board/vivado_zynq7000_xc7z020_dma_direct/readme.md

</details>

<details><summary>工具调用 2 次</summary>

- `grep` data/advanced/puf_soc
- `read` board/vivado_zynq7000_xc7z020_puf_v2/capture.py

</details>

<details><summary>工具调用 1 次</summary>

- `grep` .

</details>

<details><summary>工具调用 2 次</summary>

- `read` docs/advanced_board_handoff.md
- `grep` src/pynq/dma_transport.py

</details>

<details><summary>工具调用 2 次</summary>

- `grep` board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py
- `read` board/vivado_zynq7000_xc7z020_dma_direct/quickstart.md

</details>

<details><summary>工具调用 1 次</summary>

- `shell` foreach($d in 'data/advanced','src/rtl/keys_v2','src/rtl/puf_soc_v2','src/rtl/ascon_dma','board/vivado_zynq7000_xc7z020_puf_v2','board/vivad

</details>

### 模型回答（2026-10-30 11:02）

先说明一下改动思路，等你确认了再动手。规划前我先核对了这两个工程，发现**两个必须先告诉你的问题**。

## 先说发现的问题

1. **现有 PUF v2 的 bit 本身就有缺陷。** 它的 `setup.tcl` 没有把 PS 的 `FIXED_IO/DDR` 引到顶层端口，`impl_1.log` 里有一串 `Netlist 29-160` CRITICAL WARNING。CPU-DMA 第一版就是因为同样的问题作废的。也就是说，即便不合并，现有 `puf_v2/candidate/puf.bit` 也不该直接上板。合并版会修掉这一点。
2. **两个设计的地址冲突。** PUF 的 control 和 HW_DIRECT 的 engine 都放在 `0x40000000`，合并时必须重新分配。

## 合并思路（推荐方案 A：同一个 bit 里并排放两个子系统）

```
PS7 ─ GP0 ─ AXI 互连(4口) ─┬─ control  0x40000000  (PUF SoC 控制，ID 0x32554650)
                           ├─ mailbox  0x40001000  (PUF 自检 ASCII 日志)
                           ├─ engine   0x40010000  (HW_DIRECT 控制，ID 0x32414d44)  ← 从 0x40000000 移过来
                           └─ dma      0x40400000  (AXI DMA)
PS7 ─ HP0(64b) ← mem 互连 ← dma MM2S/S2MM ⇄ AXIS ⇄ engine(多块 Ascon，PT/AD ≤1024B)
soc = pynq_puf_soc_v2（RV32 + PUF v2 + 128KiB 私有 BRAM 固件），ro_clk = FCLK1 25MHz
FCLK0 = 100MHz 驱动其余全部逻辑；FIXED_IO/DDR 引到顶层端口
```

- **RTL 和固件一字不改**：keys_v2、puf_soc_v2、ascon_dma、keys_v2 固件 COE 都直接复用，只新建 BD 和构建脚本。目录是新的 `board/vivado_zynq7000_xc7z020_puf_dma/`，原有三个工程和 PYNQ release 都不动。
- **PUF 的 key 不送进 HW_DIRECT。** 两个子系统共用 PS，但功能上相互独立：HW_DIRECT 仍由主机提供 key，PUF 由内部 key 走自己的 AEAD 自检。要把 PUF key 接进 HW_DIRECT（方案 B），就得改 RTL、ABI 和安全语义，11-01 前做不完验证，所以不推荐。
- **上板测试**：新增一个统一入口 `board_test.py`，先校验 bit/HWH/manifest 的哈希，然后按顺序跑：
  1. PUF 自检。复用 `capture.py` 的逻辑，通过实例名 `control/mailbox` 访问，必须看到 `PUF_V2_TEST_PASS`。
  2. HW_DIRECT。复用现有 `bringup.py --control-ip engine --dma-ip dma --modes 4`，依次跑 smoke、1089 KAT 和 benchmark。
  
  每一步都输出原始 JSON/log，任何一步失败都返回非零。

## 构建与验证门禁

1. 运行 `prepare.py` 生成固件，用新的 Vivado 会话（2025.2，xc7z020clg400-1），然后综合、布线，用 `ring_ack.tcl` 确认 256 个环，最后出 reports。
2. 门禁条件：
   - 有时钟约束的路径 WNS/WHS ≥ 0；
   - DRC 0 Error / 0 Critical；
   - **没有 `Netlist 29-160`**；
   - HWH 中的地址、ID、时钟和上面的规划一致。
   
   RO 的 no_clock 问题照旧标注 `STRUCTURAL_DIAGNOSTIC_ONLY`，不会写成签核通过。
3. 离线回归：重跑 PUF SoC 的 XSim/Icarus 和 direct 的协议回归。源码不变，这一步用来确认没有退化。HWH 驱动契约检查改为针对新地址。
4. 打包 `candidate/`，包含 bit、hwh、COE、manifest 和哈希；同步更新 `actual_progress`、看板和交接文档。

**主要风险**：PUF v2 单独构建时 100MHz 余量只有 +0.009ns，再加上 DMA 约 5.6k LUT，**有可能不收敛**。不收敛时我只会尝试真实可行的实现手段（不同的 impl 策略、post-route `phys_opt`），不会修改约束来凑通过。

## 需要你确认的 4 点

1. **合并方式**：用方案 A（并排、PUF key 不接入 HW_DIRECT），可以吗？
2. **100MHz 不收敛时**：
   - (a) 把 FCLK0 整体降到真实的 80MHz 出候选，和 CPU-DMA 一样；
   - (b) 停下来报告给你再决定。
3. **提交范围**：合并版依赖的 `src/rtl/keys_v2`、`puf_soc_v2`、`ascon_dma`、固件、`src/pynq/dma_transport.py`、`build/advanced` 等目前都**还没被 git 跟踪**。要从 clone 复现，必须一起提交。另外，工作区里还有别人改过的 16 个已跟踪文档。我的建议是：
   - 提交合并版和它依赖的全部源码、脚本、文档；
   - 证据只提交新候选的 bit/hwh/manifest 和小的报告摘要；
   - **不提交** `data/advanced` 里的 DCP 等大文件（共 333MB，单个最大 26MB），也不提交各 `work/` 目录；
   - 那 16 个已跟踪的文档改动是否一起提交，由你决定。
4. **推送方式**：确认直接 push 到 `origin/main`（不强推；如果远端有新提交，先 fetch 再 rebase 或 merge，有冲突就停下来问你）。

你确认后我就开始。

## 用户提示（2026-10-30 11:04）

那我现在先不考虑V2版本，而是只进行PUF第一版和高速通道的测试，你给一个这两个测试的结合；因为队友中午还要去测试skill，我还是先确认一遍

<details><summary>工具调用 1 次</summary>

- `shell` git ls-files src/rtl/keys src/firmware sim/keys | Select-String -NotMatch "\.(o|bin)$"; git ls-files board | Select-String -Pattern "\.(tcl|

</details>

<details><summary>工具调用 3 次</summary>

- `grep` board/vivado_zynq7000_xc7z020_pynq/build.tcl
- `grep` src/rtl/soc_top.v
- `read` board/vivado_zynq7000_xc7z020_ascon/readme.md

</details>

<details><summary>工具调用 2 次</summary>

- `read` board/vivado_zynq7000_xc7z020_pynq/build.tcl
- `shell` git ls-files board/vivado_zynq7000_xc7z020_pynq src/pynq; Get-ChildItem build -File | Select-Object Name

</details>

<details><summary>工具调用 3 次</summary>

- `shell` git diff --no-index --stat board/vivado_zynq7000_xc7z020_pynq/rtl_p0/soc_top.v src/rtl/soc_top.v; git diff --no-index --stat board/vivado_zy
- `grep` src/firmware/keys_rv32
- `grep` src/firmware/pynq_svc

</details>

<details><summary>工具调用 1 次</summary>

- `shell` git diff --no-index board/vivado_zynq7000_xc7z020_pynq/rtl_p0/soc_top.v src/rtl/soc_top.v | Select-Object -First 80; Get-ChildItem src/rtl/p

</details>

<details><summary>工具调用 3 次</summary>

- `grep` src/rtl/pynq/pynq_soc.v
- `grep` src/rtl/pynq/pynq_mbox.v
- `shell` git diff --no-index board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v src/rtl/ascon/ascon_mmio.v 2>$null | Select-Object -First 5; Get-

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-ChildItem -Recurse -Include "*keys*.coe","*keys*.bin" -Path board,build,data,src -ErrorAction SilentlyContinue | Select-Object FullName,

</details>

### 模型回答（2026-10-30 11:06）

明白，这次不用 V2，只把 **PUF 第一版**和 **HW_DIRECT 高速通道**放进同一个 bit。下面是我核对完代码后的思路，你确认后我再动手。

## 先说清楚"之前 PUF 为什么没接入"

- 10-27 板测通过的 PUF 第一版，用的是**独立 JTAG 工程**：`top_pl_bram`、物理 CH340 串口、`src/rtl/soc_top.v`（带 `u_puf_key`/`key_mmio`），日志是 `uart_20261027_keys3.txt`。
- 后来的 PYNQ 主线 `build.tcl` 第 11–13 行**特意排除了 `src/rtl/soc_top.v`**，改用 `rtl_p0/soc_top.v` 和 `rtl_p0/ascon_mmio.v`。这两个文件就是不带 PUF 的版本。
- 所以 PYNQ 上做过的所有测试里，PUF 确实没有接入。

## 合并方案（RTL 和固件不改，只新建一个工程）

```
PS7 ─ GP0 ─ AXI 互连 ─┬─ pynq_ctl  0x40000000  （复位/状态/ID）
                      ├─ pynq_mbox 0x40001000  （CPU 的 ASCII 日志）
                      ├─ engine    0x40010000  （HW_DIRECT 控制，从 0x40000000 移过来）
                      └─ dma       0x40400000  （AXI DMA）
PS7 ─ HP0(64b) ← mem 互连 ← dma ⇄ AXIS ⇄ engine（多块 Ascon，PT/AD ≤1024B）
pynq_soc = RV32 + src/rtl/soc_top.v（PUF 第一版：256 RO + DNA + key_mmio，内部 clk/4 生成 ro_clk）
FCLK0 = 100MHz；FIXED_IO/DDR 引到顶层
```

- **PUF 部分**：复用 `pynq_soc.v`，只把源文件换成带 PUF 的 `src/rtl/soc_top.v`、`src/rtl/ascon/ascon_mmio.v` 和 `src/rtl/keys/*.v`。BRAM 初值直接用 10-27 板测通过的那份 `ascon_keys.coe`（keys_rv32 v3 固件），不重新编译。我已经确认过：这份固件只轮询 UART 状态位，波特率由硬件参数决定，所以输出可以直接经 mailbox 送到 PS。
- **约束**：沿用 `keys_ro_pblock.xdc` 和 `keys_ro_allow_loops.tcl`，但 pblock 的层次路径要改成 BD 里的实际路径。原文件用的是 `get_cells -quiet`，路径对不上时会静默匹配为空，所以构建时我会加一条检查：确认 256 个 RO 都真的落进 pblock。
- **HW_DIRECT 部分**：`src/rtl/ascon_dma/` 原样复用，只改 engine 的地址。
- **代价**：这个 bit 里的 CPU 跑的是 PUF 自检固件，**不是三模式服务**。PYNQ 三模式继续用原来的 release，两者不混。

## 板上测试（一个入口脚本，分两段）

新增 `board_test.py`：先校验 bit/HWH 的哈希，再下载 overlay，然后：

1. **PUF**：释放 CPU 复位，从 mailbox 收 ASCII。必须出现 `=== KEY SUBSYSTEM SELF-TEST ===` 和 `PASS key subsystem: enroll + reconstruct stable`。遇到 `FAIL`、超时或溢出都返回非零。判据和 10-27 板测完全一样。
2. **高速通道**：调用现有的 `bringup.py --control-ip engine --dma-ip dma --modes 4`，依次跑 smoke、1089 KAT，可选再跑 benchmark。

两段都保存原始 log/JSON，存到 `data/advanced/puf_dma/board_<日期>/`。

## 构建门禁

用新的 Vivado 2025.2 会话，策略和主线一致（`Performance_ExploreWithRemap`）。必须同时满足：

- WNS/WHS ≥ 0，DRC 0 Error / 0 Critical；
- 没有 `Netlist 29-160`；
- 1280 个 RO LUT 保留，并且都在 pblock 内；
- HWH 里的地址和 ID 符合上面的规划。

RO 采样域原本就有 no_clock 问题，这一点照旧写成"未签核"。

参考数据：PUF 第一版单独构建时 WNS +0.023，PYNQ 主线 +0.034，再加上 DMA（约 5.6k LUT）后**可能不收敛**。

**更正一点**：上一轮我说 `Netlist 29-160` 会导致不能上板，这个说法偏重了。已经上板通过的 PYNQ release，它的 `build.tcl` 同样没有引出 FIXED_IO/DDR，所以这更可能是规范问题，而不是功能上的致命问题。合并版照样会把它们引出来。

## 需要你确认

1. **方案**：按上面的方式合并成一个 bit，可以吗？还有一个更快的备选：今天不重新构建，**分两个 bit 依次测**。
   - PUF 用 10-27 的 JTAG 镜像，HW_DIRECT 用现有的候选 bit。
   - 两个都已经有实现证据，下午就能直接测；缺点是它们不在同一个 bit 里。
2. **100MHz 不收敛时**：
   - (a) 只尝试真实的实现手段，例如 `phys_opt`；
   - (b) 把整个设计降到真实的 80MHz；
   - (c) 停下来报告给你。
3. **提交范围**：提交新的合并工程目录、它依赖但还没被跟踪的 `src/rtl/ascon_dma/`、`src/pynq/dma_transport.py`、`board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py`，以及候选的 bit/hwh/manifest 和报告摘要。**不提交** DCP、`work/` 和 PUF V2 相关内容。其他人改过的 16 个已跟踪文档也**不提交**。确认后 push 到 `origin/main`，不强推；远端如果有新提交，先 fetch 再 rebase，有冲突就停下来问你。

另外，Vivado 构建预计要 40–60 分钟，正好不影响队友中午测 Skill。

## 用户提示（2026-10-30 11:08）

我想跟你确认一下，这里的高速通道带来的优化有什么，如果他对于我们的功能实现需要分开测试，为什么我们要加入这个高速通道呢

### 模型回答（2026-10-30 11:08）

你问到点子上了。直接说结论：**高速通道和 PUF 之间没有功能上的联系，硬把两者放进一个 bit，只是下载时少换一次文件，不会多出任何能证明的东西。**

## 高速通道实际带来什么

原来的 PYNQ 链路是：PS 用 Python 逐字节写 AXI-Lite FIFO → PL 内的 UART（6.25 Mbaud）→ RV32 → 软件/ISE/MMIO 计算 → 原路返回。

| 方面 | 原 PYNQ 链路 | HW_DIRECT | 这算优化吗 |
|---|---|---|---|
| 消息长度 | PT/AD 各 ≤16B | PT/AD 各 0–1024B，硬件里真正做多块标准 AEAD | **是功能扩展**：硬件模式第一次能跑完整的 1089 组 KAT（原 HW 只能跑 289 组） |
| 传输瓶颈 | 单次调用实测 4.262–5.216 ms，大部分耗在逐字节访问和串口上 | DMA 直接搬运 DDR 里的连续 buffer | 理论上会快很多，但**实际速度还没测**，现在给不出倍数 |
| 安全语义 | — | 解密时认证通过才输出明文；坏 tag 不返回任何明文 | 多块场景下的正确性保证 |
| 和 RV32 的关系 | 三种模式都在 RV32 上运行 | **完全绕开 RV32 CPU** | 对"RV32 + ISE 加速"这条主线**没有贡献** |

最后一行是关键。项目主线讲的是同一颗 RV32 上 SW、ISE、MMIO 三种实现的对比，HW_DIRECT 不经过 CPU，所以：

- 它不能提高 ISE 或 MMIO 的周期数据；
- 它的周期和吞吐只能单独列出，不能和 CPU 的 mcycle 放在一起比；
- 所以它天然就要单独测，这不是因为合并做得不好。

## 和 PUF 放在一起有什么意义

- 我刚才给的方案里，PUF 的 key **不会送进** HW_DIRECT，HW_DIRECT 仍然用主机提供的 key。两者只是共用 PS，测试也是分两段各自判定。
- 合并唯一的好处是只下载一个 bit。坏处是要新构建一个没验证过的 bit：时序有风险（PUF 单独构建时 WNS 才 +0.023），还要花 40–60 分钟构建，并且多出一套需要验收的证据。
- 只有一种情况合并才真正有意义：**PUF 派生的 key 直接在 PL 内驱动 HW_DIRECT，key 不出 PL**。这才是"设备绑定的高速加密"。但这要改 RTL、改 ABI、重新验证，11-01 之前来不及做扎实。

## 我的建议

1. **今天不要合并。**
   - PUF 第一版：在 PYNQ 上验证的话，我只建一个"PYNQ 主线 + PUF 第一版"的 overlay。它和主线是同一套 PS-mailbox 链路，修好的正是"之前测试里 PUF 没接入"这个问题。另一种做法是直接用 10-27 的 JTAG 镜像复测。
   - 高速通道：如果要展示，就用现有的 HW_DIRECT 候选单独测，它已经在 100MHz 收敛。
2. **高速通道是否值得在 11-01 前上板，取决于你们要不要讲"长消息/高吞吐"这个点。**
   - 要讲：单独测 smoke、1089 KAT 和 1024B 的吞吐，作为扩展展示。
   - 不讲：可以先不测，它不影响主线结论。

请你选一下：

- **A**：PUF 第一版接进 PYNQ（新 overlay，不加 DMA），高速通道用现有候选单独测；
- **B**：PUF 用 10-27 的 JTAG 镜像复测，高速通道单独测，今天不做任何新构建；
- **C**：只测 PUF，高速通道放到提交之后。

确定后我按选的方案出具体步骤，再动手。

## 用户提示（2026-10-30 11:11）

我认为A更好一点，至于其他的拓展我后续单独来修

<details><summary>工具调用 3 次</summary>

- `shell` git fetch origin; git status -sb | Select-Object -First 3; git log --oneline -3 origin/main
- `read` src/rtl/pynq/pynq_soc.v
- `read` build/keys_ro_allow_loops.tcl

</details>

<details><summary>工具调用 3 次</summary>

- `read` build/build_keys_sta.tcl
- `grep` src/rtl/top.v
- `grep` src/rtl/pynq/pynq_ctl.v

</details>

<details><summary>工具调用 2 次</summary>

- `grep` sim
- `read` sim/keys/run_keys_fw.sh

</details>

<details><summary>工具调用 2 次</summary>

- `read` sim/keys/tb_keys_fw.v
- `read` sim/pynq/run_service.py

</details>

<details><summary>工具调用 3 次</summary>

- `read` sim/pynq/tb_pynq_bridge.v
- `read` src/rtl/top.v
- `grep` src/rtl

</details>

<details><summary>工具调用 1 次</summary>

- `shell` git log --format="%h %ci %s" -- src/rtl/keys src/rtl/soc_top.v src/rtl/ascon/ascon_mmio.v src/firmware/keys_rv32 | Select-Object -First 12; 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' import hashlib,re,pathlib coe=pathlib.Path('board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/riscv_vivado_project.srcs/sources_1/

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 2 次</summary>

- `read` src/rtl/keys/ro_unit.v
- `shell` Get-ChildItem src/rtl/ascon -Name; Select-String -Path board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/riscv_vivado_project.xpr -Pa

</details>

<details><summary>工具调用 2 次</summary>

- `read` board/vivado_zynq7000_xc7z020_pynq/package_release.py
- `shell` Get-Content .gitignore | Select-String -Pattern "build|local|work|\.bit|data" ; git diff .gitignore

</details>

<details><summary>工具调用 1 次</summary>

- `write` board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl

</details>

<details><summary>工具调用 1 次</summary>

- `write` board/vivado_zynq7000_xc7z020_pynq_puf/puf_opt_pre.tcl

</details>

<details><summary>工具调用 1 次</summary>

- `shell` New-Item -ItemType Directory -Force build/local/pynq_puf | Out-Null; C:\Xilinx\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -log buil

</details>

<details><summary>工具调用 2 次</summary>

- `grep` sim/ascon/axi_slave_bram.v
- `read` sim/pynq/tb_pynq_svc.v

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-ChildItem C:\Xilinx\2025.2 -Directory | Select-Object Name; Get-ChildItem C:\Xilinx\2025.2 -Recurse -Filter vivado.bat -Depth 3 -ErrorAc

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-ChildItem C:\Xilinx\2025.2\Vitis -Directory | Select-Object Name; Get-ChildItem C:\Xilinx\2025.2\Vitis\bin -Filter vivado* | Select-Obje

</details>

<details><summary>工具调用 2 次</summary>

- `shell` Get-PSDrive -PSProvider FileSystem | Select-Object Root; foreach($r in (Get-PSDrive -PSProvider FileSystem).Root){ Get-ChildItem "$r" -Direc
- `grep` data/advanced

</details>

<details><summary>工具调用 1 次</summary>

- `shell` C:\ruanjian\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -log build/local/pynq_puf/build.log -source board/vivado_zynq7000_xc7z020_py

</details>

<details><summary>工具调用 1 次</summary>

- `read` sim/pynq/tb_pynq_svc.v

</details>

<details><summary>工具调用 1 次</summary>

- `write` sim/pynq_puf/tb_pynq_puf.v

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-Command iverilog,vvp -ErrorAction SilentlyContinue | Select-Object Source; iverilog -V 2>&1 | Select-Object -First 1

</details>

<details><summary>工具调用 1 次</summary>

- `write` sim/pynq_puf/run.py

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 sim/pynq_puf/run.py; "exit=$LASTEXITCODE"

</details>

<details><summary>工具调用 1 次</summary>

- `write` board/vivado_zynq7000_xc7z020_pynq_puf/board_test.py

</details>

<details><summary>工具调用 1 次</summary>

- `write` board/vivado_zynq7000_xc7z020_pynq_puf/package.py

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-Content build/local/pynq_puf/build.log -Tail 15

</details>

<details><summary>工具调用 1 次</summary>

- `write` board/vivado_zynq7000_xc7z020_pynq_puf/readme.md

</details>

### 模型回答（2026-10-30 11:17）

PUF 联合仿真已通过，Vivado 正在综合和实现中。等构建完成后我会继续做门禁检查、打包和提交。

### 模型回答（2026-10-30 11:38）

100MHz 下首轮实现 WNS = −0.135ns（其余门禁全过：DRC 0、RO 1280/1280 在 pblock 内、无 Netlist 29-160）。按约定只尝试真实的实现手段，不改约束。我并行试两条路：对已布线结果做 post-route 物理优化，同时用几种实现策略重新跑。

<details><summary>工具调用 2 次</summary>

- `write` board/vivado_zynq7000_xc7z020_pynq_puf/explore_impl.tcl
- `write` board/vivado_zynq7000_xc7z020_pynq_puf/postroute_physopt.tcl

</details>

<details><summary>工具调用 2 次</summary>

- `shell` C:\ruanjian\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -log build/local/pynq_puf/explore.log -source board/vivado_zynq7000_xc7z020_
- `shell` C:\ruanjian\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -log build/local/pynq_puf/physopt.log -source board/vivado_zynq7000_xc7z020_

</details>

<details><summary>工具调用 1 次</summary>

- `grep` build/local/pynq_puf/vivado/reports/timing_summary.rpt

</details>

### 模型回答（2026-10-30 11:38）

失败路径全部在原有 CPU 内（id_ex 前递 → dcache 写数据，9 级逻辑，布线占 82%），不在 PUF 逻辑里；加入 PUF 后布局变挤导致。两条优化尝试正在跑，结束后我继续。

### 模型回答（2026-10-30 11:50）

post-route 优化后仍为 −0.117ns，未收敛。剩下 4 种实现策略的重跑还在进行，等结果出来再定。

<details><summary>工具调用 1 次</summary>

- `shell` Get-Content build/local/pynq_puf/vivado/reports/explore_impl.txt -ErrorAction SilentlyContinue; Select-String -Path build/local/pynq_puf/exp

</details>

<details><summary>工具调用 2 次</summary>

- `write` board/vivado_zynq7000_xc7z020_pynq_puf/finalize_run.tcl
- `shell` C:\ruanjian\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -log build/local/pynq_puf/finalize.log -source board/vivado_zynq7000_xc7z020

</details>

<details><summary>工具调用 1 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/finalize_run.tcl

</details>

<details><summary>工具调用 3 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/finalize_run.tcl
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/finalize_run.tcl
- `shell` C:\ruanjian\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -log build/local/pynq_puf/finalize.log -source board/vivado_zynq7000_xc7z020

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $r='build/local/pynq_puf/vivado/reports'; Select-String -Path $r/utilization.rpt -Pattern "^\| (Slice LUTs|Slice Registers|Block RAM Tile|DS

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $m = Get-ChildItem build/local/pynq_puf/vivado -Recurse -Filter blk_mem_gen_0.mif | Select-Object -First 1; $m.FullName; @" import re,sys mi

</details>

### 模型回答（2026-10-30 11:59）

BRAM 初值与 10-27 板测固件逐字一致。再给仿真 TB 做一次故障注入，确认它确实能判 FAIL：把 PUF 关掉，强制走 DNA-only 降级，TB 必须失败。

<details><summary>工具调用 1 次</summary>

- `shell` $o='build/local/pynq_puf/sim'; (Get-Content sim/pynq_puf/tb_pynq_puf.v -Raw).Replace('defparam u_top.u_soc_top.KEY_WINDOW = 256;','defparam 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $o='build/local/pynq_puf/sim'; $f=@(); $f += Get-ChildItem src/rtl/*.v | Where-Object Name -ne 'top_pl_bram.v' | ForEach-Object FullName; $f

</details>

<details><summary>工具调用 2 次</summary>

- `edit` sim/pynq_puf/tb_pynq_puf.v
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/board_test.py

</details>

<details><summary>工具调用 1 次</summary>

- `cactus_write` sim/pynq_puf/run.py

</details>

<details><summary>工具调用 2 次</summary>

- `write` sim/pynq_puf/run.py
- `shell` python -X utf8 sim/pynq_puf/run.py 2>&1 | Select-String -Pattern "====|TB_PYNQ_PUF|PASS key|FAIL|normal_pass" | ForEach-Object Line; "exit=$

</details>

<details><summary>工具调用 2 次</summary>

- `edit` sim/pynq_puf/tb_pynq_puf.v
- `shell` python -X utf8 sim/pynq_puf/run.py 2>&1 | Select-String -Pattern "====|TB_PYNQ_PUF|PASS key|FAIL|normal_pass" | ForEach-Object Line; "exit=$

</details>

### 模型回答（2026-10-30 12:45）

正常用例 PASS，故障注入用例被正确判为 FAIL 并返回非零。接下来更新打包脚本，让 `build.tcl` 直接使用实际收敛的那个策略，然后打包。

<details><summary>工具调用 4 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/package.py
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/package.py
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/package.py
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/package.py

</details>

<details><summary>工具调用 2 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $w='build/local/pynq_puf/vivado'; $lines=@("# Same synth_1 netlist, clocks and constraints; values = 'Post Routing Timing Summary' line of e

</details>

<details><summary>工具调用 1 次</summary>

- `shell` python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf/package.py; "exit=$LASTEXITCODE"; Get-ChildItem board/vivado_zynq7000_xc7z020_pynq_puf

</details>

<details><summary>工具调用 2 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/package.py
- `shell` python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf/package.py | Select-Object -Last 3; "exit=$LASTEXITCODE"; Get-Content board/vivado_zyn

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $h='board/vivado_zynq7000_xc7z020_pynq_puf/candidate/pynq_puf.hwh'; Select-String -Path $h -Pattern 'MEMRANGE .*INSTANCE="(pynq_ctl_0|pynq_m

</details>

<details><summary>工具调用 2 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/readme.md
- `shell` git check-ignore -v board/vivado_zynq7000_xc7z020_pynq_puf/candidate/pynq_puf.bit board/vivado_zynq7000_xc7z020_pynq_puf/candidate/pynq_puf.

</details>

<details><summary>工具调用 1 次</summary>

- `read` project_log/actual_progress.md

</details>

<details><summary>工具调用 1 次</summary>

- `edit` project_log/actual_progress.md

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-ChildItem board/vivado_zynq7000_xc7z020_pynq_puf, sim/pynq_puf -Recurse -Directory -Filter __pycache__ | Remove-Item -Recurse -Force; gi

</details>

<details><summary>工具调用 1 次</summary>

- `shell` git diff --cached --check -- . ':(exclude)board/vivado_zynq7000_xc7z020_pynq_puf/candidate/reports' ':(exclude)*.coe' ':(exclude)*.hwh'; "sr

</details>

<details><summary>工具调用 1 次</summary>

- `shell` git check-attr -a board/vivado_zynq7000_xc7z020_pynq_puf/candidate/pynq_puf.hwh board/vivado_zynq7000_xc7z020_pynq_puf/candidate/ascon_keys.

</details>

<details><summary>工具调用 1 次</summary>

- `shell` git ls-files "*.gitattributes" ".gitattributes"; Get-Content board/vivado_zynq7000_xc7z020_pynq/release/.gitattributes -ErrorAction Silently

</details>

<details><summary>工具调用 1 次</summary>

- `shell` git status --short .gitattributes; Add-Content -Path .gitattributes -Value "`n# PYNQ + PUF v1 candidate: bytes are pinned by candidate/sha25

</details>

<details><summary>工具调用 1 次</summary>

- `shell` @' import subprocess,hashlib base='board/vivado_zynq7000_xc7z020_pynq_puf/candidate/' for line in open(base+'sha256sums.txt'):     h,n=line.

</details>

### 模型回答（2026-10-30 12:47）

Staged 内容的哈希与 `sha256sums.txt` 全部一致。提交前先确认远端没有新的提交，然后再 commit 和 push。

<details><summary>工具调用 1 次</summary>

- `shell` git fetch origin; git rev-parse HEAD origin/main; git diff --cached --name-only | Measure-Object | ForEach-Object Count

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $msg = @" feat(pynq-puf): PYNQ overlay with PUF v1 self-test (100 MHz, board NOT_RUN)  The PYNQ release build uses rtl_p0/soc_top.v without 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` git push origin main 2>&1; "exit=$LASTEXITCODE"; git fetch origin; git rev-parse HEAD origin/main; git show --stat --format="%h %s" HEAD | S

</details>

### 模型回答（2026-10-30 12:48）

PUF 第一版已经接进 PYNQ，在 100MHz 下所有离线检查都通过了，已推送到 `origin/main`（提交 `56929b0`）。还没上板，需要队友在板上跑一次。

**之前为什么没测到 PUF：** PYNQ 正式版本构建时用的是 `rtl_p0/soc_top.v`，这个文件里没有 PUF。所以之前所有 PYNQ 测试都没覆盖 PUF。唯一一次 PUF 板测通过，是 10-27 在 JTAG 工程上做的。

**这次的做法：** 新建了独立工程 `board/vivado_zynq7000_xc7z020_pynq_puf/`，RTL 和固件一行没改。PUF 代码直接用 `src/rtl` 里 10-27 板测过的那份；固件用 10-27 通过的同一份镜像，我核对过它与 bit 里 BRAM 的初值逐字一致。原来的 PYNQ 正式版本和 JTAG 工程都没动。

| 检查项 | 结果 |
|---|---|
| 时序（100MHz） | WNS +0.208ns / WHS +0.016ns |
| DRC | 0 Error / 0 Critical |
| PS 引脚（Netlist 29-160） | 没有这个警告 |
| PUF 振荡环 | 1280 个全部保留，并且都在指定区域内 |
| 资源 | 18571 LUT / 32001 FF / 34.5 BRAM / 4 DSP |
| 仿真 | 真实 CPU + 固件 + PS 读日志通过；故意关掉 PUF 后，测试能正确报 `FAIL dna-only fallback` 并判失败 |

**时序是怎么收敛的：** 主线用的实现策略在这里差 0.135ns，没过。失败路径在原有 CPU 里，不在 PUF 里。我只换了 Vivado 的实现策略，时钟和约束都没改，最后选了余量最大的 `Performance_RefinePlacement`。所有尝试的结果都存在 `candidate/reports/explore_impl.txt`。

**这个 bit 的限制：**
- 里面的 CPU 只跑 PUF 自检，**不能跑三模式演示**。三模式还是用原来的正式版本。
- PUF 振荡环部分本来就没做时序签核，这和 10-27 那版一样。

**队友上板命令：**
```sh
sudo -E python3 board/vivado_zynq7000_xc7z020_pynq_puf/board_test.py \
  --candidate board/vivado_zynq7000_xc7z020_pynq_puf/candidate \
  --out data/pynq_puf/board_20261030_run1 --runs 5
```
5 次都打印 `PASS key subsystem: enroll + reconstruct stable`，并且每次 DNA 相同，才算通过，脚本返回 0。注意每次都会重新注册，所以这只能说明同一次上电内可重复，不能说明断电后还能恢复出同一个 key。

**没提交的部分：** 进度记录已经写进 `project_log/actual_progress.md`，但这个文件里还有其他人没提交的改动，所以我没把它放进这次提交。其他人的改动、PUF V2 和高速通道相关文件也都没提交，保持原样。

## 用户提示（2026-10-30 12:53）

我想问一下时序签核是什么意思，为什么要搞这个，怎么搞这个，一定要测延时吗，我感觉这样误差会很大啊

### 模型回答（2026-10-30 12:53）

## 时序签核是什么

FPGA 里每条"寄存器 → 组合逻辑 → 寄存器"的路径，信号都必须在下一个时钟沿到来之前稳定，这叫建立时间（setup）；时钟沿之后还要再保持一小段时间不变，这叫保持时间（hold）。

**时序签核（timing signoff）就是让工具把设计里每一条路径都检查一遍，确认在规定的时钟频率下全部满足这两个要求，并且没有漏掉的路径。** 报告里的 WNS +0.208ns 意思是：100MHz 下，最差的那条路径还剩 0.208ns 的余量。

## 为什么要做

时序不满足不一定会马上出错，但会出现很难查的问题：
- 偶发出错，跑一千次错一次；
- 换一块板、换个温度或电压就出错；
- 板上偶然跑通了，不能证明它一直能跑通。

所以不能只说"板上跑过了"，要靠签核说明"在器件规定的工作范围内都能正常工作"。

## 怎么做：不是在板上测延时

你担心的"测延时误差大"其实不会发生，因为签核**不靠测量，靠静态时序分析（STA）**：

- AMD 已经对每种器件做过表征，给出每个 LUT、每段走线在最坏工艺、电压、温度下的延时模型，Vivado 直接用这些模型计算。
- 计算本身是**故意偏保守的**。报告里的 `clock uncertainty -0.154`、`clock pessimism` 等项就是额外扣掉的余量。
- 设计者只需要告诉工具"这个时钟是多少 MHz"（写在约束文件里），工具就会把这个时钟域里的每一条路径都算一遍。

所以 CPU、总线这些 100MHz 部分**已经签核过了**，就是上面的 WNS/WHS 都 ≥ 0。

## 那哪里没签核？只有 PUF 的振荡环部分

问题出在环形振荡器（RO）上：
- RO 是故意做成组合环的电路，自己振荡，它的频率**不是我们设定的，而是由芯片本身决定**。这正是 PUF 的原理，每块芯片都不一样。
- RO 的输出直接驱动计数器的时钟端。Vivado 不知道这个"时钟"是多少 MHz，就没法分析，只能报告：
  - 5824 + 5120 个"没有时钟"的寄存器引脚；
  - 27312 个没有约束的引脚。
- 换句话说，这些路径不是"算出来不通过"，而是"根本没算"。

## 怎么补，以及为什么这里需要测量

这部分需要实测，但测的不是延时，而是 **RO 的频率范围**，而且只用来给 STA 提供一个上限：

1. **在板上读出计数值**：采样窗口是 65536 个时钟周期，所以 RO 频率 ≈ 计数值 ÷ 65536 × 100MHz（计数值是窗口内 RO 跳变的次数）。在所有 256 个 RO、多次采样中取最大值。
2. **加大余量**：比如在测得的最大值上再乘 1.3～1.5，用来覆盖温度、电压和不同芯片之间的差异。误差就是靠这个余量吸收的，不需要测得很准。
3. **把这个频率写进约束**：在每个 RO 输出上 `create_clock`，然后重新跑 STA，检查计数器在这个频率下能否满足要求。
4. **跨时钟域部分**：计数结果从 RO 域传回 100MHz 域时，需要确认已经做了同步，或者在计数停止后再读取，并逐项说明理由，不能一刀切加 false_path 把报告"刷绿"。

另一条路是**改设计，让计数器不依赖 RO 的频率**，例如用格雷码计数器加同步器，或者先停振再读数。这样 STA 主要只需检查同步结构。这属于后续的设计改进。

## 对现在这次提交的影响

- CPU、Ascon 和 PS 链路这些"真正承载功能"的部分已经签核，可以如实写。
- PUF 的 RO 部分照实写成"RO 采样域未签核，计数结果的可靠性以板测为依据"。这是 RO-PUF 原型很常见的状态，并不影响这次板测的意义。
- 如果后续要补签核，最省事的顺序是：先让固件在板上打印各个 RO 的计数值，然后按上面的步骤 1 到 3 补约束，重新跑一次 STA。

## 用户提示（2026-10-30 13:03）

请你按照这个循序更改一下，我尽量让我队友用最简单的方案来完成

<details><summary>工具调用 2 次</summary>

- `read` src/rtl/keys/ro_puf_core.v
- `read` src/rtl/keys/key_mmio.v

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 2 次</summary>

- `grep` src/rtl/keys/puf_key.v
- `grep` src/rtl/soc_top.v

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Start-Sleep -Seconds 240

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-Content src/firmware/keys_rv32/build.sh; Get-Command riscv*gcc* -ErrorAction SilentlyContinue | Select-Object Source; Select-String -Pat

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Test-Path C:\wenjian\toolchain\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-gcc.exe; Get-Command bash -ErrorAction SilentlyContinue 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $r='build/local/pynq_puf'; Select-String -Path $r/ct_try.rpt -Pattern "There (is|are) \d+" | ForEach-Object Line | Select-Object -First 3; $

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $r='build/local/pynq_puf'; Select-String -Path $r/ts_try.rpt -Pattern "^\s*(clk_fpga_0|ro_clk|ro_osc\d)\s+[-\d]" | ForEach-Object Line; Sele

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

<details><summary>工具调用 1 次</summary>

- `execute` 

</details>

### 模型回答（2026-10-30 13:19）

Now correct the gate in the two Tcl scripts so the check reflects physical placement, not just pblock assignment.

<details><summary>工具调用 1 次</summary>

- `read` board/vivado_zynq7000_xc7z020_pynq_puf/finalize_run.tcl

</details>

<details><summary>工具调用 2 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/finalize_run.tcl
- `read` board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl

</details>

<details><summary>工具调用 1 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $g='build/local/pynq_puf/vivado/reports/gate.txt'; Get-Content $g; "run=impl_5 strategy=Performance_RefinePlacement wns=0.208 whs=0.016 drc_

</details>

<details><summary>工具调用 3 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/package.py
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/package.py
- `shell` python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf/package.py | Select-Object -First 14; "exit=$LASTEXITCODE"; Get-Content board/vivado_z

</details>

<details><summary>工具调用 2 次</summary>

- `write` board/vivado_zynq7000_xc7z020_pynq_puf/ro_corner_sta.tcl
- `shell` C:\ruanjian\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -log build/local/pynq_puf/ro_sta.log -source board/vivado_zynq7000_xc7z020_p

</details>

<details><summary>工具调用 2 次</summary>

- `write` board/vivado_zynq7000_xc7z020_pynq_puf/pynq_puf_timing.xdc
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Move-Item build/local/pynq_puf/vivado build/local/pynq_puf/vivado_noroclk_20261030; Get-Process vivado* -ErrorAction SilentlyContinue | Sele

</details>

<details><summary>工具调用 1 次</summary>

- `shell` C:\ruanjian\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -log build/local/pynq_puf/build_roclk.log -source board/vivado_zynq7000_xc7z

</details>

<details><summary>工具调用 3 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/ro_corner_sta.tcl
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/ro_corner_sta.tcl
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/package.py

</details>

<details><summary>工具调用 1 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/package.py

</details>

### 模型回答（2026-10-30 13:29）

正在用新约束重新实现，大约 25 分钟。完成后会依次做三件事：检查门禁，在新的布线结果上跑 RO 分角分析，然后打包并更新文档。

### 模型回答（2026-10-30 13:49）

带 `ro_clk` 约束重跑后 WNS 为 −0.337ns。先看是哪条路径失败。

<details><summary>工具调用 1 次</summary>

- `shell` $r='build/local/pynq_puf/vivado/reports/timing_summary.rpt'; Select-String -Path $r -Pattern "^\s*(clk_fpga_0|ro_clk)\s+[-\d]" | ForEach-Obj

</details>

<details><summary>工具调用 3 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/explore_impl.tcl
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/explore_impl.tcl
- `shell` C:\ruanjian\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -log build/local/pynq_puf/explore_roclk.log -source board/vivado_zynq7000_xc

</details>

<details><summary>工具调用 1 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/finalize_run.tcl

</details>

### 模型回答（2026-10-30 13:50）

约束已经补好，4 种策略正在并行实现，大约 20 分钟。完成后我会选一个收敛的结果，用 `finalize_run.tcl` 跑门禁并生成 bit，再跑 RO 分角分析、打包，最后更新文档。

<details><summary>工具调用 1 次</summary>

- `shell` $w='build/local/pynq_puf/vivado/pynq_puf.runs'; foreach($i in 1..5){ $f="$w/impl_$i/runme.log"; if(Test-Path $f){ $s=(Select-String -Path "$

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Select-String -Path build/local/pynq_puf/vivado/pynq_puf.xpr -Pattern '<Run Id="impl_\d"' | ForEach-Object { $_.Line -replace '.*Id="(impl_\

</details>

<details><summary>工具调用 1 次</summary>

- `shell` C:\ruanjian\2025.2\Vivado\bin\vivado.bat -mode batch -nojournal -log build/local/pynq_puf/finalize_roclk.log -source board/vivado_zynq7000_x

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Remove-Item -Recurse -Force build/local/pynq_puf/ro_sta -ErrorAction SilentlyContinue; C:\ruanjian\2025.2\Vivado\bin\vivado.bat -mode batch 

</details>

<details><summary>工具调用 3 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $w='build/local/pynq_puf/vivado'; $map=@{impl_1='Performance_RefinePlacement (build.tcl)';impl_2='Performance_Explore';impl_3='Performance_E

</details>

<details><summary>工具调用 3 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/package.py
- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/package.py
- `shell` @" import re mif=open(r'build/local/pynq_puf/vivado/pynq_puf.gen/sources_1/ip/blk_mem_gen_0/blk_mem_gen_0.mif').read().split() coe=open(r'bo

</details>

<details><summary>工具调用 1 次</summary>

- `shell` $h='board/vivado_zynq7000_xc7z020_pynq_puf/candidate/pynq_puf.hwh'; Select-String -Path $h -Pattern 'MEMRANGE .*INSTANCE="(pynq_ctl_0|pynq_m

</details>

### 模型回答（2026-10-30 14:19）

Now the readme — rewrite it to match the new candidate, the pblock correction, and the signoff conclusions.

<details><summary>工具调用 1 次</summary>

- `write` board/vivado_zynq7000_xc7z020_pynq_puf/readme.md

</details>

<details><summary>工具调用 3 次</summary>

- `edit` board/vivado_zynq7000_xc7z020_pynq_puf/readme.md
- `edit` project_log/actual_progress.md
- `read` project_log/lessons_learned.md

</details>

<details><summary>工具调用 1 次</summary>

- `edit` project_log/lessons_learned.md

</details>

<details><summary>工具调用 1 次</summary>

- `shell` Get-ChildItem board/vivado_zynq7000_xc7z020_pynq_puf -Recurse -Directory -Filter __pycache__ | Remove-Item -Recurse -Force; git add board/vi

</details>

<details><summary>工具调用 1 次</summary>

- `shell` git log --oneline -4; git log --stat --format="%h %s" 56929b0..HEAD | Select-Object -First 25

</details>

### 模型回答（2026-10-30 14:21）

Others' commits don't touch my files. Committing and pushing.

<details><summary>工具调用 1 次</summary>

- `shell` $msg = @" fix(pynq-puf): sign off ro_clk domain, analyse RO counters, correct pblock claim  - pynq_puf_timing.xdc declares ro_clk = FCLK0/4 

</details>

<details><summary>工具调用 1 次</summary>

- `shell` git rev-parse --short HEAD; git rev-parse --short origin/main; Get-Process vivado -ErrorAction SilentlyContinue | Select-Object Id,StartTime

</details>

### 模型回答（2026-10-30 14:21）

PUF 现在分成三块：两块已经签核，振荡计数器那块不签核，而且只靠加约束或上板测量都签不下来，必须改 RTL。新版本已推送到 `origin/main`（提交 `5eb64a5`）。**队友那边不用多做任何事**，命令和之前一样，只是 bit 换成了新的。

## 原来的"先测频率"那一步，我换成了用器件模型计算

Vivado 布线后，每个振荡环由哪几个 LUT、走哪几段线都已经确定。我用 AMD 的延时模型逐个算出 256 个环的周期，再在慢角、快角下分别用该角下的环周期做检查，这样环和计数器的快慢会一起变。整个过程不需要上板，也不存在测量误差的问题。脚本是 `ro_corner_sta.tcl`，只做分析，不改 bit。

## 三块电路的签核状态

| 部分 | 状态 | 怎么做到的 |
|---|---|---|
| CPU / Ascon / 总线（100MHz） | ✅ 已签核：WNS +0.062ns / WHS +0.009ns | 换了实现策略，每种尝试都留了记录 |
| PUF 采样控制（25MHz 的 `ro_clk`） | ✅ **这次新签核**：WNS +16.4ns / WHS +0.146ns，和 CPU 之间的跨域路径也通过 | 只在 `pynq_puf_timing.xdc` 里声明它是 100MHz 的四分频，不需要任何测量 |
| 振荡环计数器（256 个 × 20 位） | ❌ 未签核 | 见下面 |

没有时钟约束的引脚从 10944 个降到 5120 个，剩下的只有振荡计数器。

**振荡计数器为什么不签核：**
- 慢角下最快的环约 368MHz，快角下约 1079MHz。
- 计数器 setup 差 0.69～1.16ns，hold 差 0.04～0.50ns。
- 根本原因在电路结构：每个计数器直接用 LUT 的输出当时钟，同一计数器内 20 个触发器之间时钟偏差有 0.5～1.5ns；而且 20 位计数器在 400MHz 以上就会溢出回绕。
- hold 违例和频率无关，所以就算上板测出真实频率，结论也不会变。
- 要修只能改 PUF 的 RTL：在每个环旁边加分频触发器、把使能信号同步到环的时钟域、把计数器放在环旁边。这等于一个新的、没验证过的 PUF，没有放进这次的版本。

## 需要更正我上一版的一个错误

上一版写的"1280 个 RO 全部在 pblock 内"是错的。我当时统计的是"分配给了这个区域"，不是"实际放在这个区域"。区域里的进位资源不够（需要 1687 个，只有 1470 个），Vivado 自动把约束放松了，实际只有 468 个在区域内，新版本是 585 个。这不影响功能，但说法不对。门禁脚本已改为分别统计这两个数，readme 和 manifest 已更正，这个教训也记进了 `lessons_learned.md`。

## 给队友

命令不变，bit 已经换成新的（SHA256 开头 `47da0494`）：
```sh
sudo -E python3 board/vivado_zynq7000_xc7z020_pynq_puf/board_test.py \
  --candidate board/vivado_zynq7000_xc7z020_pynq_puf/candidate \
  --out data/pynq_puf/board_20261030_run1 --runs 5
```
RTL 和固件都没改，仿真结论也不变（正常用例通过，故意关掉 PUF 的用例能正确判失败）。

## 写材料时的口径

可以写：CPU、Ascon、总线和 PUF 采样控制已经时序签核；PUF 能否正常工作以板测结果为准。
不要写："PUF 全部签核"或"PUF 在各种温度、电压下都可靠"。

`actual_progress.md` 和 `lessons_learned.md` 已经更新，但因为这两个文件里还有其他人未提交的改动，我没把它们放进这次提交。
