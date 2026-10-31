# `sim/puf_min` — PUF-MIN 仿真

owner TBD。**行为级 RO 模型不是物理 PUF 证据**：`sim/puf_soc_v2/ro_array_model.sv`
只把 1280 个 LUT 环整替换成确定性差频振荡器，用来验证数字路径；板测状态永远是
`not_measured`。

| 文件 | 作用 |
|---|---|
| `sources.json` | 单一源清单真源：`run.py` 和 `board/vivado_zynq7000_xc7z020_puf_min/setup.tcl` 共同依据 |
| `axi_lite_bfm.sv` | AXI4-Lite 主机 BFM（单 outstanding；AW 与 W 分开握手） |
| `tb_puf_min.sv` | 寄存器 ABI + 协议 + 状态机自检（默认"快速"参数，`-DPROD_PARAMS` 为生产参数） |
| `tb_ro_core_single_clock.sv` | 探索项 E1：`clk == ro_clk` 下采样器仍然正确 |
| `run.py` | Icarus 回归：3 个用例，记录命令/退出码/日志/源哈希到 `data/advanced/puf_min/icarus_*` |
| `run_xsim.tcl` | XSim 回归：同样 3 个用例，必须在 puf_min 自己的工程会话里运行 |

## 跑法

```powershell
python sim\puf_min\run.py
# 交互式 Vivado 会话里：
#   open_project board/vivado_zynq7000_xc7z020_puf_min/work/puf_min.xpr
#   source sim/puf_min/run_xsim.tcl
```

## 用例覆盖

`tb_puf_min`（快速参数 `WINDOW=64`）覆盖：

1. ID / VERSION / 复位后 STATUS（只允许 `dna_ready` 置位）与 57-bit DNA 打包；
2. 非法读（未映射偏移、非对齐）→ `SLVERR`；写只读寄存器 → `SLVERR` 且数据不变；
3. `wstrb=0` 的 CTRL 写被忽略（合法应答、无副作用）；
4. 一次成功采样：`busy → done/valid`、`ERROR=0`、RAW = `0x5555…`（模型差频预期）、`TXN` +1；
5. 粘滞性：不重启也能重复读到同一 RAW / done / valid；
6. `CNT_SEL`/`CNT_VAL`：`c0 > c1`、`c128 < c129`（模型里两组环的快慢正好相反）；
7. `CLEAR` 清状态与结果；
8. busy 期间再次 START → `ERROR=0x40` 且 `locked`，且不发布 RAW；
9. `CLEAR` 解除锁定后可再次成功采样，`TXN` 跨 CLEAR 继续单调；
10. `CTRL=3`（START|CLEAR 同置）按 CLEAR 处理。

`tb_puf_min`（`-DPROD_PARAMS`，`WINDOW=1024 / CW=20`）用生产参数跑完整往返，
证明 128-bit/1024 窗口配置可用（`c0=2560, c1=1280`）。

`tb_ro_core_single_clock` 用生产参数验证 `clk == ro_clk`：

* 6 次连续采样逐位一致、事务号递增（任何跨域丢拍都会破坏一致性）；
* busy 期间 START → `0x40` + `locked`；
* 复位后恢复并再次成功采样。

## 未覆盖 / 不宣称

* 物理 RO 频率、熵、BER、温度/电压/老化、多板唯一性（`inter_hd=not_measured`）；
* 后仿（post-route SDF）**未运行**；
* 板上 AXI 时序与 PYNQ 驱动由 `src/pynq/puf_min.py` 的 mock 单测与人工板测覆盖。
