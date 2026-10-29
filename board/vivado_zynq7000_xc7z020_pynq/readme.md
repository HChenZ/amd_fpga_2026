# PYNQ overlay 工程（PS↔PL 已打通）

更新：2026-10-29；owner TBD。

**当前状态：**100 MHz overlay、同名 bit/hwh、服务固件、Python API、Notebook、
容量内三模式 KAT、warm benchmark 和 V03 错误/恢复门禁均已在正点原子领航者
ZYNQ7020 实板通过。最新证据见 [validation_20261029](validation_20261029.md)；
当前总状态见 [current_status](../../docs/current_status_20261029.md)。

下文 2026-10-27 的设计与 GUI 步骤保留为历史构建说明；其中“未构建/未上板/
not_measured”均已被上述实板结果覆盖。

对应任务：Y01（协议落地）、Y02（overlay）、Y03（Python 端到端）、M2/M3 里程碑。

---

## 1. 结论先行：通道为什么是 UART，而不是"共享 BRAM"

任务书 M2 原本写的是"AXI-Lite 控制寄存器 + 共享 BRAM"。查证冻结 RTL 后，这条路径在
**不改 `src/rtl`** 的前提下不成立，理由是硬的：

| 证据 | 位置 | 后果 |
|---|---|---|
| RV32 的外设访问全部在 `bus_interconnect` 内部译码（clint/uart/gpio/cpi/ascon），没有任何通向 PL 边界的 MMIO 出口 | `src/rtl/bus_interconnect.v:118-125, 350-364` | 想给 CPU 加一个"PS 可见寄存器窗口"，必须改这个文件 |
| 只有 `0x1000_0000~0x100F_FFFF` 被判为 cacheable | `src/rtl/dcache.v:52`（`cpu_addr_i[31:20] == 12'h100`） | 共享 BRAM 一定落在这个窗口内 → PS 改 BRAM、CPU 读到的可能是旧 cache 行 |
| 没有任何 d-cache 失效/清洗指令（只有 `fence.i` → icache flush） | `src/rtl/cpu_core.v:166-190`、`dcache.v` 全文 | 固件无法在两次事务之间把这条路径"洗"干净，靠 `volatile/fence` 是自欺 |
| P0 的时序余量只有 WNS **+0.087 ns** | `docs/freeze_checkpoint_20261027.md` §4 | 改/复制 SoC 顶层重新签核，风险与 7 天后的冻结不匹配 |

于是本轮采用**方案 A'：把 RV32 已有的 UART MMIO（`0x20000000`）当成 PS↔PL 数据通道**，
在 PL 里用新增的 `pynq_mbox.v` 实现"串口的另一端"。好处：

1. **冻结 RTL 一行不改**（只新增 3 个文件），P0 的三份 bitstream/时序/DRC 证据完全保留；
2. UART 是 `0x20000000` 的 **uncached MMIO**，天然与 PS 侧一致，不存在 dcache 陷阱；
3. 同一份固件既能跑 P0 的纯 PL 版（真实 UART 引脚），也能跑 PYNQ 版（PS 当对端），
   只有一条代码路径要维护；
4. 代价是**延迟/带宽**：6.25 Mbaud 下每字节约 1.6 µs，一次 16B 加密的 PS 端到端
   ≈ 200–300 µs（估算，**未实测**）。CPU cycles（20806 / 688 / 2570）不受影响，
   加速比仍按 cycles 计；PS 端到端时间必须单列，**不能混为一谈**。

如果后续评审坚持"PS 直接 MMIO 访问真正的 mailbox 窗口"，那就是方案 B：复制
`soc_top.v` + `bus_interconnect.v` 成 `*_pynq.v` 变体，加一个 uncached MMIO 窗口，
重新签核时序/DRC。这条路的成本写在 `board/atk_navigator_7020/interface_plan.md` 里，
本轮不选，因为会和 PUF 分支形成双份 SoC 维护。

## 2. 架构

