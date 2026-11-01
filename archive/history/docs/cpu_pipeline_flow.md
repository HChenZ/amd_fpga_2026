# CPU 流水线现状（RV32IM + Zicsr + Ascon ISE）

> 2026-11-01 阅读提示：下面行号、top_pl_bram 层次与时序数字属于10-26静态分析快照。
> 公共 CPU 仍复用，但当前 PUF3 顶层/固件/时钟来源以专用工程为准；见 version_entrypoints.md。

更新：2026-10-26。全部结论来自 `src/rtl` 静态检查，行号在写本文时核对过（`dcache.v` 已含 TIMING C 的
store buffer，`cpu_core.v` 985 行）。周期数标「推」的是从代码推导、未上板实测；实测基线见 §9。

用途：给「准备提改进想法」的人一张底图 —— 先知道每条指令经过哪些寄存器和组合逻辑、哪一级会停、
停下来时谁在动谁在冻；再看 §8 的可改点清单（只列事实与代价，不含取舍结论）。

---

## 0. 一页摘要

- **单发射、顺序、五级**：IF / ID / EX / MEM / WB；无乱序、无多发射、无分支历史表。
- **实际是「4.5 级」**：I-Cache 是「当拍出 hit、下一拍出数据」的取指级，且 `if_id` **不寄存指令**
  （`if_id.v:50-70` 的 `if_inst_o` 是组合透传，只有 `pc/pred_*/inst_valid` 进寄存器）→ IF 和 ID 共用
  一个时钟沿，ID 译码与取指数据在同一拍完成。
- **存储器位置**：I-Cache 用 `pc` 作地址（IF 拍，`cpu_core.v:460`）；D-Cache 用 EX 的 ALU 结果作地址
  （EX 拍，`cpu_core.v:322`）→ load 命中 0 停顿，数据在 MEM 拍进 `mem_stage`。
- **唯一控制中枢**：`stall_ctrl`（`ctrl.v:85-133`），输出 5 bit `stall` + 5 bit `flush` + `jump_sel`，
  优先级固定，见 §4。
- **多周期单元全部阻塞**：乘法 2 拍、除法 ~33 拍、`ascon.p12` ~13 拍，用 `ex_stall_req` 停前三级并每拍
  冲刷 EX/MEM。没有 scoreboard、没有非阻塞执行单元。
- **当前时序基线**：100 MHz、WNS +0.087 ns、WHS +0.021 ns（`project_log/actual_progress.md` 末尾）。

---

## 1. 模块层级

```
top_pl_bram / top / soc_top
└── cpu_core                         src/rtl/cpu_core.v（唯一把各段拼起来的地方）
    ├── predictor                    branch_predictor.v   例化 cpu_core.v:431-448   (* dont_touch *)
    ├── u_icache                     icache.v             例化 cpu_core.v:453-476
    ├── u_if_stage                   if_stage.v           例化 cpu_core.v:508-528   只含 pc 寄存器
    ├── u_if_id                      if_id.v              例化 cpu_core.v:538-576   不寄指令
    ├── u_id_stage                   id_stage.v           例化 cpu_core.v:580-621   1329 行大 case 译码
    ├── id_ex_u                      id_ex.v              例化 cpu_core.v:622-687   (* dont_touch *)
    ├── u_bypass                     bypass.v             例化 cpu_core.v:689-711
    ├── regfile_u                    regfile.v            例化 cpu_core.v:712-730
    ├── u_ex_stage                   ex_stage.v           例化 cpu_core.v:735-812
    │   ├── u_multiplier             mult.v               2 拍、DSP
    │   ├── u_divider                divider.v            32 次移位减法
    │   └── u_ascon_ise              ascon/ascon_ise.v    → p12/p8（ascon_permutation.v）
    ├── u_csr_file                   csr_file.v           例化 cpu_core.v:814-847   trap/中断/mcycle
    ├── u_ex_mem                     ex_mem.v             例化 cpu_core.v:850-887
    ├── u_mem_stage                  mem_stage.v          例化 cpu_core.v:891-909   纯组合
    ├── u_mem_wb                     mem_wb.v             例化 cpu_core.v:910-933
    ├── u_stall_ctrl                 ctrl.v               例化 cpu_core.v:940-982
    └── u_dcache                     dcache.v             例化 cpu_core.v:479-503
```

