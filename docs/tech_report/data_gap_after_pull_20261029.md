# 数据缺口台账（拉取 3609523 之后重算）

> 2026-11-01：3609523之后的历史台账，不能由本页“本地缺失”推断现在仍未测试。
> 当前PUF3/10-31数据和已知边界见 ../version_entrypoints.md；原缺口记录保留，不回写当次结果。

> 历史审查快照，已由 `review_20261029.md`、当前报告及 `tasks/release_plan_20261101.md` 取代。
> 下文“必须DMA”“无照片”“所有缺口均需补”等不再作为当前结论或排期；保留原记录供追溯。

```text
task_id / date / owner: I-doc-gap-repull / 2026-10-29 / TBD
source_head: 3609523（main，拉取前 f2f575e）
upstream: 队友提交 e359c91 / 755ebde / 3609523（PYNQ 10-29 实板取证）
changed_files: 仅新增本文件；未改正文、未改 RTL、未 commit/push
verification: 见 §1「已核实」列，全部为本机读文件/读 JSON 计算
```

## 1. 本轮新到的数据（`git diff f2f575e..3609523`）

| 路径 | 内容 | 已核实 |
|---|---|---|
| `data/pynq/board_20261029/env.txt` | PYNQ 2.7.0 / Py 3.8.2 / Linux 5.4.0-xilinx-v2020.2 / commit ac9143d | 文本一致 |
| `data/pynq/board_20261029/pynq_board_smoke.{json,log}` | 三模式各 6/6 KAT、6/6 错 Tag 拒绝；cycles 逐条 | 读 log 复算 6+6×3 |
| `data/pynq/board_20261029/release_hashes.log` | release 六件 bit/hwh/bin/coe/elf/manifest 全 `OK` | 6 行 OK |
| `data/pynq/notebook_20261029_130920/` | Notebook `Run All` 结果：smoke + warm benchmark（KAT #529，PT 16 B / AD 0，5 预热 + 每操作 30 采样，含 `raw_cycles` 与 `raw_wall_ns`） | `simulated=false`、`selftest_mask=7`、30 个样本全一致 |
| `data/pynq/error_gate_20261029_134023/` | V03 错误/恢复门禁 9/9 PASS、reset 7/7、epoch 1→8；已执行 `.ipynb` 本体、JSON、log | `checks` 逐项 PASS；每模式 50 次往返 |

新增可引用数值（同一 release、`simulated=false`）：

| mode | enc cycles | dec cycles | enc 墙钟中位 | dec 墙钟中位 |
|---|---:|---:|---:|---:|
| SW | 23,342 | 24,005 | 5,215.5 µs | 4,956.8 µs |
| HW | 1,439 | 1,388 | 4,478.6 µs | 4,262.1 µs |
| ISE | 3,995 | 4,385 | 5,154.2 µs | 4,986.0 µs |

`mcycle` 口径为固件 AEAD 调用边界；墙钟口径为 PS 侧一次 mailbox 事务（含 Python 与 UART），
JSON 自带 `wall_time_scope: descriptive only`。

## 2. 仍未拿到的数据

