# 上板冻结检查点（V04 索引）— 2026-10-27

owner TBD。本文是**证据索引**，不是成果声明：每条数字都能追到本仓库内的文件或串口原始日志。
对应任务：B02/B03/B04（板级）、C03/C04/I07（板上 KAT 与 benchmark）、V01（板级抽样）、V04（冻结）。

## 1. 环境与身份

| 项 | 值 |
|---|---|
| 工具 | Vivado **2025.2**（SW Build 6299465，IP Build 6300035） |
| part / top | `xc7z020clg400-1` / `top_pl_bram` |
| 板卡 | 正点原子 领航者 ZYNQ7020（底板 V3.9 / 核心板 2V5），12V DC 供电 |
| RTL 基线 | git HEAD **f88e178**（工作区另有未跟踪的 `src/rtl/keys`、`sim/keys`、PUF 文档——**未参与本工程**） |
| 工程入口 | `board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/riscv_vivado_project.xpr` |
| 工程命名 | 原为 `first_time`，2026-10-27 重命名（XPR 名 + `.runs/.cache/.hw/.sim/.ip_user_files` + 目录），重命名后以 Vivado batch 打开验证通过（见 §6） |

## 2. 输入源哈希

| 对象 | 数量 | SHA-256 |
|---|---|---|
| `src/rtl/*.v`（顶层 31 个，含 `defines.v`） | 31 | `a323df37ac442bb6…`（按文件名排序后逐文件哈希再合并） |
| `src/rtl/ascon/*.v`（含 `ascon_aead_2_tb.v` 一个 TB） | 9 | `695886f6100e00ab…`（同上合并口径） |
| `const.xdc` | 1 | `01f639212f00fce073b373a470b559772797842fee9dcd394076499f5fcd42bf` |
| `clk_wiz_0.xci`（6.0 rev17） | 1 | `1b32fbd495699161d8100b05da48bf9e6af720bbf6ef1dfc22acfbeb431bd923` |
| `axi_bram_ctrl_0.xci`（4.1 rev13） | 1 | `a0c1cf38ec960d1fe945d06e60932894a4deefa22d97c01742c43e099a0cbb4f` |
| `blk_mem_gen_0.xci`（8.4 rev12） | 1 | `92b7beddd8ad702035bed6896f2a4a670ee2d6194d9cd9c7fe244626b992fb1d` |
| `riscv_vivado_project.xpr` | 1 | `4ffeb0344745ac842f53378341ea14374671ccc49725fff49a917fd419200f2f` |

工程上下文：综合固定 `Vivado Synthesis Defaults`，实现固定 **`Performance_ExploreWithRemap`**；
`clk_wiz_0` = PLL 50→100 MHz、`RESET_TYPE=ACTIVE_HIGH`（与 `top_pl_bram` 的 `.reset(~rst_n_raw)` 匹配）；
`blk_mem_gen_0` = 32 bit × 32768（128 KiB）、byte write、`Load_Init_File=true`。

## 3. 三份镜像与板级结果

| 版本 | BRAM 初值 COE (sha256) | bitstream (sha256) | 板上 warm 16B 加密 |
|---|---|---|---|
| 软件 | `ascon_sw.coe` `3dcd59a0…` | `f4233827e3005e115bb30e31e64a75a4487f9dfdd9efe2946d9c924b8ffb5c2e` | **20806 cyc**（1.0×） |
| ISE | `ascon_ise.coe` `7ef0b829…` | `f85eb1a63284059f5dbc785aa791d81c9a6f558a27843c2767d2414909144392` | **2570 cyc**（**8.10×**） |
| MMIO | `ascon_hw.coe` `3e464c48…` | `2f6f24692533941f902deb812cd7a61192a722b20d3f8536e466e46e4579c544` | **688 cyc** 端到端（**30.2×**）；裸 crypto **103 cyc** |