```text
Jupyter (Python)
  └─ AsconHost → MailboxBackend → PynqUartTransport (src/pynq/pynq_transport.py)
        │  pynq.MMIO ×2
        ├─ CONTROL 窗口  ── pynq_ctl.v  : SOC_RESET / BUTTON / STAT(LED,RST)
        └─ MAILBOX 窗口  ── pynq_mbox.v : TX FIFO ─uart_tx─┐
                                                          │  (PL 内部，不经引脚)
                                     RX FIFO ─uart_rx──┐  │
                                                       ▼  ▼
                                        soC uart_rxd / uart_txd  (top.v 端口)
                                              ┌────────────────────────┐
                                              │ top (SoC, P0 同源集)   │
                                              │ cpu_core + dcache ...  │
                                              │ uart_ctrl 0x20000000   │
                                              │ ascon_mmio 0x30000000  │
                                              └───────────┬────────────┘
                                        M_AXI (仅 0x1000_0000 内存路径)
                                                          ▼
                                     axi_bram_ctrl_0 → blk_mem_gen_0 (128 KiB, pynq_svc.coe)
```

`pynq_svc` 固件（`src/firmware/pynq_svc/`）在 RV32 上跑一个单槽邮箱服务：
收 `Y01Q` 请求帧 → 按 mode 执行 SW/HW/ISE → 回 `Y01R` 响应帧，另有两个服务帧
`Y01S`（能力/自检/mcycle 上报）和 `Y01E`（PS 下发 epoch）。

## 3. 寄存器与地址

### 3.1 控制窗口 `pynq_ctl`（AXI-Lite，4 KiB）

| 偏移 | 名字 | 属性 | 位 |
|---:|---|---|---|
| 0x00 | CTRL | RW | [0] SOC_RESET（1=保持复位，**上电默认 1**）；[3:2] BUTTON→SoC 按键 |
| 0x04 | STAT | RO | [0] SOC_RST_N；[3:2] LED（来自 SoC）；[4] FCLK_RESET0_N |
| 0x08 | ID | RO | 0x514E5950（`'P''Y''N''Q'` 小端） |
| 0x0C | VERSION | RO | 1 |

### 3.2 邮箱窗口 `pynq_mbox`（AXI-Lite，4 KiB）

| 偏移 | 名字 | 属性 | 位 |
|---:|---|---|---|
| 0x00 | TXDATA | W | [7:0] 压入一个字节（FIFO 满时丢弃，先查 TXSTAT） |
| 0x04 | RXDATA | R | [7:0] 弹出一个字节（空读返回 0 且不弹出） |
| 0x08 | TXSTAT | RO | [15:0] 深度；[16] 满；[17] 空 |
| 0x0C | RXSTAT | RO | [15:0] 深度；[16] 满；[17] 空；[18] 溢出（粘滞） |
| 0x10 | RXCLR | W | [0] 清溢出 |
| 0x14 | TXFLUSH | W | [0] 清空 TX FIFO |
| 0x18 | CNT | RO | [15:0] PS 已压入字节数；[31:16] 已收到字节数（16-bit 回绕） |
| 0x1C | ID | RO | 0x4D424F58（`'M''B''O''X'` 小端） |

FIFO 深度：TX 64 B、RX 256 B；波特率分频 `BAUD_CNT_MAX = 16`（100 MHz → 6.25 Mbaud，
两端同一时钟域，无漂移；不改 `uart_rx.v` 的位采样结构）。

### 3.3 PS 物理地址（BD 地址编辑器里分配，示例）

| 窗口 | 建议地址 | 大小 |
|---|---|---|
| `pynq_ctl_0/S_AXI` | `0x4000_0000` | 4 KiB |
| `pynq_mbox_0/S_AXI` | `0x4000_1000` | 4 KiB |

**实际地址以导出的 `.hwh` 为准**；`src/pynq/make_pynq_profile.py` 直接解析 hwh，
不手抄地址。RV32 侧地址不受影响（帧只走 UART，不需 PS 地址翻译）。

### 3.4 时钟与复位

- `FCLK0 = 100 MHz` → AXI 互连 + `pynq_ctl` + `pynq_mbox` + SoC，**单一 100 MHz 域，无 CDC**；
  不再使用 P0 工程的 `clk_wiz_0`（PS 直接供时钟，少一个 PLL）。
- `FCLK_RESET0_N` → 本模块 `rst_n`；SoC 复位由软件 `CTRL[0]` 控制，释放后过 3 级同步器。
- 复位期间 `link_flush = SOC_RESET` 清空两侧 FIFO，保证每次复位后链路回到确定状态。