| # | 缺的数据 | 现状（本机实测） | 补法 |
|---|---|---|---|
| 1 | PUF ≥50 次上电统计、温压、唯一性 | 仓库只有一次上电的 `uart_20261027_keys3.txt`（quality 128/128）；无温压记录；仅一块板，跨芯片唯一性不可得 | 需 PS 侧保留域/Flash 持久化 helper 后重复上电 |
| 2 | RO 采样域时序签核 | `docs/io_timing_signoff.md` §10 仍为 `no_clock` 10944、`unconstrained_internal_endpoints` 27312（全在 `u_puf_key`，根因 `ro_clk_div_reg[1]/Q` 常高） | 补 RO 时钟模型与 `create_clock`/`set_false_path`，重跑 STA |
| 3 | 板上 ISA 抽样回归 | 仓库内三套 `data/ascon/results/isa/*/` 均为仿真/host，且 `rv32ui_ma_data.json` 三套全 `FAIL` | 先定 ma_data 失败归因（修或写豁免），再在板上跑 riscv-tests 子集 |
| 4 | 完整 1,089 组板级 KAT 的剩余 800 组 | 板端上限 16 B，仅 289 组（PT/AD 各 0–16 全组合）；`error_gate` 仅验证 17 B 返回 `LENGTH` | 需 AXI-Stream/DMA 或分段接口；否则正文只能写 289/1,089 |
| 5 | 长时运行与资源泄漏统计 | 手头最长证据为 30 次采样 + 每模式 50 次往返；无小时级运行、无 FD/内存增长记录 | 板端循环跑 1–4 h，周期采样 `/proc/<pid>/fd`、RSS |
| 6 | 大消息吞吐、密码核独立 PPA | 未测；`git ls-files | grep standalone` 为空 | 需独立 ascon core 的 OOC 综合 + 流式吞吐测试 |
| 7 | PYNQ 独立 FCLK 测量 | `validation_20261029.md` 第 49 行仍 `not_measured`；只有 PS 侧读 PL 计数器 | 用 PL 输出方波到 PS 计数器，或外部频率计 |
| 8 | 10-29 的仿真 smoke/regression 存档 | 仓库内 `build/reports/pynq_final_20261028/` 为 **10-28、source_head 0f5d49c** 的 run：smoke `elapsed_s=18.739`、regression_final `400.168`；而报告 §5.4 写 **16.4 s / 757.7 s**，两者不是同一次 run | 重跑 `sim/board/run_tests.py --mode smoke/regression` 并归档，或把 §5.4 改成 10-28 run 的实测值 |
| 9 | P0 三份 Vivado 报告、IO 机检输出、bitstream 入库 | 均未入 git（`.gitignore` 排除 `*.runs/`、`build/local/**`）；目前只在未跟踪的 `submission/evidence/` 里 | 按 D3/D5 决策：入 900 KB 文本报告 / bitstream 只进证据包 |
| 10 | B03 板卡实物证据 | `git ls-files | grep -E '\.(jpg|png|mp4)$'` 为空——仓库无任何图片；丝印/速度等级/SD 镜像/跳线均无 | 拍板卡正反面、核心板丝印、SD 卡与跳线照片 |
| 11 | `dna.txt`、`docs/tech_report/`、`submission/` | 仍未跟踪（`git status` 显示 `??`） | 由项目方决定是否入库 |

已解决、不必再查：

- **TNS 冲突（旧 #5）**：`build/reports/strategy_sweep_20261017/sweep_perf_explore_remap/route_timing.rpt`
  第 150 行为 `-0.118 / -1.008 / 22 / 50015`，与 `docs/ascon_ppa_comparison.md` 一致；
  `strategy_sweep_summary.csv`（已入库，33 行）同为 −1.008。旧 `sweep_summary.tsv` 的 −1.004 是错的。
- **33 组策略逐组数据（旧 #4）**：`data/ascon/results/strategy_sweep_20261017/strategy_sweep_summary.{csv,json}`
  已入库，逐组 wns/tns/失败端点/LUT/FF 齐全；但 `duration_s` 仍全 0（旧 #6 未变）。

## 3. 新数据与报告正文冲突（需改正文，不是缺数据）

| 正文位置 | 现写法 | 新数据 |
|---|---|---|
| §8.1 第 28–29 行 | 16 B 加密 PS 端到端"约 200 至 300 µs，尚未实测" | 实测中位 4.26–5.22 ms，**高一个量级**；且 HW 与 SW 仅差约 0.7 ms，周期差异被 Python/UART 开销淹没 |
| §5.4 | smoke 16.4 s、regression 757.7 s | 仓库可核的 run 为 18.739 s / 400.168 s（10-28） |
| §9.1 第 20 行 | Notebook"未执行，无长时统计" | 已执行 `Run All` 并归档，仅"长时/泄漏"仍缺 |
| §9.1 第 19 行 / §8.5 | 未提错误恢复 | 可补 9/9 PASS、7 次 reset/epoch、17 B `LENGTH`、RX overflow 恢复 |
| §9.2 第 5 条 | "端到端延迟与吞吐仍为模型估算" | 延迟已实测，可改写；吞吐仍缺（仅 16 B） |
