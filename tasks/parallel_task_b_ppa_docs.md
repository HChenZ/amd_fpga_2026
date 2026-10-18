# 并行任务卡 B：P0 收口文档与冻结检查点（文档向）

适合做证据整理与文档收口的 AI（本 Agent 执行）。与任务卡 A 零文件冲突
（A 只碰新建的 `src/pynq/` 与 development_log 末尾追加）。

## 背景

芯片级 100 MHz STA 已收敛（Performance_ExploreWithRemap WNS=+0.007 / 0 失败端点，
PostRoute +0.001，两份报告已核验），功能回归 ACB 套件全 PASS。本卡把 P0 的证据
固化成文档与冻结检查点。必读：`AGENTS.md` → `project_log/actual_progress.md` →
`docs/ascon_strategy_sweep.md` → `docs/timing_acb_validation.md`（另一个 AI 写的）。

## 交付物（只写 docs/ 与 tasks/，不碰其他）

1. **`docs/ascon_ppa_comparison.md`**（I08 收口，数据全部现成，纯整理）：
   - 三实现（纯软件 / MMIO / ISE）的资源对比表：LUT/FF/BRAM/DSP
     （来源 `data/ascon/results/strategy_sweep_20261017/strategy_sweep_summary.json`
     与 `build/reports/timing_acb_20261018/{postroute,remap}/route_utilization.rpt`）
   - 周期/加速比表：sw 17353 / hw 670 / ise 2496（16B enc，simulated 标注），
     与纯 crypto 延迟（99 cyc）分层列出
   - 时序收敛历程：-0.177 → 33 策略扫掠最优 -0.118（ExploreWithRemap）→
     dcache/ISE/乘法器三堵墙修复 → +0.001/+0.007；附策略扫掠 Top10 表
   - 明确标注：板级 IO delay 未约束、未上板，PPA 为芯片级 STA 证据
2. **`docs/freeze_checkpoint_20261018.md`** — 冻结检查点：
   - 构成收敛版本的改动清单：`src/rtl/dcache.v`（MISS_CAPTURE+B 修复）、
     `src/rtl/ascon/ascon_ise.v`（A 修复）、`src/rtl/ex_stage.v`+`src/rtl/mult.v`（C 修复），
     与基线 f52bc49 的关系
   - 复验命令（一条链）：sw/hw/ise/security/units 回归 + 双策略 STA 复测的完整命令，
     含工具链前缀与 Vivado 入口（参考 `docs/dcache_fix_plan_for_opencode.md` §4）
   - 改动门禁：此后任何 RTL/XDC/IP 改动必须重跑本清单全部项；余量 1-7 ps 的脆弱性说明
   - 剩余未闭环清单（B02/B03/V01/Y01-Y05 状态引用任务看板）
3. **`tasks/task_board.md` 状态更新**（与任务卡 A 不冲突）：
   - I08：todo → done，证据指向 ascon_ppa_comparison.md（标注"芯片级 STA 证据，
     板上 PPA 仍待 B03"）
   - V02：todo → done（差分验证在 ACB 套件中覆盖：sw/hw/ise 同一 KAT + 篡改拒绝）
   - 其余行不动；更新文件头部"更新：2026-10-17"日期
4. **`project_log/development_log.md` 末尾追加**本卡活动记录（先读格式再写）。

## 验收标准

- 文档中每个数字都有来源文件路径，没有来源的数字写 not_measured
- 与任务卡 A 的周期数据一致（同表同源）
- 不夸大：100 MHz 芯片级收敛 ≠ 上板通过；明确写出"板级 IO delay/DRC/实板 KAT 未验收"

## 禁区

- 不碰：`src/rtl/`、`src/pynq/`、`sim/ascon/`、`build/local/`、`build/reports/`、
  `ascon/`（用户自己的工程）、`data/`（只读引用）
- 不启动 Vivado / 不跑任何仿真（纯文档）
- 不 commit/push

## 完成标准

- 四个交付物齐全，文档内数字与证据源一一对应
- development_log 末尾有本卡记录