## 4. RTL 源集钉版（重要）

工作区 `src/rtl` 现在含 PUF/密钥子系统（`soc_top.v`、`ascon_mmio.v` 已被 keys 补丁改过）。
`soc_top.v` 里 `key_hw_sel` 在 `key_valid` 后**无条件锁存为 1**，之后 `ascon_mmio` 会忽略
CPU 写的 KEY、改用 PUF/DNA 密钥 —— 那样 HW 模式就无法用调用方给的 key 复现官方 KAT。

因此 PYNQ 工程钉住 **P0 上板签核的源集**（`docs/freeze_checkpoint_20261027.md` §2）：

- 除下面两个文件，其余 `src/rtl/**/*.v` 与签核版**逐文件 git blob 一致**（已用
  `git rev-parse 8a86afd:<file>` vs `git hash-object` 全量核对，只有这两个不同）；
- `rtl_p0/soc_top.v`、`rtl_p0/ascon_mmio.v` 取自 commit `8a86afd`（= 签核时的 HEAD 序列），
  sha256：`97d626ec433ae44d05bab56aa53e958634799623785a8a0580075e7d3edb5450` /
  `86400a92ca05d05133b6a965f1fea92f7b2cd5751ca9232ee9c9e428f190de8e`；
- 行尾是 LF（工作区是 CRLF），Verilog 语义无关；如果需要严格字节一致，用 `git show` 重新导出。

**PUF/密钥子系统是 P2，不进这个工程**：`src/rtl/keys/` 不加、`KEY_USE_PUF` 相关参数不传。

> 审计附带发现（未修改冻结文档）：`docs/freeze_checkpoint_20261027.md` §2 记录的
> `src/rtl/*.v` 合并哈希 `a323df37ac442bb6…`，用 hex 串联 / 原始字节串联 /
> `sha256sum` 行格式 / 文件名+哈希 等 6 种口径在 `8a86afd`、`f88e178` 两个提交上都无法复现；
> 本轮独立算出的口径是：31 个文件按路径排序、逐文件 sha256 后十六进制串联再 sha256 =
> `8d4589e22210774755df8a6c603ae595b44c562a8d988d9b6cf279c07bd2499d`（keys 合入后为
> `f4ad6ab6…`）。建议后续把该哈希的**计算口径**写进文档，否则它不能作为复现凭据。

## 5. 文件清单

新增/改动（全部是**新增**，冻结文件零修改）：

| 路径 | 作用 |
|---|---|
| `src/rtl/pynq/pynq_ctl.v` | 控制/状态 AXI-Lite 从机 |
| `src/rtl/pynq/pynq_mbox.v` | 字节 FIFO + PS 侧 uart_tx/uart_rx |
| `src/rtl/pynq/pynq_soc.v` | SoC + axi_bram_ctrl_0 + blk_mem_gen_0 封装（BD 里第三块） |
| `src/rtl/pynq/top_pynq.v` | 把上面三块组合起来的单模块顶层（备用拓扑） |
| `src/firmware/pynq_svc/{svc.h,svc_io.c,ascon_modes.c,main.c,build.sh,bin2coe.py}` | 邮箱服务固件 |
| `src/pynq/pynq_transport.py` | Transport 实现（MMIO + 分帧 + deadline） |
| `src/pynq/test_pynq_transport.py` | 寄存器级模型测试（13 项） |
| `src/pynq/make_pynq_profile.py` | hwh → navigator profile（自检 validate_overlay） |
| `sim/pynq/tb_pynq_bridge.v` | 桥 RTL 单元测试（iverilog） |
| `sim/pynq/{ip_stubs.v,elab_check.sh}` | Xilinx IP 空壳 + 整树 elaborate 检查 |
| `board/vivado_zynq7000_xc7z020_pynq/rtl_p0/*.v` | P0 源集钉版的两个文件 |
| `docs/pynq_bringup_m1.md` | M1 起板（纯 GUI 分步） |

## 6. 建工程（Vivado 2025.2 GUI，分步）

> 说明：本机已有另一个 Vivado 在跑（PID 16988，别的分支的 PUF 实现），**同时只允许一个
> Vivado 做实现**；等它结束再开始本工程的综合/实现。