层级上有一个**反直觉的跨越**：`dcache` 虽然画在 `cpu_core` 顶层，但它的输入地址 `dcache_cpu_addr`
就是 `ex_mem_addr`（`cpu_core.v:322`），输出 `dcache_cpu_rdata` 直接进 `mem_stage`
（`cpu_core.v:901`）。也就是 **D-Cache 物理上例化在顶层、逻辑上属于 EX 级**。同理 `icache` 逻辑上属于
IF 级，地址是 `pc`。

`cpu_core` 自己的端口就是两条存储器通路 + 三根中断线：

| 端口组 | 去向 | 用途 |
|---|---|---|
| `imem_mem_addr` / `imem_mem_rdata` / `imem_icache_miss` | `bus_interconnect` | icache 行填充 |
| `dmem_mem_addr` / `dmem_mem_wdata` / `dmem_mem_load_miss` / `dmem_mem_store_miss` | `bus_interconnect` | dcache 填充、写直达、MMIO |
| `ireq_software` / `ireq_timer` / `ireq_external` | `clint` / 外设 | 中断 |
| `probe_*` 四根 | `cpi_cnt`（MMIO 0x6000） | 性能计数 |

---

## 2. 逐级职责

| 级 | 级间寄存器 | 组合逻辑 | 关键输出 | 代码 |
|---|---|---|---|---|
| **IF** | `pc`（唯一的状态） | 取指地址选择：`jump_sel` TRAP/BRANCH/MSET > `stall` > `pred_taken` > `pc+4`；分支预测当拍给 `pred_taken/pred_target` | `pc` | `if_stage.v:35-54`、`branch_predictor.v:47-48` |
| **IF/ID** | `if_pc_o`、`pred_taken_o`、`pred_target_o`、`inst_valid` | 指令**不寄存**：正常拍 `if_inst_o = imem_inst_i`；`stall` 拍用 `stall_inst_reg` 保持 | `if_inst_o`、`rs1_addr/rs2_addr`、`rs1_en/rs2_en`（提前译码送给 hazard 单元） | `if_id.v:50-70`、`if_id.v:114-126` |
| **ID** | 无（组合段） | 指令译码大 case（`id_stage.v:169-1257`，case 本身在 185）；`regfile` 异步读 + 同拍写穿透；**旁路选择信号在这一拍算好**：`id_sel_ex_mem_*`/`id_sel_mem_wb_*` | `op_sel`、`func_sel`、`imm`、`rs1/rs2`、`reg_w_en`、`mem_r_en`、`is_branch`、`csr_w_en`、`illegal_inst_en` | `id_stage.v:169-1257`、`cpu_core.v:402-411` |
| **ID/EX** | 整条指令的控制 + `rs1/rs2/imm/pc` + 4 个旁路选择 + 预测信息 | `dont_touch`；flush 时把控制位清零（其余数据位保持） | 供 EX 使用 | `id_ex.v:119-192` |
| **EX** | 无（组合段） | 主 ALU（3 个独立 always：arith/logic/shift）、分支比较器（独立于 ALU）、跳转地址、CSR 读写控制、trap 判定、访存地址、多周期单元启动；`bypass` mux 在此级 | `ex_rd_data`、`ex_mem_addr`、`jump_en`、`ex_pc_shift`、`ex_stall_req`、`csr_*`、`trap_*` | `ex_stage.v:270-571`、`cpu_core.v:689-709` |
| **EX/MEM** | `ex_rd_data_o`、`ex_mem_addr_o`、`ex_reg_addr_o`、`ex_op_sel_o`、`ex_func_sel_o`、`ex_reg_w_en_o`、`ex_mem_w_en_o`、`ex_mem_r_en_o`、`ex_is_mul_o` | `dont_touch` | MEM 级输入 | `ex_mem.v:53-100` |
| **MEM** | 无（纯组合） | 字节对齐右移 + load 符号/零扩展；`mem_rd_data = op_sel==LOAD_STORE ? load_data : ex_rd_data` | `mem_rd_data`、`mem_reg_addr` | `mem_stage.v:44-122` |
| **MEM/WB** | `mem_rd_data_o`、`mem_reg_addr_o`、`mem_reg_w_en_o` | 只有 stall 保持，没有 flush | 写回 | `mem_wb.v:28-52` |
| **WB** | — | `regfile` 同步写 + 读口写穿透 | 写 `x0..x31` | `regfile.v:30-60` |

