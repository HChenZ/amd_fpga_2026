# 失败与被替代的尝试（backend_opt_20261021）

本目录的 35 个 `result.txt` 都是有效臂。下面这些是**装置层面**的失败尝试，
已被修复后的同一批重跑替代，不是时序结论；列在这里是为了让任何人读
`build/local/backend_opt_20261021/results.tsv` / `logs/` 时不会把 EXIT=1 当成实验失败。

| 时间 | 臂 | 现象 | 根因 | 处置 |
|---|---|---|---|---|
| 00:17 | fp2 / fp3 / fpc | EXIT=1 | 起点用了 `synth_1/top_pl_bram.dcp`：里面没有约束（`get_clocks` 为空）且 clk_wiz / blk_mem_gen / axi_bram_ctrl 三个 IP 是黑盒，`opt_design` 报 DRC INBB-3 | 改起点为 `acb_remap/top_pl_bram_opt.dcp`（带 clk/clk_out1、零黑盒、8/31461 已布局） |
| 00:20 | fp2 / fp3 / fpc | EXIT=1 | 同上（未改起点前的重复尝试） | 同上 |
| 00:22 | fp2 / fp3 / fpc | EXIT=1 | `set_property PLACE_DENSITY` 收到的是字面量 `$bopt_dens`（生成脚本里写成 `{$bopt_dens}`），属性不存在 | 生成脚本改为 `$bopt_dens` 无花括号；00:27 两个臂 `place_ok`（fp2 place_wns +0.296 / fp3 +0.206） |
| 00:25 | fpc | EXIT=1 | 并行 Vivado 抢同一个 `-log` 路径，报 `Failed to create directory 'C'` | launcher 改为每臂独立 cwd，不传 `-log` |
| 00:30 | ctl / rep256 / fp3 / rep128 / pl_ndh | EXIT=1 | 变体表写成了 `vspec arm {place ExtraTimingOpt ...}`，整个 spec 只作为一个参数传入，`array set` 报“list must have an even number of elements” | 改成 `vspec arm place ExtraTimingOpt ...` |
| 00:29 | probe_levers（首跑） | EXIT=1 | 脚本里有不存在的 `get_site_property` | 删掉该段后重跑，现引用的 `recon/*` 来自修复版 |
| 01:29 | fp3_loose | EXIT=1 | pblock 上 `PLACE_DENSITY` 在 Vivado 2025.2 不存在（`Netlist 29-177`） | 这一条**本身是结论**：2025.2 没有可用的“疏松密度”旋钮（见 docs §2.3/§4.4）；脚本已改成 `catch` 保护 |

`fp3_loose` 没有有效 `result.txt`，因此不在 35 臂汇总表里；它对应的结论由
`pl_spread`（+0.002）与 `pl_spread_lo`（−0.027）承担。

### WHS 战役的两个臂

| 时间 | 臂 | 现象 | 处置 |
|---|---|---|---|
| 12:03 | `hfp_split_near` | 正常出结果：WNS −0.110 / WHS +0.032（用 setup 换 hold，净亏） | 结论写入 docs §4.7 |
| 12:04 | `hfp_split` | placer 在 `Phase 4.1.1.2 Post Placement Timing Optimization` 停 30+ 分钟无输出，`stdout` 自 11:33 起无更新 | 终止进程（WINPID 50424）；无 DCP 产出。远分离几何在这颗器件上不可行 |