前置（命令行，一次性）：
1. 编固件：`bash src/firmware/pynq_svc/build.sh` → 得到
   `build/local/pynq_svc/pynq_svc.{elf,bin,hex,coe}`。

Vivado 侧：
1. **Create Project** → 名字 `pynq_overlay`，位置
   `board/vivado_zynq7000_xc7z020_pynq/pynq_overlay/` → RTL Project（**不勾** Do not specify sources）
   → part 选 `xc7z020clg400-1`。
2. **Add Sources → Add Files**，加这批 `.v`（共 **42** 个，清单与 `sim/pynq/elab_check.sh` 完全一致）：
   - `src/rtl/*.v`：除 `top_pl_bram.v` 和 `soc_top.v` 之外的全部（29 个）
   - `board/vivado_zynq7000_xc7z020_pynq/rtl_p0/soc_top.v`
   - `src/rtl/ascon/*.v`：除 `ascon_mmio.v` 与 `ascon_aead_2_tb.v` 之外的全部（7 个）
   - `board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v`
   - `src/rtl/pynq/pynq_ctl.v`、`pynq_mbox.v`、`pynq_soc.v`、`top_pynq.v`（4 个）
   - `defines.v` 保持默认的 Verilog Header（`.vh/.v` 类型若被识别成 Design Source 需手动改回）
   - **不要加** `src/rtl/keys/`、`src/rtl/top_pl_bram.v`、`ascon_aead_2_tb.v`
3. **Create Block Design**（名字 `top`）：
   1. 加 IP `ZYNQ7 Processing System`（放进去后先 **Run Block Automation**）。
   2. 双击 PS7 → *PS-PL Configuration* → AXI Non Secure Enablement → **GP Master AXI Interface**
      勾 `M AXI GP0 interface`；
   3. 同一对话框 *Clock Configuration* → **PL Fabric Clocks** → 勾 `FCLK_CLK0`，频率填 **100** MHz；
   4. *Peripheral I/O Pins* 里的 UART0/SD0/ENET0 保持厂家镜像的既有配置即可（overlay 不改 PS 的
      引脚复用；这里只是让 PS7 IP 的地址表与 FCLK 频率和 FSBL 建立的状态一致）。
   5. 在 Sources 面板把 **`pynq_ctl`、`pynq_mbox`、`pynq_soc` 各拖进 BD 画布一次**
      → 得到 `pynq_ctl_0`、`pynq_mbox_0`、`pynq_soc_0` 三个独立模块实例。
      这样 `.hwh` 里一定各有独立的 MEMRANGE，正好对上 profile 的 control/mailbox 两个绑定。
      （`top_pynq` 是单模块备用拓扑，**不要**同时拖进同一个 BD，否则同一份逻辑出现两套。）
   6. **Run Connection Automation**（全选）：
      - `M_AXI_GP0` → 自动插 AXI Interconnect/SmartConnect → `pynq_ctl_0/S_AXI` + `pynq_mbox_0/S_AXI`
      - `FCLK_CLK0` → 三个模块的 `clk`；`FCLK_RESET0_N` → 三个模块的 `rst_n`
      - `pynq_soc_0` 没有 AXI 从口（它只连 BRAM），自动化不会碰它
   7. 手工连 5 根线（在 BD 画布上直接拖端点）：
      | 从 | 到 |
      |---|---|
      | `pynq_ctl_0/soc_reset` | `pynq_mbox_0/link_flush` |
      | `pynq_ctl_0/soc_rst_n` | `pynq_soc_0/soc_rst_n` |
      | `pynq_ctl_0/soc_button` | `pynq_soc_0/button` |
      | `pynq_soc_0/led` | `pynq_ctl_0/soc_led` |
      | `pynq_mbox_0/mbox_txd` | `pynq_soc_0/uart_rxd` |
      | `pynq_soc_0/uart_txd` | `pynq_mbox_0/mbox_rxd` |
   8. **Address Editor**：`pynq_ctl_0/S_AXI` = 4K @ `0x4000_0000`，
      `pynq_mbox_0/S_AXI` = 4K @ `0x4000_1000`（点 Assign All 后确认 Range=4K）。
   9. `top` BD → **Create HDL Wrapper**（Let Vivado manage）。

   > IP 注意：BD 里出现的 `axi_bram_ctrl_0` / `blk_mem_gen_0` 是 `pynq_soc.v` **内部**
   > 实例化的名字，Vivado 会把它们当黑盒。请先用 **Add Sources → Add Files 直接选 .xci**
   > （2025.2 的向导没有 IP 选项）把这两个 IP 加进工程，名字保持
   > `axi_bram_ctrl_0` / `blk_mem_gen_0`，端口才能对上：
   > - `axi_bram_ctrl_0`：AXI4 协议、Data Width 32、Address Width **17**、单端口、ID 宽度 1；
   > - `blk_mem_gen_0`：Single-port RAM、32 bit × **32768**、Byte-Write Enable、
   >   **Load Init File = true**、Coe File 指向 `build/local/pynq_svc/pynq_svc.coe`
   >   （先把 COE 拷到与工程同级可读的位置；COE 里的路径是相对 XCI 的）。
   > 或者更省事：直接把 `board/vivado_zynq7000_xc7z020_ascon/.../ip/` 下这两个 `.xci`
   > 拷到本工程的 `srcs/sources_1/ip/<ip>/`，再在 **Re-customize IP** 里把 Coe File 换成
   > `pynq_svc.coe`（与 `docs/freeze_checkpoint_20261027.md` §7 的换 COE 流程一致，
   > 必须在对话框里改，直接改文件 Vivado 不认）。