---

## 3. 一条指令走 5 拍（逐拍表）

以 5 条指令背靠背为例（假设全部 cache 命中、无冒险）：

| 拍 | add x3 | lw x4 | add x5(用x4) | sw x6 | beq |
|---|---|---|---|---|---|
| T | IF | — | — | — | — |
| T+1 | ID（译码+读寄存器） | IF | — | — | — |
| T+2 | EX（ALU） | ID | IF | — | — |
| T+3 | MEM | **EX（由 ALU 输出算地址 → dcache 当拍 hit）** | **ID → 检测 load-use → 1 拍气泡** | IF | — |
| T+4 | WB | **MEM（BRAM 寄存输出 = 数据）** | ID（重发） | ID | IF |
| T+5 | — | WB | EX（旁路取 ex_mem/mem_wb 数据） | EX（rs2 → `ex_w_data` → store buffer） | ID |
| T+6 | | | | MEM（`bus_mem_we` + `sb_commit` 下一拍写 BRAM） | EX（分支比较 + 预测校验） |

要点：
1. **load 的地址在 EX 拍就送到 dcache**（`cpu_core.v:322`），所以 MEM 拍数据已经在 `mem_stage` 的
   输入端 → load-use 只需 1 拍气泡（`ctrl.v:56-73`），不是经典的 2 拍。
2. **store 的数据在 EX 拍就位**（`ex_w_data`，`cpu_core.v:286-314`），EX 拍发起，下一拍进 store buffer
   提交到 BRAM（`dcache.v:283-319`），同时同一拍把写请求打到总线（`dcache.v:530`）。
3. **分支在 EX 拍才出结论**，比较器独立于主 ALU（`ex_stage.v:178-183`），所以分支本身不占 ALU。

指令类别 → 经过的单元（便于评估「改哪条指令收益最大」）：

| 类别 | EX 用到的单元 | 额外环节 |
|---|---|---|
| R/I 型算术逻辑移位 | ALU 三个 always 之一 | 无 |
| load | 地址加法器 `id_rs1+imm`（`ex_stage.v:433`） | dcache（EX 拍）+ mem_stage 对齐扩展 |
| store | 地址加法器 + `ex_w_data` 拼字节 | dcache store buffer + 总线写 |
| branch/jal/jalr | 比较器 / `pc+imm` / `rs1+imm` | predictor 更新（EX 拍） |
| mul | `u_multiplier` | 2 拍，`ex_stall_req` |
| div/rem | `u_divider` | ~33 拍，`ex_stall_req` |
| csr* | `csr_file` 异步读 + 组合写数据 | 无额外拍 |
| ecall/ebreak/mret | trap 判定 | 冲刷 IF/ID/ID-EX/EX-MEM |
| ascon.w / ascon.rd | ISE 状态寄存器读写 | 1 拍，无停顿 |
| ascon.p12 / p8 | `ascon_ise` → `p12`/`p8` | ~13 / ~9 拍，`ex_stall_req` |

---

## 4. 控制层级（stall / flush）

`stall_ctrl` 是全机唯一做流水线决策的地方（`ctrl.v:85-133`），输出：

```
stall[4:0] = {IF, IF/ID, ID/EX, EX/MEM, MEM/WB}    ctrl.v:40-41
flush[4:0] = 同上
jump_sel   = {PC_PLUS_4, BRANCH, TRAP, MSET}
```