- 三份 bitstream 均为 4,045,687 B，且**两两不同**；存档于 `build/local/board_bitstream/`（不入 git）。
- 三版 KAT 全 PASS：软件版 6 组官方向量（empty/1B/16B/16B+AD/17B/32B）+ tamper reject；
  ISE 版（empty/1B/16B/16B+AD + dec round + tamper）；MMIO 版（同上 + **len reject**，16B 上限）。
- 板上/仿真（同 RTL f88e178 + xpack GCC 15.2.0）：软件 17353→20806（**+19.9%**）、
  ISE 2496→2570（**+3.0%**）、MMIO 670/99→688/103（**+2.7%/+4.0%**）。
  开销与访存密度成正比，解释见 `project_log/actual_progress.md` 2026-10-26/27 条目。

## 4. 时序与实现证据

| 轮次 | 策略 | WNS | TNS | 失败端点 | WHS | 布线 | DRC |
|---|---|---|---|---|---|---|---|
| 软件 / ISE / MMIO（三轮一致） | Performance_ExploreWithRemap | **+0.087 ns** | 0.000 | **0** / 55572 | +0.021 | 24610/24610，0 error | 0 Error / 0 Critical |

- 三轮综合资源一致：LUT 11266（as Logic）/ FF 15945 / DSP 4（顶层报表中 BRAM 因 IP 为黑盒显示 RAMB18 5）；
  实现后 placed：LUT 12426 / FF 16156 / RAMB36 32 + RAMB18 5 = 34.5 tiles / DSP 4。
- 最差路径三轮同为 `u_ascon_mmio/…/FSM_sequential_state_reg[3]/C → p12_in_reg[215]/D`。
- ⚠ **现存报告只对应 MMIO 轮**：`riscv_vivado_project.runs/synth_1/`（10-27 18:33）、
  `.../impl_1/`（10-27 18:43）是最后一次构建的产物；软件/ISE 两轮的报告已被后续重建覆盖，
  其 WNS/TNS/失败端点记录在 `project_log/actual_progress.md` 与当次 `vivado.log`。

## 5. 串口原始日志

| 文件 | 内容 | SHA-256 |
|---|---|---|
| `uart_20261026_sw_and_ise.txt` | 软件版 + ISE 版（XCOM 会话数据提取的可读文本，25 行） | `69c51d28d6e03d2e28008dd24b94e60b355054d19d1bfdffb914c9a7c7ce35e2` |
| `uart_20261027_mmio.txt` | MMIO 版（同法提取，22 行） | `bdeda7e4138108ec9b400a4d9f45264e9dadb3a51e1c8bcad94fb25c0c28a4ef` |
| `uart_sw_20261026.txt` | 软件版（XCOM "保存窗口"直接存盘，纯 sw） | `0a6485bd424feb9f16981ecd9f32a522ea9b0d499d7319bcb27ee0ee879f9758` |
| `xcom_raw_20261026.XDat` | XCOM 原始会话数据（含帧头字节，可回溯） | `ca033509c6c57bafb3e1ed50be813c22eccc5d5722d1d57366b07b431e55c80e` |
| `xcom_raw_20261027.XDat` | 同上（MMIO 轮） | `5aa335835aab6f00a56c1ffc1be8c949dd30f23cfd66e958ade1e18843b8f5ed` |
| `uart_20261027_keys3.txt` | PUF 密钥子系统（含 v2 抢跑失败段 + v3 通过段，31 行，已标注分段） | `ad634d898e216d7a029529069a99355800c4e1ef753c8a1b6c5f0880d88c4ba0` |
| `xcom_raw_20261027_keys3.XDat` | 同一捕获的原始字节（含首尾 0x00 与 CRLF，可回溯） | `3f85131638abdc425ee906210a0a505a9114f60e560e30398ac213cbf8fbfc7e` |

⚠ MMIO 版日志开头有约 2 行乱码（打开串口瞬间的帧错），banner 之后干净；`.txt` 是从 `.XDat`
去掉非打印字节后的可读版，两者可互相核对（原始文件保留，不修改）。

## 6. 重命名/清理后的工程自检（Vivado batch 实跑两次）