4. **Set as Top**：`top_pynq_wrapper`（如果用了 BD 方案）。
5. **Generate Bitstream**（综合策略保持 `Vivado Synthesis Defaults`，实现用
   `Performance_ExploreWithRemap`，与 P0 三轮数字可比）。
6. **File → Export → Export Hardware**（Include bitstream）→ 得到 `.xsa`；
   BD 的 `.hwh` 在 `pynq_overlay.gen/sources_1/bd/top/hw_handoff/top.hwh`，
   bit 在 `pynq_overlay.runs/impl_1/top_pynq_wrapper.bit`。
7. 把 **同 basename 的 .bit/.hwh 拷到同一目录**（例如 `build/local/pynq_ovl/top_pynq.{bit,hwh}`），
   然后生成 profile：
   ```sh
   python src/pynq/make_pynq_profile.py \
     --hwh build/local/pynq_ovl/top_pynq.hwh \
     --bit build/local/pynq_ovl/top_pynq.bit \
     --firmware build/local/pynq_svc/pynq_svc.elf \
     --firmware-id pynq-svc-v1 \
     --out board/vivado_zynq7000_xc7z020_pynq/pynq_profile.json
   ```
   成功输出 `validate_overlay: PASS` 才算 M2 的地址一致性验收通过。
8. 记录：tool version / part / top / IP 版本 / 约束 / 命令 / WNS / TNS / DRC / 资源，
   追加到 `docs/freeze_checkpoint` 风格的证据文件里（M2 产出）。

### 6.1 BD 拓扑（已定，不再留分叉）

用**三个独立模块实例**（`pynq_ctl_0` + `pynq_mbox_0` + `pynq_soc_0`）而不是单个
`top_pynq_0`，原因只有一个：PYNQ 的 hwh 解析对"一个 module 两条 MEMRANGE"的行为未经验证，
而 `navigator_backend.validate_overlay()` 要求 `ip_dict` 里存在 **两个不同名字**的
`phys_addr/addr_range` 绑定（`control` + `mailbox`）。三个实例能保证这一点。

`top_pynq.v`（单模块、双 AXI-Lite 从口）仍然保留在仓库里，作为纯 RTL/仿真入口和
"不想开 BD 时的备选顶层"；两者共用同一份 `pynq_ctl`/`pynq_mbox`/`pynq_soc`，
不存在两套逻辑。

## 7. 验证现状（本轮的实测命令与结果）

