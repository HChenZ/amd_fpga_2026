# L2 实验结果归档（2026-10-30 ~ 10-31）

这里只存**汇总证据**，原始 transcript 与 agent 交付文件在仓库外的试验目录里。

| 项 | 值 |
|---|---|
| 日期 | 2026-10-30（T1/T3）、2026-10-31（T2/T4） |
| 模型 | `deepseek/deepseek-flash`（三组相同，opencode v2.2.2） |
| 任务 | `t1_overlay`、`t2_hls`、`t3_dma`、`t4_diagnose` |
| 组别 | `with`（pynq-overlay-workflow）、`without`（无 Skill）、`placebo`（pynq-style-notes） |
| 规模 | 4 题 × 3 组 × 5 次 = 60 次 `opencode run`；另加 T1×placebo 修复仪器后复跑 5 次 = 65 次，全部 `exit=0` |
| 系统 | Windows 11，Python 3.14.0（`D:\Application\Python\Python314`） |
| 随机化 | seed 20261030，每批内所有试验随机打乱后串行执行 |
| 权限 | 三组均禁 shell/web/子 agent/工作区外目录；`with` 与 `placebo` 各允许自己的 Skill |
| 原始数据 | `C:\Nebula\HChenZ\Projects\ab_trials\{run1,run2,run1_fix_t1_placebo}\` |
| 结果类型 | `simulated`（假 PYNQ 行为模型），**不是板级结果** |

## 文件

| 文件 | 说明 |
|---|---|
| `results_all.csv` | **全部四题**的最终逐场景判分（390 行），由 `results_final.csv`（T1/T3）+ `results_t2_t4.csv` 拼接 |
| `stats_all.txt` | `stats.py results_all.csv` 的输出 |
| `results_final.csv` / `stats_final.txt` | T1+T3 的最终数据（T1 的 placebo 用修复仪器后的复跑批） |
| `results_t2_t4.csv` / `stats_t2_t4.txt` | 第二批（T2 HLS、T4 诊断）的判分与统计 |
| `results.csv` / `stats.txt` | 首批结果（**修复 `fake_pynq` 之前**判分，保留作对照：`t1_overlay/placebo/rep04` 当时被 `ImportError` 误判 0 分） |
| `results_t1_placebo_rerun.csv` | T1 × placebo 的 5 次复跑（修复仪器后） |
| `design.json` / `design_t2_t4.json` / `design_t1_placebo_rerun.json` | 三批实验的组别、重复次数、模型、种子、执行顺序 |

## 复现

```powershell
# 生成（目录必须在仓库外）
python skill/ab_eval_pynq/harness/make_trials.py --root <仓库外目录> --tasks t1_overlay,t2_hls,t3_dma,t4_diagnose --reps 5 --model deepseek/deepseek-flash
# 执行（每个试验一个新进程，顺序由 design.json 的 seed 决定）
powershell -ExecutionPolicy Bypass -File <仓库外目录>\run_all.ps1
# 判分与统计
python skill/ab_eval_pynq/harness/grade.py --root <仓库外目录>
python skill/ab_eval_pynq/harness/stats.py <仓库外目录>\results.csv
```

## 结论摘要

主指标（预注册）= T1–T3 的场景通过率，n=15/组：
| 组 | 均值 | 全通过 |
|---|---|---|
| with | **1.000** | 15/15 |
| without | 0.833 | 10/15 |
| placebo | 0.844 | 12/15 |

- `with` vs `without`：+0.167，**p=0.0425**，δ=+0.33（显著）；T3 单独 p=0.0476、δ=+0.80。
- `with` vs `placebo`：+0.156，p=0.2248，δ=+0.20（**未达显著**）；`placebo` vs `without`：p=1.0。
- 次指标 T4（文字诊断）：`with` 1.000、`without` 0.900、`placebo` 0.825；`with` vs `placebo`
  p=0.0079、δ=+1.00（区分点是 Q6 clear-on-read）。T4 规则为概念正则，存在误判风险，不作为主结论。
- T2（HLS）是天花板：三组都是 30/30 场景全通过，对该模型无区分度。
- 操作检查：`with` canary 20/20、`placebo` 20/20、`without` 0/20 → 三组只差 Skill。
- 板级效果：`not_measured`（L3 未执行）。

## 留出任务（`t5_bram`，一次性）

| 组 | 场景通过率 | 全通过 | canary |
|---|---|---|---|
| with | 1.000 | 5/5 | 5/5 |
| without | 0.800 | 4/5 | 0/5 |
| placebo | 0.800 | 4/5 | 5/5 |

`with` vs `without` p=1.0000、δ=+0.20，`with` vs `placebo` p=1.0000。差异来自 2 个试验全场景失败
（解法读了 `ip_dict` 里不存在的 `vlnv` 键，正确键名是 `type`）。**主实验的差异未能在留出任务上复现**，
10 个非 `with` 试验中 8 个满分，接近天花板；泛化证据不足。

- 文件：`results_holdout_t5.csv`、`stats_holdout_t5.txt`、`design_holdout_t5.json`
- 原始数据：`C:\Nebula\HChenZ\Projects\ab_trials\run3\`
