# dcache 修复执行方案（OpenCode + AMD Ross）

> 本方案是历史执行记录。V10 已按用户要求清理其旧报告/中间结果；请使用
> [当前清理与复验入口](workspace_cleanup.md)，不要继续执行下面的旧删除/覆盖命令。

目标：修复 dcache 流水线版的功能死锁，保住时序改善（WNS -0.177 → -0.055），
功能回归全绿后重新测量时序。本方案自带诊断结论与验证门禁，可直接执行。

## 0. 协作约束（先读，违反会毁掉进行中的扫掠）

1. **禁止打开/操作 `build/local/strategy_sweep/`**。该隔离工程正在跑 27+ 策略扫掠；
   同一工程两个 Vivado 主进程会互相重置 run 状态、毁掉双方数据（本仓库已实测两次）。
2. 所有实验一律使用**独立工程副本**（见 §6 入口脚本）。
3. `src/rtl/dcache_experiments/` 里的实验文件**不得移回** `src/rtl/`：
   `dcache_timing_optimized.v` / `dcache_aggressive_fsm.v` 都声明 `module dcache`，
   Vivado 遇到同名模块**不报错、静默按文件顺序选一个**综合，之前一次时序测量因此测错对象。
4. 改 RTL 前先跑一遍基线回归留证据（§4 命令，`head` 档）。

## 1. 诊断结论（已定位，直接修，不要重复排查）

死锁点（调试 TB 实测）：
```
t=200  缓存 miss 正常完成（FILL → IDLE）
t=251  第一次 MMIO 访问进入 MISS_CAPTURE
t=275 起 pc=0x100083f0, state=IDLE, cpu_stall_o=1 恒高,
      bus_mem_re_o=0, bus_mmio_re_o=0, rdata_valid_i=0 → 永久死锁
```
根因：MMIO 读等待被改写成依赖 `bus_rdata_valid_i` 清除
（`else if (bus_rdata_valid_i) mmio_read_wait_r <= 1'b0;`），
但 `bus_mmio_re_r` 在 MISS_CAPTURE 只发 1 拍脉冲，AXI 握手从未完成，
`rdata_valid` 永远不来 → `mmio_read_wait_r` 恒 1 → CPU 无限 stall。

附带隐患：MISS_CAPTURE 态里 `bus_load_miss_r <= captured_re && cacheable && !hit`
用的是**活** `hit`/`cacheable`（活地址推导），应在捕获时刻锁存 hit 或从 captured 值重算。

## 2. 修复方案（二选一 + 必做审查）

- **方案 A（推荐）**：`bus_mmio_re_r` / `bus_mem_re_r` 保持断言直到总线接受
  （用 `m_arready`/`m_awready` 或显式 ack 门控），数据到达后再清 `mmio_read_wait_r`。
- **方案 B**：恢复原固定 2 拍移位等待（`mmio_read_wait_r <= mmio_read_now;
  uncached_req_r <= mmio_read_wait_r`），不要用 `bus_rdata_valid_i` 门控 stall。
- **必做审查**：hit 结果在捕获时刻锁存，避免 MISS_CAPTURE 中引用活输入。

## 3. 用 AMD Ross 干什么

- 改完先 `vivado-rtl-lint`（Skill 名）检查 dcache.v；
- 需要波形/逐拍调试时用 `vivado-simulate-rtl`（Vivado xsim，独立工程内跑，
  避开扫掠进程；本机 Vivado 2025.2 已装 Zynq-7000 器件库）；
- 快速回归仍用品快 Icarus 脚本（比 xsim 快一个量级，见 §4）。

## 4. 验证门禁（全部通过才算修好）

```bash
# 4.1 基线对照（原始 dcache，必须 PASS）—— 验证筛选环境本身可靠
bash build/screen_dcache_donttouch.sh head

# 4.2 修好后：功能回归，sw/hw/ise 三模式 + security 全 PASS
P="C:/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-"
python sim/ascon/run_cpu_regression.py --mode sw  --label fix_r1 --cc-prefix $P
python sim/ascon/run_cpu_regression.py --mode hw  --label fix_r1 --cc-prefix $P
python sim/ascon/run_cpu_regression.py --mode ise --label fix_r1 --cc-prefix $P
python sim/ascon/run_cpu_regression.py --mode hw  --security --label fix_r1 --cc-prefix $P
python sim/ascon/run_cpu_regression.py --mode ise --security --label fix_r1 --cc-prefix $P

# 4.3 单元测试
python sim/ascon/run_cpu_units.py --label fix_r1

# 4.4 时序复测（独立工程，含 Performance_ExplorePostRoutePhysOpt）
#     先删旧产物再跑，避免脚本防覆盖报错：
#     rm -rf build/local/ascon_dcache_pipe build/reports/dcache_pipe_20261018
bash -c '/c/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch -source build/build_dcache_pipe.tcl \
  -notrace -log build/local/strategy_sweep_log/vivado_dcache_fix.log'
```

通过标准：4.1 PASS、4.2 全 PASS、4.3 PASS、4.4 的 `RESULT wns=...` 中
WNS ≥ -0.078（先保住改善，追求 ≥ 0 收 100 MHz）。

## 5. 时序现状与后续方向（修完功能后）

| 版本 | WNS | TNS | 失败端点 | 功能 |
|---|---:|---:|---:|---|
| HEAD 原始 | -0.177 | -2.968 | 31 | PASS |
| DONT_TOUCH 版 | -0.078 | -0.594 | 14 | 死锁 |
| MISS_CAPTURE 版（工作区） | -0.055 | -1.122 | 40 | 死锁 |

修好后最差路径预计在 `id_ex_u/rs1_o_reg → u_dcache/captured_addr_reg/CE`
（miss 检测锥挪到了捕获寄存器使能端）。下一步：使能端解耦——
每次有效请求无条件捕获，或使能提前一拍预计算。

## 6. 环境与入口

- Vivado 2025.2：`C:/ruanjian/2025.2/Vivado/bin/vivado.bat`（Zynq-7000 已装）
- 交叉工具链：`C:/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-`
- Icarus：已在 PATH（`/c/wenjian/.vscode/iverilog/bin/`）
- 工程基准副本：`board/vivado_zynq7000_xc7z020_baseline/`（只读，复制用）
- 隔离构建入口：`build/build_dcache_pipe.tcl`（时序）、`build/screen_dcache_donttouch.sh`（功能筛选）
- 证据：`data/ascon/results/key_lifecycle/sw_dcache_pipe2.json`（FAIL）、
  `build/local/strategy_sweep_log/dcache_head_screen.log`（PASS 对照）、
  `build/reports/dcache_pipe_20261018/`（时序报告）、
  诊断细节 `docs/dcache_fix_checklist_en.md`

## 7. 交付物

1. 修改后的 `src/rtl/dcache.v`（附 diff 说明改了什么、为什么）
2. §4 全部回归日志与 JSON 证据
3. 时序报告与 RESULT 行
4. 在 `docs/dcache_fix_checklist_en.md` 末尾补记验证状态
