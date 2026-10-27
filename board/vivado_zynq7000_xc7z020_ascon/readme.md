# vivado_zynq7000_xc7z020_ascon — 上板工程（B03/B04/C03/V01）

2026-10-27；owner TBD。本目录是**目标板的独立 Vivado 工程**，不动
[vivado_zynq7000_xc7z020_baseline](../vivado_zynq7000_xc7z020_baseline/readme.md) 的任何字节。

- 入口：`riscv_vivado_project/riscv_vivado_project.xpr`
- 工具：Vivado 2025.2　part：`xc7z020clg400-1`　top：`top_pl_bram`
- 源：仓库 `src/rtl/*.v`(31) + `src/rtl/ascon/*.v`(8，排除 `*_tb.v`)，**以仓库文件为准、不拷贝进工程**
  （XPR 里是 `$PPRDIR/../../../src/rtl/...` 相对引用）；`src/rtl/keys`（PUF）**未纳入**
- 约束：`riscv_vivado_project.srcs/constrs_1/new/const.xdc`（源自 baseline，U18 50 MHz / N16 复位 /
  T19,J15 USB-UART / H15,L15 LED / L14,K16 KEY）
- IP：`clk_wiz_0`(PLL 50→100 MHz, RESET_ACTIVE_HIGH) / `axi_bram_ctrl_0`(AXI4, 32b, 32768) /
  `blk_mem_gen_0`(32×32768, byte write, COE 可换)
- 策略：综合 `Vivado Synthesis Defaults` + 实现 **`Performance_ExploreWithRemap`**（**这个组合不能拆开改**，
  历史所有时序数字都是它测的）
- 目录历史：工程名原为 `first_time`，2026-10-27 重命名为 `riscv_vivado_project`（XPR 名 + 各
  `.runs/.cache/.hw/.sim/.ip_user_files` + 目录），重命名后已用 batch 打开验证（NAME/DIR/PART/TOP/
  3 IP/43 源文件/1 约束/COE 全对、runs 100% Complete）

## 板上结果（三套镜像，同板同 100 MHz）

| 版本 | COE | bitstream sha256（前 8 位） | warm 16B 加密 | 相对软件 |
|---|---|---|---|---|
| 软件 | `ascon_sw.coe` | `f4233827` | 20806 cyc | 1.0× |
| ISE（custom-0 置换指令） | `ascon_ise.coe` | `f85eb1a6` | **2570 cyc** | **8.10×** |
| MMIO（0x3000_0000 加速器） | `ascon_hw.coe` | `2f6f2469` | **688 cyc**（裸 crypto 103） | **30.2×** |

三轮实现均为 **WNS +0.087 ns / TNS 0 / 0 失败端点 / WHS +0.021 / 0 布线错误 / DRC 0 Error**；
KAT 全 PASS（MMIO 另有 16B 长度拒绝）。完整哈希与证据索引见
[上板冻结检查点](../../docs/freeze_checkpoint_20261027.md)。

## 换一套 COE 的完整动作（每次都要重综合+重实现）

1. **IP Sources → 双击 `blk_mem_gen_0`（Re-customize IP）→ Other Options → Coe File** 指向
   `riscv_vivado_project.srcs/sources_1/imports/bin_file/<目标>.coe` → OK
   ⚠ 必须在对话框里改；直接改 `.xci` 文件 Vivado 不认，会提示 "output products up-to-date" 拒绝重生成
2. 若仍提示 up-to-date：右键 IP → **Reset Output Products** → 再 Generate
3. **Generate Output Products** → `Out of context per IP` → Generate（1–2 min；属 OOC 综合，
   此时综合报告里 BRAM 显示 0 RAMB36 是正常的，IP 是黑盒）
4. 校验镜像指纹（`.gen/sources_1/ip/blk_mem_gen_0/blk_mem_gen_0.mif`）：
   sw 第 3 字 `…A197`；ise `…2197` + 第 4 字 `1E018193`；hw `…2197` + 第 4 字 **`81018193`**
5. **Run Synthesis → Run Implementation → Generate Bitstream**
6. bitstream 另存到 `build/local/board_bitstream/top_pl_bram_<版本>.bit` 并记 SHA-256（**别覆盖前一份**）
7. **Hardware Manager → Auto Connect → Program Device**（JTAG；先把串口工具开好，固件上电只打印一次）

## 板级连接

- 12V DC 供电；启动模式 **JTAG**（不要 QSPI/SD）
- JTAG：ATK-U18 下载器（FT232H）→ 排线 pin1 对齐板座；驱动用 Vivado 自带
  `data/xicom/cable_drivers/nt64/install_drivers.cmd`（管理员）
- 串口：板载 CH340 → 设备管理器 `USB-SERIAL CH340 (COMx)`；**115200 8N1 无流控**
- 底板 **P5 短接 3–5、4–6** 选 PL 串口（PS 控制台是 1–3、2–4，不能混）

## 生成物与 git

`.runs/`、`.cache/`、`.gen/`、`.hw/`、`.sim/`、`.ip_user_files/`、`.Xil/` 均已被
[.gitignore](../../.gitignore) 忽略；纳入版本库的只有 XPR、`.srcs` 里的 XCI/XDC/COE、本 readme
（`.srcs` 共 8 个文件 / 1.2 MB）。`imports/bin_file/freertos_demo.coe` 是 baseline 原件（自动被 Vivado
带进工程），本工程的实际初值以 `blk_mem_gen_0` 的 `Coe_File` 为准。

**关于增量 checkpoint（2026-10-27 清理）**：XPR 原先带 `IncrementalCheckpoint=$PSRCDIR/utils_1/...dcp`
且 `AutoIncrementalCheckpoint=true`，会在 `.srcs/utils_1/` 里生成约 2.9 MB 的 dcp。按 baseline 恢复审计的
同一口径（不把生成 dcp 纳入版本库）已删除该 File 条目、关闭自动增量并移出 `utils_1/`。
因此**本机 Design Runs 里 `synth_1`/`impl_1` 会显示 `Out-of-date`** —— 这是 run 完成后又编辑过 XPR
（重命名 + 去 checkpoint）导致的元数据漂移，**不代表设计变了**：磁盘上 `impl_1/top_pl_bram.bit`
的 sha256 仍是 `2f6f2469…`（与存档的 hw bitstream 逐字节相同），`impl_1` 的 timing/utilization 报告仍是
MMIO 轮（10-27 18:43）的签核产物。若在该工程里重建，Vivado 会重新跑综合，结果与三轮实测等价
（三轮 WNS 均 +0.087 / TNS 0 / 0 失败端点）。

## 未闭环

IO delay 未约束（`no_input_delay`/`no_output_delay` 为已知项，板级 IO 未签核）、板上 ISA 回归抽样、
PS7/PYNQ 链路（厂家 PYNQ 2.7.0 镜像缺失）、芯片丝印速度等级未现场核对、PUF/密钥子系统未纳入本工程。