消费者（行号已核对）：`if_stage.stall=stall[4]`（`cpu_core.v:515`）、`if_id.stall=stall[3]`（`:550`）、
`id_ex.stall=stall[2]`（`:663`）、`ex_mem.stall=stall[1]`（`:868`）、`mem_wb.stall=stall[0]`（`:921`）。
`flush[3]` 进 if_id（`:549`），`flush[2]` 进 id_ex（`:664`），`flush[1]` 进 ex_mem（`:867`）。
`dcache.cpu_req_stall_i` 接的是 `stall[2]`（`:488`）。

**优先级（同一拍只能走一条分支）**：

| 序 | 条件 | stall | flush | jump_sel | 周期代价（推） | 代码 |
|---|---|---|---|---|---|---|
| 1 | `inter_req \|\| jump_trap_en` | — | `[3:1]` | TRAP | 冲刷 3 段，重取 2 拍 | `ctrl.v:91-95` |
| 2 | `jump_trap_out`（mret） | — | `[3:1]` | MSET | 同上 | `ctrl.v:96-100` |
| 3 | `dcache_stall` | `11111` 全停 | — | — | load miss 全程；MEM/WB 也停，用来兜住垃圾数据 | `ctrl.v:101-104` |
| 4 | `dmem_axi_stall_req` | `11111` | — | — | 总线写缓冲满 | `ctrl.v:105-108` |
| 5 | `ex_stall_req`（mul/div/p12） | `[4:2]` | `[1]` | — | 每拍把 EX/MEM 变气泡，逐拍累加 | `ctrl.v:109-114` |
| 6 | `jump_en`（预测错） | — | `[3:2]` | BRANCH | 杀 2 条 + icache 重对齐，**≈3 拍** | `ctrl.v:115-119` |
| 7 | `load_use_rs1/rs2` | `[4:3]` | `[2]` | — | 1 拍 | `ctrl.v:120-125` |
| 8 | `icache_stall \|\| fence_i_stall` | `[4:3]` | `[2]` | — | 每拍丢一条 ID 指令 | `ctrl.v:126-131` |

不直观、值得记住的四点：

1. **icache 停不是「冻住」而是「丢指令」**：`stall[4:3]` 保住 pc 和 if_id，同时 `flush[2]` 把 ID/EX
   变成气泡（`ctrl.v:130`）。所以 I-Cache 未命中的每一拍都白扔一条已经取到的指令；不过指令本身没寄存，
   重取的就是同一个地址（`if_id.v:50-70` 的保持 mux），不会错。
2. **dcache 停是整机停**（`5'b11111`），因为它要保住 MEM/WB 里那条 load 的写回时机；只要 MEM/WB 一动，
   写回的就是填充前的垃圾。
3. **多周期指令停的是前三级**，`flush[1]` 每拍把 EX/MEM 清掉，因此除法执行期间 EX 里没有有效指令，
   一旦 `div_done` 拉高，同一拍 `ex_stall_req` 放开，结果才被 EX/MEM 采走。
4. **`jump_en` 优先于 load-use**：分支自己若同时命中 `load_use`（操作数来自上一条 load），走的是
   错预测分支 —— 因为 `flush[3:2]` 会把 ID 里那条依赖指令一起冲掉，气泡根本不需要插。顺序反过来
   （先插气泡）只会多花 1 拍。

### 4.1 各级「谁在动、谁被冻」

| 事件 | 动的级 | 被冻的级 | 说明 |
|---|---|---|---|
| icache miss/未对齐 | — | IF + IF/ID 保持，ID/EX 清空 | 后端自然排空 |
| dcache load miss | dcache FSM（MISS_CAPTURE/FILL） | 全部 5 级 | 数据在 `fill_done_r` 那拍由 mux 补回 |
| bus 写满 | 总线 | 全部 5 级 | `bus_interconnect.v:340` |
| mul（2 拍） | 乘法器 | IF/IF-ID/ID-EX | EX/MEM 每拍清 |
| div（~33 拍） | 除法器 | 同上 | 每拍 `count+1` |
| ascon.p12（~13 拍） | ISE | 同上 | `round_cnt` 0→12 |
| 预测错 | pc、predictor | IF/ID、ID/EX 清 | predictor 在 EX 拍更新 |
| trap | csr_file、pc | IF/ID、ID/EX、EX/MEM 清 | `jump_sel=TRAP` |

