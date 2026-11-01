# 冻结检查点 2026-10-18（100 MHz 芯片级收敛版本）

> 2026-11-01：保留10-18芯片级源快照，不是当前PUF3的源码/工件冻结点。
> 当前提交留档见 submission/freeze_manifest.md 与 version_entrypoints.md；原周期/报告不可跨版本混用。

本文档定义当前收敛版本的文件构成、复验命令与后续改动门禁。目标：10-27 功能冻结前
任何改动都有据可查、可一键复验。

## 1. 收敛版本构成

- 基线：f52bc49（fix/ascon-key-lifecycle，origin 同步）
- 工作区未提交修改（构成收敛 RTL）：
  - `src/rtl/dcache.v` — MISS_CAPTURE 流水化 + MMIO 握手修复 + store/MMIO 绕行（B）
  - `src/rtl/ascon/ascon_ise.v` — s_reg 复位局部寄存器化（A）
  - `src/rtl/ex_stage.v` — 乘法器 multi-cycle 集成（C）
  - `src/rtl/mult.v` — 新模块：寄存器化乘法器（C）
  - 其余 src/rtl 与 f52bc49 一致；XDC/XCI/COE 与 baseline 一致
- 生产策略：**Performance_ExploreWithRemap**（WNS +0.007）；
  备用 Performance_ExplorePostRoutePhysOpt（+0.001）
- 证据快照：`build/reports/timing_acb_20261018/{postroute,remap}/`、
  `data/ascon/results/key_lifecycle/*_timing_acb*.json`、
  `data/ascon/results/isa/{fix_r1_control,timing_acb}/`

## 2. 复验命令（一条链，全部 exit 0 才算复验通过）

```bash
cd <repo_root>
P="C:/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-"
# 2.1 功能回归（sw/hw/ise + security + 单元）
python sim/ascon/run_cpu_regression.py --mode sw  --label freeze_ck --cc-prefix $P && \
python sim/ascon/run_cpu_regression.py --mode hw  --label freeze_ck --cc-prefix $P && \
python sim/ascon/run_cpu_regression.py --mode ise --label freeze_ck --cc-prefix $P && \
python sim/ascon/run_cpu_regression.py --mode hw  --security --label freeze_ck --cc-prefix $P && \
python sim/ascon/run_cpu_regression.py --mode ise --security --label freeze_ck --cc-prefix $P && \
python sim/ascon/run_cpu_units.py --label freeze_ck
# 2.2 ISA 回归（49 PASS + 1 既有 FAIL=rv32ui_ma_data，与对照组一致）
python sim/ascon/run_rv32_isa.py --label freeze_ck
# 2.3 时序复测（双策略，独立工程；先清理旧产物）
#   build/build_dcache_pipe.tcl 的 tag 机制：-tclargs freeze_ck 写独立目录
/c/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch -source build/build_dcache_pipe.tcl \
  -notrace -log build/local/strategy_sweep_log/vivado_freeze_ck.log -tclargs freeze_ck
# 2.4 判定：RESULT wns= 双策略均 ≥ 0，TNS=0，失败端点=0
```

## 3. 改动门禁

- **任何** src/rtl、XDC、XCI、COE、固件、工具链版本改动后：
  1. 运行 §2.1+2.2 全套功能回归；任一非"既有失败"即回退
  2. 运行 §2.3 双策略时序复测；任一策略 WNS<0 即回退或追加修复
  3. 在 development_log 记录改动 diff 摘要 + 复验结果路径
- 余量脆弱性：收敛余量仅 1-7 ps，处于布局噪声量级（s_reg 路径实测跨布局摆动
  -0.05~-0.128）。双策略同为正提供防误证；不同 Vivado build/种子下结果可能漂移，
  复验以本机 2025.2 环境与上述命令为准。

## 4. 剩余未闭环（引用任务看板）

- B02（重建与报告收口）、B03（板型/pinout/IO delay，blocked）、B04（固件加载）
- V01（实板回归/mcycle）、V03（PS/PL 端到端）、Y01-Y05（PYNQ）、S01-S05（Skill）
- V04（冻结回归清单，10-27）、M05（提交材料，11-01）
- P01-P04（PUF/密钥生成，gated；10-21 门禁后再评估）
