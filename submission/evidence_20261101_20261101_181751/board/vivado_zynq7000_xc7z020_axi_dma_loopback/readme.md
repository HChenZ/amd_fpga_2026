# AXI DMA 回环 overlay（非 Ascon，Skill L3 实板测试用）

2026-10-31；owner TBD。给 `skill/pynq-overlay-workflow` 的 L3 实板层提供一个与 Ascon 无关的
overlay（段 C 寄存器契约、段 D 有界 DMA），见 `skill/ab_eval_pynq/README.md` §1 L3。
独立入口，不引用任何项目 RTL，不改其他 board 工程。

## 设计

| 项 | 值 |
|---|---|
| 工具 / 器件 / 顶层 | Vivado 2025.2，`xc7z020clg400-1`，`dma_loop_wrapper` |
| PS7 | `M_AXI_GP0` → `axi_interconnect` → `axi_dma_0/S_AXI_LITE`；`axi_dma_0/M_AXI_MM2S`、`M_AXI_S2MM` → `axi_interconnect` → `S_AXI_HP0`（64 位） |
| AXI DMA | `xilinx.com:ip:axi_dma:7.1`，**simple 模式**（`c_include_sg=0`），MM2S/S2MM 均启用，地址 32 位，数据 32 位，无 DRE（缓冲物理地址须 4 字节对齐），`c_sg_length_width=14`（单次最多 16383 字节） |
| 回环 | `M_AXIS_MM2S` 直连 `S_AXIS_S2MM`（接口连线，TDATA/TKEEP/**TLAST** 原样传递，hwh 中 `s_axis_s2mm_tlast` 的信号名就是 `axi_dma_0_m_axis_mm2s_tlast`） |
| 地址 | `axi_dma_0` 控制寄存器 `0x40400000`，64 KiB；DMA 看到的 HP0 DDR 窗口 `0x00000000–0x3FFFFFFF`（1 GiB） |
| 时钟 / 复位 | 全部使用 FCLK0；`proc_sys_reset` 由 `FCLK_RESET0_N` 驱动，`interconnect_aresetn` 接两个互连核，`peripheral_aresetn` 接各端口与 DMA |
| 中断 | 未连接（只用轮询） |

两处板卡相关配置（不配会在这块正点原子领航者板上出错）：

- **FCLK0**：PYNQ 只按 hwh 写 FCLK0 分频，IO PLL 沿用启动镜像（33.333333 MHz × 30 = 1000 MHz）。
  因此固定 `PCW_IOPLL_CTRL_FBDIV=30`、分频 10 × 1，得到 100 MHz。若让 IP 自选（1600 MHz、4 × 4），
  板上实际只有 62.5 MHz（pynq_puf3 已在板上踩过并验证修正）。原版 PYNQ 2.7 的 `Clocks.fclk0_mhz`
  按 50 MHz 参考时钟换算，会显示 **150**，这是它的假设导致的，不是实际频率。
- **DDR 大小**：PS7 的 DDR 参数按厂家 base 设成 MT41J256M16 RE-125、32 位（1 GiB）。IP 默认是 512 MiB，
  那样 DMA 的 HP0 窗口只到 `0x1FFFFFFF`，`pynq.allocate` 若分配到 512 MiB 以上会出现 `DMADecErr`。
  overlay 不会重新配置 DDR，这个参数只决定 DMA 能访问的地址范围。

## 构建与打包（仓库根目录）

```sh
vivado -mode batch -source board/vivado_zynq7000_xc7z020_axi_dma_loopback/build.tcl -notrace -tclargs Performance_ExploreWithRemap 6
python -X utf8 board/vivado_zynq7000_xc7z020_axi_dma_loopback/package.py
```

`build.tcl` 拒绝复用已有的 `build/local/axi_dma_loopback/vivado`。它会回读并核对 PS7/DMA 配置以及两个 DMA 地址空间的
HP0 窗口（0x0 + 1G）。在同一次实现的最终 checkpoint 上检查以下门禁，任一不满足就停止、不出 bit：
setup/hold ≥ 0、没有 DRC Error/Critical Warning、没有 `Netlist 29-160`、没有未布通的线网。
通过后写出同名的 `axi_dma_loopback.bit` / `.hwh`。

`package.py` 复查门禁和 bit、gate、checkpoint 的生成顺序，再从 hwh 核对：simple 模式参数、GP0/HP0、
MM2S→S2MM 回环与 TLAST、HP0 窗口 1 GiB、FCLK0 配置。还会用 Skill 自己的工具检查：
`hwh.parse_hwh` 得到 `axi_dma_0 @0x40400000 +0x10000`，`dma.config_from_hwh` 得到最大传输 16383、对齐 4。
最后用 `artifacts.write_manifest` 生成 `candidate/manifest.json`（同一次实现的 bit/hwh 哈希）。

## 当前候选（2026-10-31，离线门禁与 L3 板测 PASS）

| 项 | 结果 |
|---|---|
| 实现 | Vivado Synthesis Defaults + Performance_ExploreWithRemap + 布线后 phys_opt（impl_1） |
| Setup / hold | WNS +1.736 ns，WHS +0.025 ns；没有无时钟引脚或无约束端点 |
| DRC / PS 引脚 / 布线 | 0 个 Error 或 Critical Warning；没有 `Netlist 29-160`；全部布通 |
| 资源 | 2436 LUT / 3333 FF / 2 BRAM tile |
| 工件 | `axi_dma_loopback.bit` sha256 `890add35…`，`axi_dma_loopback.hwh` sha256 `27bcceca…`（以 `candidate/sha256sums.txt` 为准） |
| Skill L1 工具 | `pynq_skill_cli.py artifacts … --manifest` exit 0；`hwh … --contract examples/axi_dma_simple.contract.json --ip axi_dma_0` 显示契约与 hwh 寄存器一致 |
| L3 实板 | session `l3_20261031_063709` PASS：8/9/16/64/256 B 与连续 16 B 回环数据一致，超限启动前拒绝、mutation 检出、DMA 恢复 halted |

第一次构建用的是 IP 默认 DDR 大小（512 MiB 窗口），在打包前的 hwh 检查中发现，已作废，没有发布
（工作目录留在 `build/local/axi_dma_loopback/vivado_ddr512m`）。

## 上板（L3）

`skill/ab_eval_pynq/test_board/l3_30_dma.ipynb` 默认直接使用本工件：
`candidate/` 目录里正好有一个 `.bit` 和一个 `manifest.json`，同名 `.hwh` 也在同一目录。

按 `skill/ab_eval_pynq/test_board/readme.md` 的顺序执行 `l3_30_dma.ipynb`。它会自动选中唯一的
`axi_dma_0`，测试长度 8/9/16/64/256 以及 16 字节连续两次，检查超长请求在启动前被拒绝。
该 Notebook 记录的 `fclk0_pynq_register_derived_mhz` 来自原版 `Clocks`，会显示 150，
这不影响判定（它不做时钟门禁），写结论时不要当作实际频率。

如果手动按 Skill 的 A–D 段执行，结果按 `skill/ab_eval_pynq/README.md` 的口径记录：

1. **A 工件**：`python3 skill/pynq-overlay-workflow/scripts/pynq_skill_cli.py artifacts board/vivado_zynq7000_xc7z020_axi_dma_loopback/candidate/axi_dma_loopback.bit --manifest board/vivado_zynq7000_xc7z020_axi_dma_loopback/candidate/manifest.json`
2. **B 加载**：`Overlay(<bit>)` 后核对 `ip_dict['axi_dma_0']` 为 `0x40400000`/`0x10000`。FCLK0 按 hwh 晶振由 SLCR 推算，不要用原版 `Clocks.fclk0_mhz` 判定。
3. **C 寄存器**：用 `examples/axi_dma_simple.contract.json` 生成驱动，读 MM2S/S2MM DMASR（复位后应为 Halted）。
4. **D 数据通路**：用 `BoundedSimpleDMA.from_parameters(MMIO(...), ip_dict['axi_dma_0']['parameters'])`
   做回环。回环输出应与输入逐字节一致，S2MM LENGTH 读回应等于发送长度。建议覆盖 4 B、1 KiB、16380 B，
   以及连续多次传输。不要直接访问 `ol.axi_dma_0`（PYNQ 2.x 驱动构造时会无超时自旋）。

## 限制

- 这是测试工件，不属于项目交付功能，也没有 Ascon 内容。
- 没有接中断；没有 SG；没有 DRE。奇数长度可以传输，但物理地址必须按 4 字节对齐。
- DMA 吞吐率未测，不能用本 overlay 宣称带宽。