第一次（仅重命名，未动 checkpoint）：

```
CHECK NAME=riscv_vivado_project   DIR=.../board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project
CHECK PART=xc7z020clg400-1        CHECK TOP=top_pl_bram
CHECK IPS=axi_bram_ctrl_0 blk_mem_gen_0 clk_wiz_0          CHECK NIP=3
CHECK NFILES=43                   CHECK NCONSTR=1
CHECK COE=../../imports/bin_file/ascon_hw.coe              CHECK INCDIR=（空：所有 include 都在同目录内解析）
CHECK RUN synth_1 synth_design Complete! 100%
CHECK RUN impl_1  write_bitstream Complete! 100%
CHECK RUN blk_mem_gen_0_synth_1 synth_design Complete! 100%
```

第二次（再删掉 `utils_1` 增量 checkpoint 与 XPR 里的增量属性之后，同样的 43 源文件、3 IP、
1 约束、COE=ascon_hw 全部不变），但 `synth_1`/`impl_1` 变为 **`Out-of-date`**：
这是 run 完成后又编辑过 XPR 造成的元数据漂移，**设计输入没有变化**。判据是产物本身：
`.../impl_1/top_pl_bram.bit` 的 sha256 仍为 `2f6f2469…`（与存档的 MMIO 轮 bitstream 逐字节相同），
`impl_1` 的 timing/utilization 报告仍是 10-27 18:43 的签核产物。在该工程里重建会重新跑综合，
结果与三轮实测等价。

命令：`vivado.bat -mode batch -source build/local/check_project.tcl`（两次均 exit 0）。
备份：重命名前整目录备份于 `build/local/proj_backup_first_time_20261027/`（97 MB，git 忽略）。
纳入版本库的工程文件仅 8 个（3 XCI + 1 XDC + 4 COE）+ XPR + readme，共约 1.2 MB。

## 7. 复现路径（换一套 COE 的完整动作）

1. 打开 `riscv_vivado_project.xpr`（part/top 自动正确）
2. **IP Sources → 双击 `blk_mem_gen_0`（Re-customize IP）→ Other Options → Coe File** 指向
   `riscv_vivado_project.srcs/sources_1/imports/bin_file/<目标>.coe` → OK
   （**必须在对话框里改**；直接改文件 Vivado 不认，会拒绝重生成）
3. **Generate Output Products** → `Out of context per IP` → Generate（约 1–2 min）
4. 校验镜像指纹（`.gen/sources_1/ip/blk_mem_gen_0/blk_mem_gen_0.mif` 前几个字）：
   sw 第 3 字 `…A197`；ise 第 3 字 `…2197` 且第 4 字 `1E018193`；hw 第 3 字 `…2197` 且第 4 字 **`81018193`**
5. **Run Synthesis**（默认策略）→ **Run Implementation**（`Performance_ExploreWithRemap`）→
   **Generate Bitstream**
6. 存 bitstream 为 `build/local/board_bitstream/top_pl_bram_<版本>.bit` 并记 SHA-256
7. **Hardware Manager → Auto Connect → Program Device**（JTAG，非 QSPI；XCOM 先开好 COM 口）
8. 串口 115200 8N1 采集原始日志 → `data/ascon/results/board/`

## 8. 未闭环（不得在材料里当作已完成）

- **IO 时序未约束**：`no_input_delay` / `no_output_delay` 仍为已知项，板级 IO 未签核；+0.087 ns 是芯片内部时序
- 板上 ISA 回归抽样（含已知 `rv32ui_ma_data` 失败）未做
- MMIO 版仅支持 ≤16B；完整 1,089 组 KAT 仍只在 host 侧
- PS7 / PYNQ 链路未通（厂家镜像缺失，见 `board/atk_navigator_7020/vendor_findings.md`）
- 芯片丝印速度等级未现场核对（厂家示例 BD 为 `-2`，本项目按 `-1` 约束）
- PUF/密钥子系统**未进入本工程**（`src/rtl/keys` 仍未跟踪、未集成）