---

## 5. 冒险与旁路

### 5.1 三条前递路径

| 生产者位置 | 消费者位置 | 机制 | 代码 |
|---|---|---|---|
| EX（`ex_rd_data`） | EX +1 拍 | `ex_mem_rd_data` → `bypass` 的 `sel_ex_mem_*` | `bypass.v:22-42` |
| MEM/WB | EX +2 拍 | `mem_rd_data_o` → `bypass` 的 `sel_mem_wb_*` | 同上 |
| WB | ID 同拍 | `regfile` 读口写穿透（`w_reg_en && r_addr==w_addr`） | `regfile.v:44-60` |

旁路选择信号**在 ID 拍算、寄进 ID/EX 用**（`cpu_core.v:402-411`）：
```verilog
id_sel_ex_mem_rs1 = if_id_rs1_en && id_ex_rd_valid && (rs1_addr == w_reg_waddr_o);
```
这就是时序报告里那条 `id_ex/sel_mem_wb_rs1_o_reg → rs2_o_reg/CE` 的源头 —— 选择信号和操作数在
`id_ex` 内部汇合（`docs/cpu_timing_architecture_plan.md:13-18`）。

### 5.2 唯一的真冒险：load-use

```verilog
mem_rd_valid_1st = id_ex_mem_r_en && (id_ex_reg_addr != 0);   // ctrl.v:56
rs1_hit_1st      = mem_rd_valid_1st && (id_ex_reg_addr == rs1_addr);
early_rs1_hazard = rs1_hit_1st;                               // ctrl.v:66
```
- **停顿 1 拍**；`rs*_hit_2st`（对比 EX/MEM 里的 load）算了但**没人用**（`ctrl.v:62-63` 死逻辑）——
  因为 load 在 EX 拍就访问了 RAM，数据到 MEM 结束时已经可用，不需要第二级。
- 该检测用的是 `if_id` 提前译码的 `rs1_en/rs2_en`（`if_id.v:117-126`），不是 `id_stage` 的输出，
  目的是把比较提前一拍、缩短关键路径。

### 5.3 没有检测的依赖（当前靠"顺序"自然正确）

| 场景 | 现状 | 风险 |
|---|---|---|
| CSR 读后立即用（`csrrw` 紧接依赖它的指令） | `csr_rdata` 在 EX 当拍异步读，写回走正常 WB 旁路 | 无（读是异步组合，写是同步） |
| store 后紧接 load 同地址 | dcache 内 store buffer 定向转发 `sb_fwd_*`（`dcache.v:346-375`） | 无 |
| fence.i 后取指 | `fence_i_stall` 等总线写空（`cpu_core.v:181-190`） | 无 |
| ascon.w 后紧接 ascon.rd 同字 | 两者都在 EX 组合/1 拍内完成，`ascon_ise` 内状态同步写 | 无（都是 1 拍指令） |

---

## 6. 存储子系统在流水线中的位置

### 6.1 I-Cache（`icache.v`）

- 结构：2 路组相联、64 组、4 字/行 = 2 KB；tag 用分布式 RAM 异步读，data 用两块 BRAM（各自独立读口）。
- 命中：`hit = (hit_way0||hit_way1) && state==IDLE`（`icache.v:80-82`）；**当拍**成立（tag 异步读）。
- 数据：`data_way*_out` 是 BRAM 寄存输出，**下一拍**才有（`icache.v:165-183`）。
- 停顿守卫：`cpu_stall_o = !(hit && hit_r)`（`icache.v:163`）—— `hit` 是"当前地址（前瞻）命中"，
  `hit_r` 是"总线上这拍的数据来自一次命中"。两者都真才放行。
