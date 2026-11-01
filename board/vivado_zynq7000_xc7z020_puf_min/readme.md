# PUF-MIN：最小闭环 RO-PUF overlay

> 2026-11-01 范围：独立探索版本，不是 PUF3，也没有 RV32/ISE。work/ 与 work_v2/ 是探索工程，
> 不是两个已发布 PUF3。未见可用的已发布 candidate，板测 NOT_RUN；下面“打包/交付”是操作流程而非完成声明。
> 本次不用作主演示，程序和实验记录保留；见 docs/version_entrypoints.md。

任务号 `PUF-MIN`（`tasks/puf_fix_and_min_goal_20261030.md` §4）。owner TBD。

**只把"物理响应"留在 PL**：PS 上的 Python 负责注册、重建、派生密钥、加解密与统计。
PL 内没有 CPU、没有私有 BRAM/COE、没有 Ascon ISE/MMIO、没有 crypto_aead、没有
puf_key_v2、没有镜像认证、没有邮箱、没有 FCLK1。

## 目录内容

| 文件 | 作用 |
|---|---|
| `setup.tcl` | 新建独立工程 `work/puf_min.xpr`；BD 里导出 `ps7/FIXED_IO`、`ps7/DDR`；单时钟 FCLK0=100MHz；把 4KiB 窗口放到 `0x40000000` |
| `ring_ack.tcl` | `impl_1` 的 `OPT_DESIGN.TCL.PRE`：逐环确认 256 个反馈网并打开 `ALLOW_COMBINATORIAL_LOOPS`，建立 `pb_ro_puf` |
| `build.tcl` | `setup -> synth -> route_design`（**不跑 phys_opt_design**）`->` 门禁 `->` 写 bit |
| `reports.tcl` | 实现后全套报告（timing/utilization/drc/methodology/cdc/clocks/route_status/check_timing） |
| `audit_rings.tcl` | 只读复核：1280 个环 LUT、256 个已确认反馈网 |
| `package.py` | 把证据目录打包成 `candidate/`（bit/hwh/manifest/reports），门禁不过则拒绝 |
| `verify_delivery.py` | 交付前校验：candidate 哈希、门禁字段、仿真证据 |
| `sources.txt` | 综合源清单（与 `sim/puf_min/sources.json` 的 `rtl` 段一致） |

## 怎么跑

```powershell
# 1) 纯仿真（不需要 Vivado）
python sim\puf_min\run.py

# 2) 主机闭环单测（不需要板卡）
python -m unittest src.pynq.test_puf_min -v

# 3) 实现（独立 Vivado 会话，Vivado 2025.2）
vivado -mode batch -notrace -source board\vivado_zynq7000_xc7z020_puf_min\build.tcl `
       -log data\advanced\puf_min\session_xxx\vivado_build.log

# 4) XSim 回归（必须在 puf_min 工程自己的会话里，脚本会校验工程路径）
vivado -mode batch -notrace -source board\vivado_zynq7000_xc7z020_puf_min\build.tcl   # 先建好工程
# 之后在交互式会话里：
#   open_project board/vivado_zynq7000_xc7z020_puf_min/work/puf_min.xpr
#   source sim/puf_min/run_xsim.tcl

# 5) 打包与校验
python board\vivado_zynq7000_xc7z020_puf_min\package.py
python board\vivado_zynq7000_xc7z020_puf_min\verify_delivery.py
```

## 实现门禁（`build.tcl` 里硬编码，失败即 `error` 且不写 bit）

| 项 | 门限 |
|---|---|
| setup | `route_design` 后 WNS ≥ **+0.5 ns**，**不依赖** `phys_opt_design` |
| hold | WHS ≥ 0（WNS/WHS ≥ 0 时 TNS/THS 必为 0） |
| DRC | Error = 0 |
| PS 引脚 | `impl_1`/`synth_1` 运行日志中 `Netlist 29-160` **= 0** |
| PS 端口 | 顶层存在 `DDR*` 与 `FIXED_IO*` |
| RO 结构 | 1280 个环 LUT，且全部落在 `pb_ro_puf`；256 个反馈网逐个确认 |

## 记录边界

- 结论等级是 `STRUCTURAL_ONLY_NO_RO_TIMING_SIGNOFF`：RO 环是异步物理环路，
  **不定义 RO 时钟、不虚构最小周期**，无时钟 pin / 未约束端点数量照实列出。
- 板测 `NOT_RUN`。上位机脚本加载前用 SHA-256 校验 candidate。
- 不宣称：熵、安全提取器、ECC、温度/电压/老化可靠性、多板唯一性（inter-HD）、
  安全启动、防回滚、key 保密性（RAW 可读）。