| 项 | 命令 | 结果 |
|---|---|---|
| 桥 RTL 单元仿真 | `iverilog -g2005 -o build/local/pynq/tb_pynq_bridge.vvp sim/pynq/tb_pynq_bridge.v src/rtl/pynq/pynq_ctl.v src/rtl/pynq/pynq_mbox.v src/rtl/uart_tx.v src/rtl/uart_rx.v && vvp ...` | **PASS**（ctl 寄存器/复位同步、8 字节双向回显含 0x00/0xFF/A5/7E、空读不弹出、CNT 计数、link_flush 清零） |
| 整树 elaborate | `bash sim/pynq/elab_check.sh` | **PASS**（42 个源文件，Xilinx IP 用 `sim/pynq/ip_stubs.v` 空壳；证明 `top_pynq→pynq_soc→top→soc_top→…` 的端口名/位宽全部对得上） |
| 固件交叉编译 | `bash src/firmware/pynq_svc/build.sh` | **PASS / exit 0**；text 46104 B / bss 336 B（< 128 KiB）；`pynq_svc.bin` sha256 `dba0a861debb3bd701200445b3ce6421618300fead9c0a61eb20e44845b1db2c`、`pynq_svc.coe` sha256 `d7e9382fbd49f898f3a47969575a5a6dea89981489c2e38ba667968dedc12e9b`（图像可复现；`.elf` 因构建元数据哈希每次不同，不当作指纹）。反汇编里 custom-0 共 **22** 条，其中 `0x200b`(p12)×1、`0x300b`(p8)×4 → ISE 指令确实进了二进制 |
| 固件 KAT/周期 | — | **not_measured**（需上板；SW/HW/ISE 的 KAT 自检在固件里，开机即跑） |
| Python 驱动 | `python src/pynq/test_pynq_transport.py` | **13/13 PASS**（寄存器级模型：KAT 字节穿透、篡改拒绝、17B 拒绝、小 FIFO 反压、文本噪音、超时、epoch 变化、ACK 纪律） |
| profile 生成 | `python src/pynq/make_pynq_profile.py --selftest` | **PASS**（合成 hwh 上 validate_overlay 通过；真实 hwh 待 M2） |
| 既有回归 | `test_mailbox.py` / `test_navigator.py` / `golden_checker.py --backend mailbox --mode ise` | 24 tests OK；KAT 1089 PASS / TAMPER 4290 |
| Vivado 综合/实现/上板 | — | **NOT_RUN**（另一个 Vivado 正在跑，未并发；且上板由用户点击） |

## 8. 降级阶梯（不许临场编）

| 卡在哪 | 交付到哪 | 报告里怎么写 |
|---|---|---|
| M3（邮箱跨 PS 跑不通） | M2：PS 控 reset/start + 从 `Y01S` 帧读 status/selftest/mcycle | PS 端到端 = not_measured；演示 payload 仍由 COE 预装 |
| M2（BD/地址/hwh 有问题） | 只证明"PYNQ 平台 + fpga_manager 装载 .bit 成功"（不需要 hwh） | P1 标未完成 |
| `ip_dict` 只出现一条窗口 | 按 §6.1(b) 把 `top_pynq.v` 拆成三个模块后重建 | 记录拆分前后 hwh 的 MEMRANGE 条数 |

## 9. 已知风险 / 未验证

1. **M_AXI_GP0 是否在厂家镜像的 FSBL 里使能**：我们的 overlay 只用 GP0 + FCLK0，不复位
   PS。若厂家 BOOT.BIN 的 PL 设计没使能 GP0，MMIO 会读回 `0xFFFFFFFF` 或挂死。
   诊断：`pynq.Overlay('xxx.bit')` 后读 `overlay.ip_dict` 与 0x00/0x08 的 ID 寄存器；
   不对就是 GP0 没通（届时需要厂家 base design 或自建 FSBL，属新阻塞）。
2. **PS7 IP 配置一致性**：本工程的 PS7 只用来给 GP0/FCLK0 提供地址和时钟约束，
   DDR/MIO 的配置**不参与** overlay 加载（bit 文件不重配 PS）。FCLK0 必须与 FSBL 建立的
   一致（100 MHz），否则时序分析的前提不成立。
3. **`.hwh` 里 module 的 MEMRANGE 条数**（§6.1）。
4. 串口链路的实际延迟/带宽、真实 FIFO 反压行为、PS MMIO 每次读写的耗时：全部
   **not_measured**，等 M2/M3 上板用 `CNT` 寄存器与 `time.monotonic()` 分别记录。
5. 固件的 ISE 路径依赖 `ascon_ise.v`（custom-0 0x0B）——与 P0 同源，未新增指令。
6. UDP/网络侧（Jupyter、SSH）带宽足够跑 200–300 µs 级事务，但未实测端到端时间分布。