- 周期：稳态命中 **1 条/拍**；新行首次访问 +1 拍；miss = 4 字 burst + 2 拍对齐；**每次 redirect
  （分支/异常/中断）`hit_r` 被清零（`icache.v:143-144`）→ 固定多 1 拍**。

### 6.2 D-Cache（`dcache.v`）

- 结构：2 路、64 组、4 字/行 = 2 KB；写直达 + 写不分配；含 **1 项 store buffer**（TIMING C，`dcache.v:283-319`）。
- 命中：`hit = cacheable & valid & tag` 两路相或（`dcache.v:83-85`）；**无 `state==IDLE` 门控**，
  靠 `cache_access_fire = (state==IDLE) && !cpu_req_stall_i` 抑制（`dcache.v:120`）。
- 节拍：地址（EX 拍 ALU 输出）→ 当拍 hit → 下一拍 BRAM 输出进 MEM（`dcache.v:269`、`385-386`）。
- 写：EX 拍捕获进 buffer，下一拍 `sb_commit` 写两路 BRAM（`dcache.v:392-424`）；同时总线写直达；
  store→load 同字靠 `sb_fwd` 覆盖（`dcache.v:346-375`）。
- 总线侧还有一级写 FIFO：`cpu_axi_bridge` 里 `wdata/waddr/mask_fifo[0:7]`，`full = fifo_cnt==4`
  → **有效深度 4 项**（`cpu_axi_bridge.v:67-73`、`164-167`）；满了就 `cpu_axi_stall_req` 停整机。
- **store miss 会把该 set 两路 valid 全清**（`dcache.v:584-595`）→ 一次 store miss 毁掉两行，
  之后同 set 的 load 要重新填充。这是写直达下"保守"的做法，不是必需。
- load miss：`MISS_CAPTURE`(1) + `FILL`(4 字) + 对齐（`dcache.v:98-103`、`437-462`），期间整机停。
- MMIO：`cacheable = addr[31:20]==12'h100`（`dcache.v:52`）；其它地址走固定 3 拍 MMIO 读
  （`dcache.v:244-264`）。

### 6.3 存储器通路一览

```
IF:  pc ──► icache(tag 当拍 / data 下拍) ──► if_id 组合透传 ──► ID 译码
EX:  ex_mem_addr(ALU) ──► dcache(tag 当拍 / data 下拍) ──► mem_stage 对齐扩展 ──► mem_wb ──► regfile
      miss ──► bus_interconnect ──► cpu_axi_bridge ──► axi_bram_ctrl ──► blk_mem_gen
```

---

## 7. 多周期单元时序

| 单元 | 结构 | 延迟（推） | 控制信号 | 代码 |
|---|---|---|---|---|
| `multiplier` | 操作数打一拍 → DSP 乘法打一拍 → `mul_done` 保持到 ack | 2~3 拍 | `mul_start=~mul_done`、`ex_stall_req=~mul_done` | `mult.v:63-83`、`ex_stage.v:318-336` |
| `divider` | 每拍 1 位恢复余数法，`count` 0→31 → DONE | ~33 拍 | `div_start=~div_done`、`ex_stall_req=~div_done` | `divider.v:149-177` |
| `p12` | 每拍 1 轮（`ascon_round.v` 一个组合轮），`round_cnt` 0→12 | ~13 拍 | `ascon_perm_start=~ascon_perm_done` | `ascon_permutation.v:47-57` |
| `p8` | 同上，8 轮 | ~9 拍 | 同上 | `ascon_permutation.v:74-134` |

三者的共同点：**都不接受新指令**，整条流水线等它；`cancel` 端口在中断/异常时清零私有状态
（`ex_stage.v:134`、`158`、`ascon_ise.v:45`）。

对 CPI 的直接影响：软件版 AEAD 每次 `p12` 花 13 拍时 CPU 完全空转；ISE 版 2559 拍里 p12 的占比
可以从 `mcycle` 差分直接量（见 §9）。

---

## 8. 可改点清单（按层，只列事实+代价）

