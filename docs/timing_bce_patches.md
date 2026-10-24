# 时序补丁 B + E：改动说明、等价性验证与落地步骤

> **2026-10-20 结论更新：B 与 E 不落地（净负收益）。**
> 功能与周期完全等价，但实测 STA：只打 E-v1 是 −0.273 ns（137 失败端点），
> B + E-v2 是 −0.643 ns（649 失败端点），而未打补丁的对照是 +0.007 ns。
> 原因是这个设计的 WNS 对网表扰动有 ±0.7 ns 敏感度，这两处改动只重排使能、不减少逻辑深度。
> 真正落地的是 **A1**（`build/patches/timing_A1_ex_stage_alignment_narrow.patch`）：
> 对齐判定改用 3 位部分和，把 32 位地址加法器从 `trap → flush → ID/EX 使能` 锥里摘掉，
> 实测 +0.016 ns、LUT +3、六种场景周期不变。详见
> [cpu_timing_architecture_plan](cpu_timing_architecture_plan.md) §5.2。
> 本文以下内容保留为过程记录与“为什么不行”的依据。


2026-10-20；owner TBD。目标：在不改变任何周期数的前提下，先清掉时序墙上的第二梯队路径，
为后续 id_ex 旁路网改造（方案 A）腾出余量。

**重要预期**：B + E 落地后 WNS **仍然是 −0.140 ns**，因为这批补丁碰不到最差那条
（`id_ex_u` 内部，CE = `!(flush[2] | stall[2])`，锥里有 32 位地址加法器 → trap/flush）。
它们只是把 #2（`pc → dcache/bus_addr_r/CE`，−0.071）与 ISE 的 cancel 扇出摘掉。
要看到数字变正，必须再做方案 A（见 [cpu_timing_architecture_plan](cpu_timing_architecture_plan.md)）。

未修改 `src/rtl` 下任何文件。补丁可直接 `git apply`：

| 补丁 | 目标文件 | 行数 |
|---|---|---|
| `build/patches/timing_B_dcache_bus_addr_ce.patch` | `src/rtl/dcache.v` | 1 处改成 6 行 |
| `build/patches/timing_E_ascon_ise_cancel_ce.patch` | `src/rtl/ascon/ascon_ise.v` | 状态机重排 + 1 个寄存器 |

```bash
cd <repo_root>
git apply --check build/patches/timing_B_dcache_bus_addr_ce.patch   # 已验证可干净应用
git apply --check build/patches/timing_E_ascon_ise_cancel_ce.patch
git apply build/patches/*.patch
```

---

## B：dcache `bus_addr_r` 的使能不再依赖地址

### 改前
```verilog
else if (store_now || mmio_read_now || mmio_write_now)
begin
    bus_addr_r  <= cpu_addr_i;
    bus_wdata_r <= cpu_wdata_i;
    bus_wmask_r <= cpu_wmask_i;
end
```

### 改后
```verilog
else if (cache_access_fire)     // = (state == IDLE) && !cpu_req_stall_i
begin
    bus_addr_r  <= cpu_addr_i;
    bus_wdata_r <= cpu_wdata_i;
    bus_wmask_r <= cpu_wmask_i;
end
```

### 为什么等价
`store_now`、`mmio_read_now`、`mmio_write_now` 三者的共同前缀就是 `cache_access_fire`
（`store_now = cache_access_fire && cpu_we_i && cacheable`；`mmio_*_now = mmio_access_fire
&& ...`；`mmio_access_fire = cache_access_fire`）。所以改后**只在更多空闲拍**多锁存一次，
而 `bus_addr_r/wdata_r/wmask_r` 只在对应 `bus_*_r` 选通有效时被使用，那些选通仍由原来的
条件产生，值同为同一拍 `cpu_addr_i/cpu_wdata_i/cpu_wmask_i` → 总线行为逐拍不变。

### 消除的路径
原使能锥含 `cpu_addr_i[31:20] == 12'h100`（cacheable 12 位比较）与 `cpu_we_i`，而
`cpu_addr_i` 是 EX 段地址加法器的输出 → 上游一直到 `pc_reg`。
改后使能只剩 `state == IDLE` 与 `cpu_req_stall_i`（都是寄存器/局部比较），
`pc → bus_addr_r/CE`（−0.071 ns，本版 #2 路径）整条消失。

---

## E：`ascon_ise` 的 cancel 不再进 320 位状态使能

### 改前
```verilog
else if (cancel) begin
    state <= 320'd0;            // cancel 直接进 320 位寄存器使能
    mode_p12 <= 1'b0; perm_run <= 1'b0; p_start <= 1'b0; perm_done <= 1'b0;
end else begin ... end
```

### 改后
```verilog
reg cancel_d;
always @(posedge clk or negedge rst_n)
    if (!rst_n) cancel_d <= 1'b0; else cancel_d <= cancel;

assign rd_data = (cancel || cancel_d) ? 32'd0 :
                 ((rd_idx < 10) ? state[32*rd_idx +: 32] : 32'd0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin ... end
    else begin
        p_start <= 1'b0;
        if (perm_ack) perm_done <= 1'b0;
        if (cancel) begin                  // 只杀控制状态（5 位，宽锥无妨）
            mode_p12 <= 1'b0; perm_run <= 1'b0; p_start <= 1'b0; perm_done <= 1'b0;
        end else if (perm_start && !perm_run && !perm_done) begin ... end
          else if (perm_run && p_done)           begin state <= p_out; ... end
          else if (wr_en && wr_idx < 10 && !perm_run && !perm_done) begin state[..] <= wr_data; end
          else if (cancel_d)                     begin state <= 320'd0; end   // 延迟一拍物理清零
    end
end
```