## 9. 阶段 4：PUF/密钥子系统（2026-10-27，独立于上面的三套签核结果）

三套 sw/ise/hw bitstream 对应的是 **PUF 之前的源集**（`src/rtl/*.v` 合并哈希 `a323df37…`）。
2026-10-27 晚把两处密钥子系统补丁应用到 `src/rtl` 后，源集变为 `2a83bec0…`（仅 `soc_top.v` 变，
另新增 `src/rtl/keys/*.v` 5 个文件、合并哈希 `be9507ef…`）。因此：

- 上面三份 bitstream **只能由 PUF 之前的源集重现**；最新工作区重建会得到第 4 份（keys 版）bitstream。
- 阶段 4 工程配置：`Coe_File = ascon_keys.coe`（`.mif` 第 3 字指纹 `1197`）、约束增加
  `build/keys_ro_pblock.xdc`、`impl_1` 挂 `STEPS.OPT_DESIGN.TCL.PRE = build/keys_ro_allow_loops.tcl`、
  include_dirs 加 `src/rtl/keys`、源文件 49 个（43 + 5 keys + keys COE）。
- 依据同源集的 STA（`build/reports/keys_sta_20261025_mmio2`）：WNS **+0.023**、TNS 0、0 失败端点、
  LUT 17123 / FF 28498 / BRAM 34.5、DRC 0 条 LUTLP-1。
- 阶段 4 的板级结果**尚未产生**；在它出来之前，P0 的三套结论不受影响，但也不得把 PUF 写成"已上板"。

## PUF 版镜像与实现证据（2026-10-27 23:47，v3 固件）

镜像与报告取自同一轮实现（`impl_1`，Vivado 2025.2，part `xc7z020clg400-1`，top `top_pl_bram`）：

| 项 | 值 |
|---|---|
| bitstream | `build/local/board_bitstream/top_pl_bram_keys3.bit`（4,045,687 B） |
| SHA-256 | `edaf8417d88e7b735f33302325a691a75dbc97b2764068ff4daead33697518aa` |
| 固件 COE | `ascon_keys.coe` sha256 `edd66d37…`（`.mif` 第 4 行 `58818193`，v3 固件） |
| 综合/实现策略 | `Vivado Synthesis Defaults` / `Performance_ExploreWithRemap` |
| WNS / TNS | **+0.152 ns** / 0.000 ns，失败端点 0 / 59513（`All user specified timing constraints are met`） |
| WHS / THS | +0.034 ns / 0.000 ns，失败端点 0 / 59513 |
| WPWS / TPWS | 0.000 ns / 0.000 ns，失败端点 0 / 18636 |
| 最差路径 | `u_cpu_core/id_ex_u/sel_ex_mem_rs1_o_reg/C` → 0.152 ns（`clk_out1_clk_wiz_0`，10 ns） |
| 布线 | 40894 / 40894 fully routed，routing errors 0 |
| DRC（routed） | **Error 0 / Critical Warning 0**；Warning 825（含 `LUTLP-2` ×256、`PDRC-153` ×256，源自 256 路 RO 有意的组合环与 pblock 放置） |
| 资源（placed） | LUT 15987（30.05%）、FF 28508（26.79%）、BRAM 34.5、DSP 4 |
| Methodology | `TIMING-17` ×1001、`TIMING-23` ×257 —— **RO 采样域仍未纳入 STA** |

口径说明：
- `+0.152 ns` 是这一版（含 PUF + v3 固件）的芯片内部时序余量，与 P0 三套（`+0.087`）不是同一源集，
  不可混用；也不同于 PUF 首版（`+0.168`，RTL 未含忙时排队/看门狗）。
- **不能据此声明 PUF 时序已签核**：RO 采样域（`ro_clk`、`osc[k]`）仍无时钟模型，
  `no_clock`/`unconstrained_internal_endpoints` 未消除。
- IO 时序仍未约束（`no_input_delay`/`no_output_delay`），上述余量仅为芯片内部。