### 8.1 前端 / 取指

| 编号 | 现状 | 改法 | 周期收益 | 时序/面积代价 | 风险 |
|---|---|---|---|---|---|
| F1 | 1 条/拍取指，icache 单读口 | 加第二个读口或复制 BRAM → 每拍取 2 字 | 取指带宽翻倍 | BRAM/走线翻倍，`hit` 与路选择逻辑 ×2 | 需要 ID 双发射/或仅供预测用 |
| F2 | 无预取 | 命中时顺带预取下一行（用 BRAM 第二口或空闲拍） | 减少 cold miss | 与 fill 抢总线 | 需要新的请求队列 |
| F3 | 指令不进 if_id 寄存器 | 给 `if_inst_o` 加寄存器，切断 icache→ID→id_ex 长链 | 0（稳态） | **时序收益大**（那是当前最长的组合段之一） | 需要重排 pc/inst 对齐，可能 +1 拍重定向代价 |
| F4 | `icache_stall` 每拍丢一条 ID 指令 | 改成「保持」而非「冲刷 ID/EX」 | miss 时少丢指令 | 需要 ID/EX 的 stall 语义改造 | 与 dcache 全停语义冲突，要统一 |

### 8.2 分支

| 编号 | 现状 | 改法 | 收益 | 代价 | 风险 |
|---|---|---|---|---|---|
| B1 | BTB 64 项直连 + 2-bit BHT，无历史、无 RAS（`branch_predictor.v`） | 加返回地址栈（jalr 的 rs1 多半是 `ra`）；BTB 扩到 256 | 函数调用/返回少错 | 少量 LUTRAM | 需要 jalr 的 rd==ra 判断 |
| B2 | 预测错惩罚 ≈3 拍（杀 2 条 + icache 对齐 1 拍） | 分支解析提前到 ID（ID 加比较器 + 前递到 ID） | 惩罚 3 → 2 | ID 关键路径变长 | `id_ex` 是 dont_touch，改动波及面大 |
| B3 | `jal` 首次执行必错（BTB 未分配） | jal 静态预测「必跳 + 目标=pc+imm」（不需要 BTB） | 每个 jal 首次省 3 拍 | 几乎 0 | 与现有 mispredict 逻辑叠加要小心 |
| B4 | 预测器在 EX 拍更新 | 保持不变（EX 更新是安全的） | — | — | 别挪到 ID（会用到未确定的结果） |

### 8.3 冒险 / 停顿

| 编号 | 现状 | 改法 | 收益 | 代价 |
|---|---|---|---|---|
| H1 | load-use 停 1 拍 | 除非把 dcache 读到 MEM 结束（当前已是最优单口方案），否则压不下去 | — | — |
| H2 | dcache 内 store buffer 1 项（`dcache.v:283-319`），总线侧写 FIFO 4 项（`cpu_axi_bridge.v:164`） | dcache buffer 加到 2~4 项 | 连续 store 少停 | 面积、转发比较器变多；与 bridge FIFO 的背压语义要重新对齐 |
| H3 | `rs*_hit_2st` 死逻辑 | 删掉 | 0 | 无（只是可读性） |
| H4 | 除法整机阻塞 ~33 拍 | radix-4（16 拍）/ radix-8；或非阻塞 scoreboard | 除法密集代码明显 | 面积、控制复杂度 |

### 8.4 执行

| 编号 | 现状 | 改法 | 收益 | 代价 |
|---|---|---|---|---|
| E1 | 单 ALU，分支比较器独立 | 已是最省的结构 | — | — |
| E2 | 移位器组合 barrel | 可换 DSP（`use_dsp`）| 时序 | 资源 |
| E3 | `ascon.p12` 13 拍串行轮 | 2 轮/拍 或 4 轮/拍（展开 `ascon_round`） | ISE 版周期数接近-90% | 时序（当前 100 MHz 只剩 +0.087 ns，塞不下）、面积 |
| E4 | 无 Zbb（`clz/rev8/andn/orc.b`） | 加几条位操作指令 | 软件 Ascon 里位运算多 | 译码 + 执行 + 软件重写 |