### 安全语义（必须由测试证明的三条）
1. cancel 当拍 `rd_data` 立即读出 0（`cancel` 项在掩码里）；
2. cancel 之后那一拍（`cancel_d`）仍读 0（掩码同时含 `cancel_d`），此时 `state` 在同一拍边沿被清零；
3. **新写入优先于延迟清零**：`cancel` 后下一拍如果就来 `ascon.w`，写入不会被清零分支吞掉
   （清零放在 else-if 链最末）。这一条是本轮改代码时修掉的一个真实坑。

代价：物理零化晚一拍，但可观测数据在 `cancel` 与 `cancel_d` 两拍都被屏蔽。

---

## 验证

等价性脚本 `build/check_bce_patches.sh`：用 `build/local/key_audit/*_timing_acb_*/firmware.hex`
（当前 HEAD 的固件）分别跑**未打补丁的 `src/rtl`** 与**打补丁的副本**
（`build/local/patches/rtl_patched/`，不碰源码），逐项比较 PASS/FAIL 与周期数。

覆盖：ISE 基准、ISE + HOLD_ISE、ISE + RESET_ISE、ISE 安全套件、MMIO(hw)、软件(sw)。

结果见下表（脚本输出 `build/local/patches/equivalence.txt`，逐例日志 `run_<case>_<variant>.log`）。
控制组 = 当前 `src/rtl`（HEAD 3c6f134），打补丁 = `build/local/patches/rtl_patched/`。

| 用例 | 控制组 | 打补丁 | 结论 |
|---|---|---|---|
| ise（KAT 6 项 + 16B bench） | PASS 7 / 2496 cyc | PASS 7 / 2496 cyc | 等价 |
| ise + `+HOLD_ISE` | PASS 8 / 2496 cyc，注入命中 | PASS 8 / 2496 cyc，注入命中 | 等价 |
| ise + `+RESET_ISE`（cancel 路径） | PASS 8 / 2496 cyc，“restarts” 命中 | PASS 8 / 2496 cyc，“restarts” 命中 | 等价 |
| ise 安全套件 | **402 checks PASS / 0 failed** | **402 checks PASS / 0 failed** | 等价（延迟清零无泄漏） |
| hw（MMIO） | PASS 8，crypto 99 / 往返 670 cyc | PASS 8，crypto 99 / 往返 670 cyc | 等价 |
| sw（软件 Ascon） | PASS 9，17353 / 21515 / 17847 / 22094 cyc | 同上，逐项相同 | 等价 |

结论：**B + E 在整机 KAT、安全套件、hold/reset 注入、MMIO、软件五种场景下与未打补丁的
RTL 逐项一致，周期数完全相同**，包括 ISE 的 cancel 路径（安全套件 402 项全过，
说明“延迟一拍物理零化 + 两拍读掩码”没有泄漏旧状态）。


---

## 为什么 C（store buffer）没有放进这一批

C 要解决的问题是 #3/#4（`id_ex → dcache/data_way*/DIADI`，−0.047/−0.019），
**不是最差那条**，而且它必须引入一级写缓冲，进而需要处理：
back-to-back store（缓冲非空时要么停顿要么二级）、同地址 store→load 的字节级转发、
以及 fill 与缓冲写同拍时的端口冲突。风险明显高于 B/E，收益却排在 A 之后。

建议顺序：**B + E → A（id_ex 旁路网，真正决定 WNS）→ 再回来看 C 是否仍是瓶颈**。
如果 A 之后 `u_dcache` 的写口路径重新上榜，再按 [cpu_timing_architecture_plan](cpu_timing_architecture_plan.md)
§3C 的方案补一个 2 项 store buffer。

---

## 落地后的验收命令

```bash
# 1) 功能回归（8 项整机 + 安全 + 单元）
P="C:/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-"
for m in sw hw ise; do python sim/ascon/run_cpu_regression.py --mode $m --label bce --cc-prefix $P; done
python sim/ascon/run_cpu_regression.py --mode ise --security --label bce --cc-prefix $P
python sim/ascon/run_cpu_regression.py --mode ise --reset  --label bce --cc-prefix $P
python sim/ascon/run_cpu_regression.py --mode ise --stall  --label bce --cc-prefix $P
python sim/ascon/run_cpu_units.py --label bce
python sim/ascon/run_rv32_isa.py --label bce      # 49 PASS + 1 既有 rv32ui_ma_data FAIL

# 2) 双策略 STA
/c/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch -source build/build_dcache_pipe.tcl \
  -notrace -tclargs bce
```

判据：功能全 PASS（除既有 `rv32ui_ma_data`）；时序 `RESULT wns=` 双策略均 ≥ 0、TNS 0、失败端点 0；
周期数与上表一致。**注意：WNS 预计仍是 −0.140 附近，不以 WNS 变化作为本批补丁的验收标准，
以“功能等价 + 路径消失”为标准。**