### 8.5 存储

| 编号 | 现状 | 改法 | 收益 | 代价 |
|---|---|---|---|---|
| M1 | D-Cache 写直达、写不分配 | 改 write-allocate + 写回 | store miss 不再毁行 | 一致性、脏行写出、复杂度 |
| M2 | store miss 清两路 valid（`dcache.v:584-595`） | 写直达下**只清被写那一路的 tag 匹配失败即可**，不命中就什么都不用清 | 同 set 的命中率回升 | 要论证「写了但没分配」不会造成旧数据可见 |
| M3 | 无 MSHR/行锁定 | 加 miss 队列 | 减少 miss 期间的停顿 | 大改 |
| M4 | 4 字/行、2 路、2 KB | 8 字/行 或 4 路 4 KB | miss 率 | BRAM（当前 34.5 tile） |

### 8.6 系统 / 异常

| 编号 | 现状 | 改法 | 备注 |
|---|---|---|---|
| S1 | `mstatus` 只实现 MIE/MPIE（`csr_file.v:241-247`） | 补 MPP、MPRV 等 | 竞赛不要求，除非要跑更多软件 |
| S2 | 中断优先级 external > timer > software（`csr_file.v:118-126`） | 按 RISC-V 规范 MEI > MSI > MTI 排 | **待核实是否要改**：当前实现与规范顺序不同 |
| S3 | 中断接受晚一拍（`inter_slow_ok_q`，`cpu_core.v:349-365`） | 若恢复当拍判决会重新引入 pc→icache→flush 长链 | 是 TIMING D 的产物，别轻易回退 |
| S4 | `mip` 只有硬件置位、无软件写（`csr_file.v:209-221`） | 允许写 `mip`（规范要求 MSIP 可写） | 若软件用 `csrw mip` 会静默失效 |
| S5 | 无 debug / 无 U-mode | — | 竞赛不要求 |

---

## 9. 怎么自己量（改进前必做）

1. **四个硬件计数器**（MMIO 0x6000，`cpi_cnt.v`）：`cnt_inst` / `cnt_stall_ld` / `cnt_stall_md` /
   `cnt_flush_br`。读它们能得到「指令数、load-use 停顿、多周期停顿、分支冲刷」四路占比 —— 这是判断
   该改哪一块的唯一诚实依据。
2. **`mcycle`**（CSR 0xB00 / 0xB80，`csr_file.v:60-61`、`132-138`）：整段代码的总周期。
3. **已有仿真基线**：软件版 AEAD 16840 拍 / MMIO 664 拍 / ISE 2559 拍（`docs/board_bringup_plan.md:91`）。
   任何 RTL 改动都要先复现这三个数，再谈收益。
4. **时序基线**：100 MHz WNS +0.087 ns、WHS +0.021 ns（`project_log/actual_progress.md` 末尾）。
   凡是「加工逻辑」的改动都要同时报 WNS 变化，否则数字不完整。
5. 想看单条路径：`docs/cpu_timing_architecture_plan.md` 与 `project_log/lessons_learned.md` 里已有
   pc→dcache、id_ex 内部、sel_* 扇出三类路径的历史数据，可直接复用做对比。

---

## 10. 未核实 / 待定

- §7 的所有延迟是代码推导；没有用仿真逐拍数过（可用 §9 的计数器校准）。
- `clint` 定时器中断是电平式比较 `irq_timer = (mtime >= mtimecmp)`（`clint.v:124`），
  `mtimecmp` 复位为全 1（`:71`）—— 已核实，但「软件写 mtimecmp 后是否立即清中断」取决于软件是否
  重写 mtimecmp，本文未验证运行行为。
- §8 的收益列全部是「方向性估计」，没有做任何实现或回归；任何一条落地前必须先跑 §9 的基线。
- 本文不含把 `dcache` 移进 EX 级改名/重组之类的结构重排建议 —— 那类改动会同时改时序与功能，
  不属于「先看清流程」的范围。
