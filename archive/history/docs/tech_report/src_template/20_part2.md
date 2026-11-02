## 第二部分 系统组成及功能说明

### 2.1 整体介绍

处理器采用经典五级顺序流水线结构：取指（IF）、译码与读寄存器（ID）、执行（EX）、访存（MEM）、
写回（WB），并配置 I-cache、D-cache、分支预测器、旁路网络与集中式冒险控制。顶层 `cpu_core` 之下
的并列单元构成如下表。

<span class="tabcap">表 2-1</span> **处理器功能单元组成**

| 单元 | 文件 | 职责 |
|---|---|---|
| 取指 | `if_stage.v`、`if_id.v` | PC 生成、I-cache 查询、预测目标选择、冲刷响应 |
| 译码 | `id_stage.v`、`id_ex.v` | 指令字段解析、立即数生成、结果类型（ResultKind）判定、寄存器索引下发 |
| 执行 | `ex_stage.v`、`mult.v`、`divider.v` | ALU 与移位、分支条件判定、多周期乘除、Ascon ISE 接入 |
| 访存 | `mem_stage.v`、`mem_wb.v` | load/store 对齐与 D-cache 事务、总线请求 |
| 写回 | `mem_wb.v`、`regfile.v` | 结果选择、GPR 写端口、CSR 写端口 |
| 控制 | `ctrl.v`（`stall_ctrl`）、`bypass.v` | 5 位 `stall/flush` 向量、两级旁路选择 |
| 存储 | `icache.v`、`dcache.v`、`bus_interconnect.v` | 各 64 组 × 4 字/行；地址译码与总线状态机 |
| 系统 | `csr_file.v`、`clint.v`、`uart_ctrl.v`、`gpio.v`、`cpi_cnt.v` | 特权 CSR、定时器中断、串口、GPIO、CPI 事件计数 |
| 互连 | `cpu_axi_bridge.v`、`axi_full_master.v`、`soc_top.v`、`top.v`、`top_pl_bram.v` | 内部总线至 AXI4 master、BRAM 与外设；板级顶层与时钟复位 |

> <span class="figslot" data-src="2-1">图 2-1</span> **处理器与 SoC 总体框图**：CPU 五级流水、I/D-cache、旁路与
> 冒险控制、总线互连、AXI BRAM、UART/GPIO/CLINT/CPI，以及 Ascon MMIO 与 EX 级 ISE。
> 当前系统时钟由 PS7 FCLK0 提供，PL-only 顶层仅作历史对照。

数据通路的关键接口约定如下：

- **指令与数据的地址空间由 Cache 区分**：I-cache 与 D-cache 独立查询同一片 BRAM 区域（统一编址，
> `0x1000_0000` 起 128 KiB）；不可 Cache 的访问（MMIO）直接经总线完成，不进入 Cache；
- **结果类型于 ID 级判定**：指令在译码阶段即标注结果来源（算术、逻辑、移位、load、跳转链接、乘法），
  EX 级据此选择数据通路，避免在执行级重复译码；
- **旁路于 ID 级选路、于 EX 入口生效**：优先级为 `EX/MEM > MEM/WB`（`bypass.v` 中两级 MUX）；
  load-use 冒险以停顿方式解决，不采用推测加重放；
- **CSR 读写置于 EX 级**：`mepc`、`mcause`、`mtvec` 与陷入入口位于同一路径，使 `ecall` 与 `mret` 的
  PC 修复仅有单一实现。


### 2.2 处理器架构与设计思路

#### 2.2.1 设计目标与总体思路

处理器采用 RV32 五级流水线结构，以下保留当时的设计讨论，
而是在其上完成器件迁移、时序改造与密码加速扩展。设计围绕三个目标展开：

1. **在 XC7Z020 上以 100 MHz 稳定运行**。7020 的 LUT 与布线资源有限，结构选择优先考虑时序可收敛，
   而不是追求更高的单线程性能。
2. **为三种 Ascon 实现提供公平的对照平台**。软件、MMIO 与定制指令必须运行在同一 CPU、同一存储层次、
   同一测量方式（`mcycle`）下，周期差异才只来自实现方式本身。
3. **让定制指令接入后不破坏既有流水线语义**。新增指令要能被停顿、被陷入取消，且不会因停顿而重复执行。

据此形成以下设计取舍：

<span class="tabcap">表 2-2</span> **处理器设计取舍**

| 决策 | 选择 | 理由与代价 |
|---|---|---|
| 流水线深度 | 经典五级顺序流水，不做乱序与多发射 | 控制逻辑可审查、可验证；单发射使周期计数可直接比较 |
| 冒险控制 | `ctrl.v` 集中产生 stall / flush，按固定优先级裁决 | 多种停顿源（Cache、总线、乘除、ISE、load-use）叠加时只有一处裁决，便于证明正确性 |
| 数据冒险 | EX/MEM、MEM/WB 两级旁路，load-use 停顿一拍 | 不做推测加重放，以少量停顿换取简单可靠的控制 |
| 译码 | ID 级标注结果类型（ResultKind）并随流水传递 | 后级按类型选数据通路，避免在 EX/WB 重复译码，缩短关键路径 |
| 存储层次 | 分离 I/D-cache，代码与数据统一编址于 128 KiB BRAM；MMIO 绕过 Cache | 取指与访存并行；外设访问保持顺序与副作用语义 |
| 分支预测 | 64 项 BTB + 2-bit BHT，分布式 RAM 零延迟读出 | 小表面积与时序代价低；命中率未单独实测，不作性能结论 |
| 加速接入 | MMIO 外设挂总线；ISE 置于 EX 级、持有 320-bit 私有状态 | 前者不改 CPU，后者省去总线往返；ISE 以 hold / ack 握手跨多拍执行 |

时序收敛同样体现上述思路：先用 33 组实现策略确定工具能回收的余量，再按失败端点归因做结构改造
（D-cache 增加 MISS_CAPTURE、乘法器寄存器化、ISE 局部复位），而不是降低频率（见 2.2.11 节）。


#### 2.2.2 流水线微架构

图 2-2 按流水级分列给出处理器微架构。顶部为贯穿各级的集中冒险控制，竖条为四组流水寄存器，
底部为总线与 SoC 外设。

> <span class="figslot" data-src="2-12">图 2-2</span> **RV32 处理器流水线微架构**：五级流水各级功能单元、流水寄存器、
> 集中冒险控制、旁路与写回、分支重定向与预测器训练，以及 I/D-cache 与 MMIO 的总线出口。

- **IF**：PC 按"陷入向量 > 分支重定向 > 预测目标 > PC+4"选择；分支预测器在同拍组合读出目标，
  I-cache 命中当拍返回指令，未命中则停顿取指并整行回填。
- **ID**：并行生成五种立即数，标注结果类型；寄存器堆双读一写并带写读直通；
  load-use 冒险在此检测，命中时冻结前两级并插入气泡。
- **EX**：旁路网络先选出最新操作数，再送入 ALU、乘除法、CSR 与 Ascon ISE。分支在 EX 级裁决，
  误预测时重定向 PC 并冲刷两条较年轻指令，同时训练 BTB/BHT。乘除与 ISE 为多周期单元，
  通过 `ex_stall_req` 冻结前级。
- **MEM**：可 Cache 地址走两路组相联 D-cache；MMIO 地址绕过 Cache，直接发出单拍注册请求。
- **WB**：按结果类型选择 ALU、load、PC+4 或 CSR 值写回寄存器堆，并经旁路回送 EX。

各单元的实现细节见 2.2.3–2.2.10 节，结构改造汇总见 2.2.11 节。


#### 2.2.3 取指单元（IF）

取指级的职责为每周期产生一个 PC 及一条指令，需同时处理 Cache 命中、分支预测与流水线冲刷三项相互
耦合的条件。

- **PC 来源优先级**（由高至低）：陷入与中断入口、EX 级分支重定向（`jump_en`）、分支预测目标、
  `pc + 4`；
- **I-cache 查询**：容量 1 KiB，64 组 × 4 字/行，直接映射；tag 命中时当拍返回。未命中时进入 `FILL`
  状态并向总线发出一次 burst 请求，`ctrl.v` 收到 `icache_stall` 后冻结 IF 与 IF/ID；
- **预测器接口**：取指级以当前 PC 组合读出 `pred_taken` 与 `pred_target`（分布式 RAM，零延迟），
  预测命中时当拍改选 PC，不增加流水级；
- **冲刷**：`flush[4]` 清除 IF，`flush[3]` 清除 IF/ID。分支重定向（`jump_en`）时 `ctrl.v` 置
  `flush[3:2]`（清除 IF/ID 与 ID/EX 两级，作废两条较年轻指令）；陷入、`mret` 与外部中断时置
  `flush[3:1]`（额外清除 EX/MEM）。各级冲刷的流水线代价随清除级数而变，本文不作未经实测的拍数结论。

> <span class="figslot" data-src="2-3">图 2-3</span> **IF 级数据通路与冲刷语义**：PC 选择、I-cache 查询、
> 预测改选、miss FILL 与分支冲刷（flush[3:2] 两级）；为结构示意，不作为实测周期波形。


#### 2.2.4 译码单元（ID）

译码级完成字段解析与指令意图标注，为流水线中控制逻辑最密集的一级。

- **立即数生成**：I、S、B、U、J 五种格式并行生成，由 opcode 选择；
- **寄存器堆**：32 × 32-bit，双读一写；`x0` 恒为零（写端口屏蔽）；同步写、组合读。
  读地址与有效写地址相同时直接返回 `w_reg_data`，存在寄存器堆内部写读旁路，并非返回旧值；
- **结果类型（ResultKind）**：将指令映射为六类结果来源（算术、逻辑、移位、load、跳转链接、乘法），
  该标注随流水线传递至 EX/MEM/WB，为后级"不再重复译码"的基础；
- **CSR 指令与陷入**：`csrrw`、`csrrs`、`csrrc`、`ecall` 与 `mret` 于 ID 级识别为 SYSTEM 类，具体
  读写与 `mepc`、`mcause` 更新在 EX 级完成；
- **load-use 检测**：ID 级比较 `id_ex.rd` 与当前 `rs1`、`rs2`，命中时置 `stall_ld`，由 `ctrl.v`
  冻结 IF 与 IF/ID（`stall[4:3]`），并在 ID/EX 插入气泡（`flush[2]`）；EX/MEM 不再清除。


#### 2.2.5 执行单元（EX）

执行级为多功能并行与多周期串行相结合的混合结构，本作品的两处关键改造均作用于该级。

**并行功能单元**：ALU（加、减、逻辑、比较、移位）、分支条件判定、跳转链接地址生成与 CSR 读写均在
单周期内完成；乘法器 `mult.v` 完成 32 × 32 有符号与无符号乘法（RV32M 的
`mul`、`mulh`、`mulhsu`、`mulhu`），综合后被映射为 4 个 DSP48E1（实现报告 DSP 利用率 4／220），
映射结果由工具的乘法推断产生而非显式例化 DSP 原语；除法器 `divider.v` 为迭代式多周期实现
（`div`、`divu`、`rem`、`remu`）。

**多周期与握手**：执行级向 `ctrl.v` 发出 `ex_stall_req`，后者冻结 IF、IF/ID 与 ID/EX 并在 EX/MEM
插入气泡。多周期单元完成时将结果与 `done` 一并锁存，直至被确认（ack）方予释放。乘法器于本轮改造中
增加 `mul_ack` 与 `cancel` 两个内部端口，其契约为：输入寄存器至乘积寄存器，接受后下一拍乘积与
`mul_done` 有效；`done` 与结果保持至 ack；cancel 或 reset 取消且不产生完成信号。该契约使"乘法结果
在 EX 级保持"与"陷入取消"两项行为互不干扰。

**Ascon ISE 接入点**：custom-0（opcode `0x0b`，funct7 = 0，funct3 区分四类操作）在该级被识别为一类
带状态的多周期指令，其读写对象为 ISE 内部的 10 个 32-bit 状态字（§2.3.3.4），而非通用寄存器。执行级以
hold 方式使流水线跨越 P12/P8 的多拍执行，`done` 保持至指令推进；"完成有效方予退休"的判据保证该指令
不会因跨过完成的停顿而被重复执行。

> <span class="figslot" data-src="2-4">图 2-4</span> **EX 级功能单元与多周期握手状态图**：含 `Idle → Busy → Done →
> ack` 转换、陷入与中断取消分支，以及 ISE hold 与 ALU 单拍路径的复用关系。


#### 2.2.6 访存与写回（MEM/WB）及 Cache 结构

访存级将执行级的地址与数据转换为 D-cache 事务或总线事务；写回级完成 GPR 与 CSR 写回。

**D-cache 结构**（`dcache.v`）：容量 2 KiB，64 组 × 4 字/行，两路组相联，采用 write-through 策略
（store 不等待填充），tag 与数据分存；不可 Cache 的地址（MMIO 窗口）绕过 Cache，改为单拍注册请求。
状态机为 `IDLE / MISS_CAPTURE / FILL` 三态：

- `IDLE`：查询 tag，命中即返回；
- `MISS_CAPTURE`：本轮新增状态，将 miss 的 tag、index、way 及请求属性锁存一拍，使"miss 判定至总线
  请求"不再经过单一长组合路径；
- `FILL`：等待总线填充完成，逐字写入 way。

**I-cache**：容量 1 KiB，64 组 × 4 字/行，直接映射，状态机为 `IDLE/FILL` 两态，未命中时整行填充。

**写回**：`mem_wb` 选择访存结果、load 数据、PC + 4 或 CSR 读值，驱动 `regfile` 写口；`x0` 于写口屏蔽，
"读 x0 恒为零"由寄存器堆本身保证，写回级不再作特判。

> <span class="figslot" data-src="2-5">图 2-5</span> **D-cache 与总线请求时序**：命中单拍、`MISS_CAPTURE` 一拍锁存、
> `FILL` 逐字写入，以及 store 与 MMIO 的绕过通路。


#### 2.2.7 CSR、异常与计数

`csr_file.v` 实现的 CSR 集合为：`mstatus`（0x300）、`misa`（0x301）、`mie`（0x304）、`mtvec`（0x305）、
`mscratch`（0x340）、`mepc`（0x341）、`mcause`（0x342）、`mtval`（0x343）、`mip`（0x344）、
`mvendorid`（0xF11）、`marchid`（0xF12）、`mimpid`（0xF13）、`mhartid`（0xF14），以及 64-bit
`mcycle` 与 `mcycleh`（0xB00／0xB80）。其中 `mvendorid`／`marchid`／`mimpid`／`mhartid` 返回常量 0。

- `mcycle` 为**唯一周期来源**：每个非复位时钟加一，RV32 经 `0xb00`（低）与 `0xb80`（高）访问，
  软件按 high→low→high 顺序读取并校验一致性后重读。本作品全部周期加速比均以 `mcycle` 差值计算，不以
  事件计数之和替代——后者（`cpi_cnt` 的 inst、stall、flush 事件）存在重叠，不可相加为周期数；
- **陷入流程**：`ecall` 于 EX 级写入 `mepc`（当前 PC）与 `mcause = 11`，跳转至 `mtvec`；`mret` 自
  `mepc` 恢复 PC；外部中断经 `ireq_external = gpio_irq | uart_irq | ascon_irq` 汇聚，抢占时由
  `stall_ctrl` 清除较年轻指令；
- **计数与 CPI**：`cpi_cnt.v` 挂接 `0x6000_0000` 窗口，提供 `probe_inst_valid`、`probe_stall_ld`、
  `probe_stall_md` 与 `probe_flush_br`（每事件计权 2）四组 64-bit 计数；CPI 以同一区间的
  cycle delta 与已退休指令 delta 计算，不采用事件加权和。


#### 2.2.8 分支预测

预测器为 64 项单表结构（`branch_predictor.v`，`INDEX_WIDTH = 6`）：

- **表项**：tag 表、BTB 目标表（分布式 RAM，`ram_style="distributed"`，整体 `dont_touch`）、2-bit
  饱和计数器 BHT 与打包 valid 向量；
- **索引**：`index = pc[7:2]`（指令 4 字节对齐，低 2 位恒为零），`tag = pc[31:8]`；
- **预测**：仅当 `valid && tag_match && bht >= 2'b10` 时判为 taken，目标取 BTB 中记录的历史目标；
- **更新**：分支进入 EX 级后训练（`update_en`、`pc_ex`、`actual_taken`、`actual_target`），并按
  2-bit 状态机更新 BHT（`00↔01↔10↔11`，初值为弱不跳）。误预测冲刷由 `ctrl.v` 统一处理，预测器
  不参与冲刷。

采用"小型表 + 分布式 RAM"而非大容量 BTB，系针对本平台的容量与时序折衷：在 100 MHz、LUT 资源受限的
7020 器件上，该结构的面积与时序代价均较低；就本 SoC 的主要负载（AEAD 分块循环与基准测试主循环）而
言，其命中率与单独性能贡献尚未量化，本文不以结构描述替代实测结论。


#### 2.2.9 总线与 SoC 外设

`bus_interconnect.v` 按地址高位将读写请求译码至各从设备；`cpu_axi_bridge.v` 与 `axi_full_master.v`
将内部事务转换为 AXI4 master（ID 1 bit、WSTRB = XLEN/8，支持单拍与 burst）。

<span class="tabcap">表 2-3</span> **SoC 地址窗口与外设**

| 窗口 | 基址 | 从设备 | 说明 |
|---|---|---|---|
| MEM | `0x1000_0000` | AXI BRAM Controller → Block RAM | 128 KiB，代码与数据统一空间，可 Cache |
| CLINT | `0x1200_0000` | `clint.v` | `msip`、`mtimecmp`、`mtime`，提供软件定时中断 |
| UART | `0x2000_0000` | `uart_ctrl.v` | 当前 PYNQ 内部链路 6.25 Mbaud；历史板外串口 115200；读 FIFO 有副作用 |
| GPIO | `0x2001_0000` | `gpio.v` | LED 控制、按键事件锁存（读清），两级同步与消抖 |
| ASCON | `0x3000_0000` | `rtl_p0/ascon_mmio.v` | AEAD 寄存器接口，由调用者写 key（§2.3.3.3） |
| CPI | `0x6000_0000` | `cpi_cnt.v` | 四组 64-bit 事件计数 |

MMIO 事务不进入 D-cache。当前发布工程显式选择 `rtl_p0/soc_top.v` 与
`rtl_p0/ascon_mmio.v`；不能直接用工作树中同名但不同版本的文件替代发布源集。


#### 2.2.10 流水线控制与冒险处理

`ctrl.v` 输出两个 5 位向量 `stall[4:0]` 与 `flush[4:0]`，位序为 `{IF, IF/ID, ID/EX, EX/MEM, MEM/WB}`，
优先级由高至低如下表。

<span class="tabcap">表 2-4</span> **流水线控制事件优先级**

| 顺序 | 事件 | `ctrl.v` 中的动作 |
|---|---|---|
| 1 | `inter_req`（外部中断）或 `jump_trap_en`（陷入，同一条件分支） | `flush[3:1]`；`jump_sel = 10`（中断／陷入向量） |
| 2 | `jump_trap_out`（`mret`） | `flush[3:1]`；`jump_sel = 11`（`mepc`） |
| 3 | `dcache_stall` | `stall[4:0]` 全冻结 |
| 4 | `dmem_axi_stall_req`（store 等待总线） | `stall[4:0]` 全冻结 |
| 5 | `ex_stall_req`（多周期单元与 ISE） | `stall[4:2]`；`flush[1]`（EX/MEM 插气泡） |
| 6 | `jump_en`（分支重定向） | `flush[3:2]`（IF/ID 与 ID/EX）；`jump_sel = 01` |
| 7 | `load_use_rs1`／`load_use_rs2` | `flush[2]`（ID/EX 插气泡）；`stall[4:3]`（IF 与 IF/ID） |
| 8 | `icache_stall`／`fence_i_stall` | `stall[4:3]`；`flush[2]` |

表中次序为 `ctrl.v` 内 if-else 链的实际判定顺序，据此，Cache 与总线停顿优先于分支重定向，中断与
陷入同属首个条件分支。

该层为加速指令正确执行的关键：ISE 的多拍执行属第 5 项，陷入与中断属第 1 项；两者叠加时以
"陷入优先、ISE 状态一并清零、不发布迟到结果"为语义（§2.3.3.4）。


#### 2.2.11 与加速及时序收敛相关的结构改造

<span class="tabcap">表 2-5</span> **与加速及时序收敛相关的结构改造**

| 序号 | 改造内容 | 位置 | 动机 |
|---|---|---|---|
| 1 | 器件与工程迁移：Kintex-7 → Zynq-7020，重建 3 个 IP 与 1 个 XDC，PLL 由 50 MHz 倍频至 100 MHz | `board/vivado_zynq7000_xc7z020_ascon/` | 早期工程的目标器件为 `xc7k325t`，与提交板卡不符 |
| 2 | D-cache 增加 `MISS_CAPTURE` 状态，miss 属性锁存一拍后再发总线 | `dcache.v` | 消除"miss 判定至总线请求"的长组合路径（11 个失败端点） |
| 3 | store 与 MMIO 绕过 `MISS_CAPTURE`，恢复单拍注册请求 | `dcache.v` | `MISS_CAPTURE` 对不可 Cache 访问仅增加延迟，据此回收周期代价 |
| 4 | 乘法器输入与输出寄存器化，并引入 `mul_ack`、`cancel` 握手 | `mult.v`、`ex_stage.v` | 乘法器组合深度对应 48 个失败端点、−0.105 ns |
| 5 | ISE 状态寄存器改为局部复位控件 | `ascon/ascon_ise.v` | 全局复位扇出对应 93 个失败端点、−0.128 ns |
| 6 | 新增 Ascon MMIO 窗口与 ISE 指令 | `ascon/`、`rtl_p0/soc_top.v` | 当前短消息加速的核心功能 |
| 7 | UART 起始位检测审计（`d0` 与 `d1/d2`） | `uart_rx.v` | 已记录同步链风险；未做错误概率实测，不以估计数值判定无影响 |

前五项与加速功能无直接关联，但决定该 SoC 能否在 100 MHz 收敛。第 4 章将说明：33 组策略扫掠将 WNS
自 −0.942 ns 提升至 −0.118 ns，而剩余 0.118 ns 须由上述结构改造回收。



### 2.3 硬件系统介绍

#### 2.3.1 硬件整体介绍

当前入口为 `board/vivado_zynq7000_xc7z020_pynq/build.tcl`，top=`pynq_wrapper`、
part=`xc7z020clg400-1`、Vivado 2025.2。PS7 GP0 连接两个 AXI-Lite 窗口，
FCLK0 配置为 100 MHz；`proc_sys_reset` 与控制窗口管理复位。
COE 作为 128 KiB BRAM 初值，由服务固件 ELF/BIN 生成；板上不做动态固件装载。

源集明确使用 `rtl_p0/soc_top.v` 和 `rtl_p0/ascon_mmio.v`，其余 CPU/Ascon 模块按构建脚本选择。
实际逐文件哈希、IP 版本与产物大小见 release/manifest.json。
不能用当前 main 的同名文件、旧工程缓存或不同 COE 替代该发布源集。
`rebuild_firmware.tcl` 用于已有独立工程的 BRAM 重建与后续实现，不等于干净构建入口。

历史 PL-only 基准使用 `top_pl_bram`、板外串口及 clk_wiz_0；它与当前 PS 时钟工程分开保存。
三套历史固件对应三份 bitstream，当前 PYNQ 则在同一 overlay 下按 mode 选择三方案。

> <span class="figslot" data-src="2-2">图 2-6</span> **历史 PL-only 工程结构**：top_pl_bram 的板外时钟与串口入口，
> 仅用于解释历史基准；当前 PS7/FCLK0/AXI-Lite 结构见 PS/PL 通路图。


#### 2.3.2 机械设计介绍

本作品为纯电子系统，不含机械结构与运动部件。板卡采用正点原子领航者 ZYNQ7020 开发板，
以底板 + 核心板的两段式结构装配；设计成果全部位于 PL 内部逻辑与 PS 端软件，
不需要额外的机械加工件、传感器支架或外部供电模块。板级连接的仅有 50 MHz 时钟源、
USB 串口（UART）、两个用户按键、两个用户 LED 与以太网口，其中串口与网口分别用于
固件日志输出与 PYNQ 远程访问。


#### 2.3.3 电路各模块介绍

本节介绍三种密码实现和当前 PS/PL 接口；处理器核见 2.2 节。
当前源集选择以发布 manifest 与 build.tcl 为准；同名源文件的其他变体不自动属于本次交付。
职责、接口、测量范围与验证边界分别说明，不以设计意图替代已取得的证据。

##### 2.3.3.1 算法标准与参数定义

Ascon 的安全核心为 320 bit 状态 $S=(s_0,s_1,s_2,s_3,s_4)$，每个分量 64 bit，认证加密通过"吸收与挤出
＋置换"实现。AEAD128 的参数如下表。

<span class="tabcap">表 2-6</span> **Ascon-AEAD128 参数**

| 参数 | 取值 | 本作品的处理 |
|---|---|---|
| key | 16 byte / 128 bit | $K_0$ 取低 64 bit，$K_1$ 取高 64 bit |
| nonce | 16 byte / 128 bit | $N_0$、$N_1$ 同理 |
| tag | 16 byte / 128 bit | 完整输出，不截断 |
| rate / capacity | 128 bit / 192 bit | 每块吸收 16 byte |
| 初始向量 | 整数 `0x0000_1000_808c_0001`，字节串 `01 00 8c 80 00 10 00 00` | 常量以位移式匹配 |
| 轮常量 | `f0 e1 d2 c3 b4 a5 96 87 78 69 5a 4b`（第 0 至 11 轮） | P12 取前 12 个，P8 取后 8 个 |
| 域分离 | $s_4 \mathrel{\oplus}= 2^{63}$（`0x8000_0000_0000_0000`） | 于 AD 与 PT 之间插入 |

**轮函数**。第 $i$ 轮先执行常量加与 S-box，再执行线性扩散：

$$
\begin{aligned}
s_2 &\mathrel{\oplus}= c_i \\
s_0 &\mathrel{\oplus}= s_4,\quad s_4 \mathrel{\oplus}= s_3,\quad s_2 \mathrel{\oplus}= s_1 \\
t_0 &= \overline{s_0}\, s_1,\;\; t_1 = \overline{s_1}\, s_2,\;\; t_2 = \overline{s_2}\, s_3,\;\; t_3 = \overline{s_3}\, s_4,\;\; t_4 = \overline{s_4}\, s_0 \\
s_0 &\mathrel{\oplus}= t_1,\quad s_1 \mathrel{\oplus}= t_2,\quad s_2 \mathrel{\oplus}= t_3,\quad s_3 \mathrel{\oplus}= t_4,\quad s_4 \mathrel{\oplus}= t_0 \\
s_1 &\mathrel{\oplus}= s_0,\quad s_0 \mathrel{\oplus}= s_4,\quad s_3 \mathrel{\oplus}= s_2,\quad s_2 = \overline{s_2}
\end{aligned}
$$

线性层（$\mathrm{rotr}$ 表示 64 bit 循环右移）：

$$
s_i \mathrel{\oplus}= \mathrm{rotr}(s_i,\,r_{i,1}) \mathrel{\oplus} \mathrm{rotr}(s_i,\,r_{i,2}),
\qquad (r_{i,1},r_{i,2}) \in \{(19,28),(61,39),(1,6),(10,17),(7,41)\}
$$

**AEAD 流程**（加密方向）：

1. 初始化：$S \gets (IV,K_0,K_1,N_0,N_1)$，$S \gets P^{12}(S)$，$s_3 \mathrel{\oplus}= K_0$，
   $s_4 \mathrel{\oplus}= K_1$；
2. 关联数据：按 16 byte 分块吸收并执行 $P^8$；非空整块之后仍须追加一个空 padding 块并再次执行
   $P^8$；
3. 域分离：$s_4 \mathrel{\oplus}= 2^{63}$；
4. 明文：按 16 byte 分块挤出 $C_i = P_i \oplus (s_0 \Vert s_1)$ 并执行 $P^8$；末块不足 16 byte 时先补
   `0x01` 再补 `0x00`，末块不再置换；
5. 终结：$s_2 \mathrel{\oplus}= K_0$，$s_3 \mathrel{\oplus}= K_1$，$S \gets P^{12}(S)$，
   $s_3 \mathrel{\oplus}= K_0$，$s_4 \mathrel{\oplus}= K_1$；
6. 标签：$T = \mathrm{LE64}(s_3) \mathbin{\Vert} \mathrm{LE64}(s_4)$；密文与明文等长。

三种方案遵循的实现要点如下。完整 1,089 组 KAT 为 host 验证范围；当前板级三模式仅验证容量内 289 组：

- padding 为"追加字节 `0x01` 后补 `0x00`"，在 64-bit 字中表示为 $1 \ll (8n)$，$n<8$；
- AD 为空时既不吸收亦不 padding，但仍执行域分离；
- 整块 AD 与整块 PT 之后均须再经一个空 padding 块，不得以"满块即结束"处理；
- 长度须显式给出，不得由"最高非零 bit"反推（否则 `00` 与 `a500` 将判定错误）。

> <span class="figslot" data-src="2-6">图 2-7</span> **Ascon 置换数据通路**：5 × 64-bit 状态、S-box 的五个与非项
> 组合、线性层的五组双旋转与轮常量注入；标注 P12/P8 轮数差异及 ISE 内 320-bit 状态寄存器位置。


##### 2.3.3.2 方案一：纯软件实现（SW）

软件实现为正确性基准，同时作为周期加速比的参照基准（分母）。生产代码位于 `ascon/ascon_c/aead/`，锁定且不可修改的
参考实现位于 `sim/ascon/reference/ascon_c/`（ascon-c 固定 commit `446347f2`）。

**API 契约**（C）：

- `crypto_aead_encrypt(c, clen, m, mlen, ad, adlen, nsec, npub, k)`：`clen` 含 16 byte tag；
- `crypto_aead_decrypt(m, mlen, nsec, c, clen, ad, adlen, npub, k)`：tag 拼接于密文末尾，成功返回 0，且 `*mlen = clen − 16`；
  认证失败返回 −1，`*mlen = 0`，并清除 `m[0, clen−16)` 范围内的候选明文；`clen < 16` 时返回 −1
  且不写 `m`。

"认证失败须清除候选明文"为项目验收要求，非 SUPERCOP 的强制项：原始 C 参考在 bad tag 时返回 −1，
但缓冲区仍保留明文，且 `mlen` 等于明文长度。本作品修复生产 C 实现的失败处理，并将"原始 C 的真实
FAIL 行为"作为保留证据，不予掩盖。

**历史 PL-only 构建**：以 xpack `riscv-none-elf-gcc 15.2.0`、`-O2` 交叉编译为裸机固件，链接至
`0x1000_0000`，经 UART 输出测试结果。周期加速比的分母即该固件在板上的 `mcycle` 增量。在 16 字节明文、
warm 条件（指令已在 I-cache）下，板上实测为 **20806 周期**。当前 PYNQ 服务固件的固定输入
加密中位周期为 **23342**，见 §3.3.4.1；不与历史工具链和测量边界混用。


##### 2.3.3.3 方案二：存储器映射加速器（MMIO／HW）

MMIO 实现将整个 AEAD 实现为挂接于 `0x3000_0000` 的从设备，CPU 仅承担参数搬运、状态轮询与结果读取。
当前接口取自发布源集 `board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v`，如下表。

<span class="tabcap">表 2-7</span> **MMIO 加速器寄存器**

| 偏移 | 名称 | 读写 | 位定义与语义 |
|---|---|---|---|
| `0x00` | CTRL | W | `[0]` START（自清脉冲，仅空闲态接受）；`[1]` ENCRYPT（1 加密，0 解密）；`[2]` ZEROIZE（仅空闲态接受，同一写中优先于 START） |
| `0x04` | STATUS | R | `[0]` BUSY；`[1]` DONE；`[2]` FAIL（解密 tag 校验失败） |
| `0x08` | ADLEN | W | AD 字节数 |
| `0x0C` | MLEN | W | 消息字节数 |
| `0x10–0x1C` | KEY | W | 四个小端序 32-bit key 字，由调用者写入 |
| `0x20–0x2C` | NONCE | W | $N_0$ 至 $N_3$ |
| `0x30–0x3C` | TAGIN | W | 解密时待校验的 tag |
| `0x40` | AD_WDATA | W | 推入一个 AD 字（内部指针自增） |
| `0x44` | MSG_WDATA | W | 推入一个消息字（加密为明文，解密为密文） |
| `0x48` | OUT_RDATA | R | 弹出一个输出字（加密为密文，解密为明文），指针自增 |
| `0x4C–0x58` | TAGOUT | R | 加密计算所得 tag |

以下四项行为构成"可用外设"而非"可计算模块"的判据，须写入契约：

1. **BUSY 期间全部写操作被忽略**，包括 ZEROIZE、START、key/nonce、长度与输入缓冲；
2. **输出读门禁**：`OUT_RDATA` 仅在 `DONE && !BUSY && !FAIL` 且未超出有效字数时返回数据并推进指针，
   其余情形返回零且不推进。认证失败不得发布明文由硬件保证，不依赖软件自觉；
3. **ZEROIZE**：清除 key、nonce、tagin、长度与状态，以及全部 AD、MSG、OUT 数组，并经子核心复位清除
   适配器缓冲、$s_0..s_4$、候选明文与 P8/P12 私有副本。DONE 本身不等于清理，取完结果后须显式清零；
4. **长度上限**：硬件实际支持 AD 与消息各 0 至 16 byte（参数名 `MAX_AD_BYTES=256` 仅为缓冲上限，
   不代表多块能力），超长请求显式返回 FAIL。该限制为 P0 的边界条件：板级 MMIO 周期加速比仅对
   ≤16 byte 成立，正文不将其泛化为"任意长度"。

延迟结构上，MMIO 端到端周期由参数搬运（key、nonce、AD 与消息的逐字写入）、轮询往返与密码核本体三
部分组成。历史 PL-only 16 B 调用为 **688 周期**，核本体观测 **103 周期**；
当前 PYNQ 固定输入加密为 **1439 周期**。核外开销的历史分解不直接套用到当前调用。


##### 2.3.3.4 方案三：定制指令扩展（ISE）

ISE 将置换并入 CPU：320 bit Ascon 状态作为执行级的专用寄存器堆，由 4 条定制指令访问。指令占用
RISC-V 预留的 custom-0 编码（`0b0001011`），**未新造主操作码值**，4 条指令以 funct3 区分。

<span class="tabcap">表 2-8</span> **定制指令编码与语义**

| funct3 | 助记符 | 操作数 | 周期 | 语义 |
|---|---|---|---|---|
| `000` | `ascon.w` | `rs1` 为数据，`rs2[3:0]` 为索引 | 1 | `state[32*idx +: 32] = rs1` |
| `001` | `ascon.rd` | `rs1[3:0]` 为索引，`rd` 为结果 | 1 | `rd = state[32*idx +: 32]` |
| `010` | `ascon.p12` | — | 多周期 | `state = P12(state)` |
| `011` | `ascon.p8` | — | 多周期 | `state = P8(state)` |

状态映射固定为 10 个 32-bit 字：`s0` 低与高、`s1` 低与高，直至 `s4`。非法索引（不在 0 至 9 范围）
读返回零、写被忽略；该行为属显式容错约定，不产生非法指令异常。保留 opcode 与 funct 编码的全局审计
仍在待办之列，正文不声称已覆盖全部指令空间。

实现细节与生命周期如下：

- `perm_start` 为电平信号（指令位于 EX 且未完成期间保持有效），内部状态机对其打一拍脉冲，完成后
  锁存结果；据此，流水线 hold 跨越完成不会导致重复执行；
- **取消**：陷入与中断经 `cancel` 丢弃在飞操作并清零 ISE 状态，且不发布迟到结果；普通分支冲刷仅
  清除较年轻指令，不影响已完成的置换；
- **局部复位寄存器化**：P12/P8 的 1280-bit 私有复位扇出原挂接于全局复位的组合锥（93 个失败端点、
  −0.128 ns），改为"取消当拍清架构 `state`，下一拍清私有 `s_reg/s_out`"，接受与 `p_start` 同拍
  释放局部复位，不增加正常执行的置换周期（§3.3.1）；
- **无上下文保存与恢复 ABI**：陷入取消后不可自中间轮续算，调用者须串行独占或整体重算。当前
  bare-metal 自测不启用抢占，真实中断、多任务与嵌套调用下的恢复尚未验证；
- **软件封装**：以 `asm volatile` 手写 intrinsic（不改动 GCC backend），逐字读写状态并调用 P8/P12；
  软件侧 AEAD 循环与 MMIO 版本共用同一调用顺序与测试向量，故两版密文与 tag 可逐字节比对。

历史 PL-only 16 B 加密为 **2570 周期**、相对同组软件 8.10×；当前 PYNQ 固定输入为
**3995 周期**、相对当前 SW 5.843×。ISE 的设计动机是用硬件置换替代软件轮函数；
不同固件的差值尚未完成分项归因，不把推测写成已测结论。

> <span class="figslot" data-src="2-7">图 2-8</span> **三种实现的调用路径对比**：SW（全部于 CPU 内完成）、
> HW（CPU 经寄存器搬运至加速器并轮询）、ISE（CPU 直接执行 custom-0，状态位于 EX 级）；标注三者
> 的数据搬运量与关键延迟分项（搬运、轮询、算法本体）。


##### 2.3.3.5 三种方案的可比性边界

<span class="tabcap">表 2-9</span> **三种方案的可比性边界**

| 维度 | SW | MMIO（HW） | ISE |
|---|---|---|---|
| 数据通路 | 全部于 CPU 内逐字运算 | CPU → MMIO 总线 → 专用核 | CPU EX 级内，状态寄存器 |
| 单次 AEAD 的 CPU 动作 | 纯计算 | 写 key/nonce/AD/msg/len → START → 轮询 STATUS → 读 OUT/TAG | 写状态 → P8/P12 → 读状态 |
| 当前 PYNQ 加密周期（KAT #529） | 23342 | 1439 | 3995 |
| 当前周期加速比（相对 SW） | 1.000× | 16.221× | 5.843× |
| 当前服务长度能力 | PT/AD 各 ≤16 B | PT/AD 各 ≤16 B | PT/AD 各 ≤16 B |
| 主要成本 | CPU 软件运算 | 寄存器与窗口逻辑、轮询开销 | 指令译码、状态搬运与 EX 级多周期 |
| 面积统计 | 三模式共同占用的整机资源；不拆分独立面积 | 同左 | 同左 |
| 时序风险 | 无 | MMIO 完成路径（§3.3.1 最差路径） | EX 级 hold 与状态复位扇出 |
| 当前使用方式 | 正确性与周期基线 | CPU 搬运参数并主动轮询，短消息加速 | 软件 AEAD 控制流与硬件置换紧耦合 |

上述结果不宜读作"性能强弱排序"，而应理解为两条技术路线的取舍：MMIO 的周期加速比更高，但其能力受 16 byte
寄存器窗口与轮询开销约束，且 CPU 在轮询期间不可用；ISE 的周期加速比相对较低，然其状态位于流水线内，无
MMIO 总线往返，但当前服务仍统一受 16 B 长度限制。三者置于同一 SoC、同一套向量与
同一块板上测量，方能为该取舍提供实测依据。

<span class="evid">证据 docs/ascon_key_management.md；docs/ascon_standard_baseline.md；board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v；src/rtl/ascon/ascon_ise.v；data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json</span>


##### 2.3.3.6 PS/PL 数据通道方案论证

任务书初稿拟定的方案为"AXI-Lite 控制寄存器 + 共享 BRAM"。查证冻结 RTL 后，该方案在不修改 `src/rtl`
的前提下不可成立，依据如下：

<span class="tabcap">表 2-10</span> **PS/PL 数据通道选择依据**

| 证据 | 位置 | 后果 |
|---|---|---|
| 外设访问全部在 `bus_interconnect` 内部译码（clint、uart、gpio、cpi、ascon），无通向 PL 边界的 MMIO 出口 | `src/rtl/bus_interconnect.v` | 若为 CPU 增加 PS 可见寄存器窗口，必须修改该文件 |
| 仅 `0x1000_0000` 至 `0x100F_FFFF` 被判为可 Cache | `src/rtl/dcache.v` | 共享 BRAM 必落于该窗口内，PS 写入后 CPU 可能读到旧 Cache 行 |
| 无 D-cache 失效或清洗指令（仅 `fence.i` 触发 I-cache 冲刷） | `src/rtl/cpu_core.v`、`dcache.v` | 固件无法在两次事务之间保证一致性，`volatile` 与 `fence` 不足以替代 |
| 历史 P0 时序余量为 WNS +0.087 ns | `docs/freeze_checkpoint_20261027.md` §4 | 改动公共路径需重新验证；采用独立 PYNQ 工程控制变更范围 |

据此，本作品采用"以既有 UART MMIO 作为 PS/PL 数据通道"的方案：在 PL 内新增 `pynq_mbox.v` 实现串口的
另一端，字节经 `uart_tx` 送入 SoC 的 `uart_rxd`，SoC 的 `uart_txd` 经 `uart_rx` 收入 RX FIFO 供 PS 读取。
该方案具备四项性质：

1. **独立发布源集**：历史 PL-only 证据保留，当前 BD 与桥接 RTL 单独构建并验证；
2. UART 属不可 Cache MMIO，当前无 PS/RV32 共享可缓存 buffer，缓存可见性记为 N/A，不泛化为所有架构均无一致性问题；
3. 同一份服务固件既可运行于 P0 纯 PL 版本（接真实 UART 引脚），亦可运行于 PYNQ 版本（PS 为对端），
   仅需维护一条代码路径；
4. 代价为延迟与带宽：链路为 6.25 Mbaud（`BAUD_CNT_MAX = 16`，100 MHz 分频），每字节约 1.6 µs。
   理论字节时间不等于 PS 调用墙钟。固定 KAT #529 的实测中位为 **4.262–5.216 ms**，
   包含 Python、MMIO 与 UART。固件 AEAD 周期不含串口，须与墙钟分列；不同固件边界仍会影响周期。


##### 2.3.3.7 结构与寄存器定义

```
Jupyter (Python)
  └─ AsconHost → MailboxBackend → PynqUartTransport（src/pynq/pynq_transport.py）
        │  pynq.MMIO × 2（GP0，各 4 KiB）
        ├─ CONTROL 0x4000_0000 ── pynq_ctl.v  ：SOC_RESET / BUTTON / STAT(LED, RST) / ID
        └─ MAILBOX 0x4000_1000 ── pynq_mbox.v ：TX FIFO（64）─uart_tx─┐
                                                                     │ PL 内部，不经引脚
                                        RX FIFO（256）─uart_rx──┐    │
                                                               ▼    ▼
                                            SoC uart_rxd / uart_txd（top 端口，P0 同源集）
                                              cpu_core + dcache + uart_ctrl（0x2000_0000）
                                                        └─ Ascon：SW／MMIO／ISE
```

**CONTROL 窗口**（`pynq_ctl.v`，AXI-Lite 32 bit，遵循 WSTRB[0]）：

<span class="tabcap">表 2-11</span> **CONTROL 窗口寄存器**

| 偏移 | 名称 | 读写 | 位定义 |
|---|---|---|---|
| `0x00` | CTRL | RW | `[0]` SOC_RESET（1 保持 RV32 复位，上电默认 1）；`[3:2]` BUTTON[1:0] 透传至 SoC GPIO |
| `0x04` | STAT | RO | `[0]` SOC_RST_N（送给 SoC 的复位，1 为运行）；`[3:2]` LED[1:0] 回读 |
| `0x08` | ID | RO | `0x514E_5950`（"PYNQ"，小端） |
| `0x0C` | VERSION | RO | `0x0000_0001` |

复位约定为：`CTRL[0]` 上电置 1（SoC 保持复位），PS 确认链路可用后写 0 释放；释放信号经三级同步器
进入 SoC 时钟域。

**MAILBOX 窗口**（`pynq_mbox.v`，TX 深度 64、RX 深度 256）：

<span class="tabcap">表 2-12</span> **MAILBOX 窗口寄存器**

| 偏移 | 名称 | 读写 | 含义 |
|---|---|---|---|
| `0x00` | TXDATA | W | `[7:0]` 压入一字节；FIFO 满时延迟写响应 |
| `0x04` | RXDATA | R | `[7:0]` 弹出一字节；空时读 0 且不弹出 |
| `0x08` | TXSTAT | R | `[15:0]` 深度；`[16]` 满；`[17]` 空 |
| `0x0C` | RXSTAT | R | `[15:0]` 深度；`[16]` 满；`[17]` 空；`[18]` 溢出（粘滞） |
| `0x10` | RXCLR | W | `[0]` 清溢出标志 |
| `0x14` | TXFLUSH | W | `[0]` 清空 TX FIFO |
| `0x18` | CNT | R | `[15:0]` PS 已压入字节数；`[31:16]` 已接收字节数（16-bit 回绕） |
| `0x1C` | ID | R | `0x4D42_4F58`。按 32-bit 小端读出字节序为 `58 4F 42 4D`（"XOBM"），按大端字节序方为 ASCII "MBOX"；与 CONTROL 窗口 `0x514E_5950`（小端读出 "PYNQ"）的编码方向相反，正文按 RTL 现状如实记录 |

`link_flush`（由 CONTROL 的 SOC_RESET 驱动）为高时清空两侧 FIFO 与计数，保证每次 SoC 复位后链路回到
确定状态。


##### 2.3.3.8 服务协议与服务固件

字节流格式由 `src/pynq/mailbox_protocol.py` 与服务固件共同实现，共四类帧：

<span class="tabcap">表 2-13</span> **服务帧类型**

| 帧 | 长度 | 方向 | 用途 |
|---|---|---|---|
| `Y01Q` | 48 B 头 + key16 + nonce16 + AD + data + tag | PS → PL | AEAD 请求 |
| `Y01R` | 48 B 头 + payload | PL → PS | AEAD 响应 |
| `Y01S` | 64 B | PL → PS | 开机与 epoch 应答：固件标识、能力上限、自检结果、boot `mcycle` |
| `Y01E` | 20 B | PS → PL | PS 下发会话 epoch |

请求头字段依次为：magic（`Y01Q`）、version、flags、epoch（u64）、request_id（u64）、operation
（1 加密 / 2 解密）、mode（1 SW / 2 HW / 3 ISE）、adlen、dlen、output_capacity、taglen；响应头为
magic（`Y01R`）、version、flags、epoch、request_id、status、operation、mode、size、cycles。状态码为
`OK`、`AUTH_FAILED`、`LENGTH`、`UNSUPPORTED`、`INTERNAL`；响应 flags 中 `SIMULATED` 位在真实硬件执行
时恒为 0，`CYCLES_VALID` 位指示周期字段是否有效。协议约束为：失败响应不得携带数据与周期；key 与 nonce
长度须为 16；解密请求须携带 16 字节 tag。

服务固件 `pynq-svc-v1`（`src/firmware/pynq_svc/`）具备以下设计特征：

- **单槽串行**：一次仅处理一个请求，响应发完后回到帧同步状态，故 PS 侧无需额外 ACK 线；
- **周期口径**：仅在 AEAD 调用边界读取 64-bit `mcycle`（`0xB00`/`0xB80`，hi-lo-hi 一致读取），
  **不含串口传输时间**；
- **能力上限**：message 与 AD 各 16 字节，超长请求立即拒绝并返回 `LENGTH`；
- **构建**：`src/firmware/pynq_svc/build.sh` 以 RV32IM_Zicsr/ilp32 交叉编译，产物中检出 24 条
  custom-0 指令，P12/P8 均存在，可作为"ISE 确实被调用"的静态证据；
- **异常处置**：半帧读取依赖主机超时后 reset；无本地接收超时；UART 无远端流控。

> <span class="figslot" data-src="2-9">图 2-9</span> **PS/PL 协同通路结构**：Jupyter → Python API → 两个 AXI-Lite
> 窗口 → PL 内 UART 桥 → RV32 服务固件 → SW/MMIO/ISE；标注时钟域（FCLK0 100 MHz）、FIFO 深度与
> 帧格式。


##### 2.3.3.9 Overlay 构建与时序签核

Overlay 由 `board/vivado_zynq7000_xc7z020_pynq/build.tcl` 自动创建：独立工程 `pynq_overlay.xpr`、
Block Design（PS7 GP0、FCLK0 = 100 MHz、`proc_sys_reset`）、综合与实现并导出同名 bit 与 hwh。发布产物
为 `release/pynq.bit`（4,045,688 B，与 P0 三份 4,045,687 B 的 bitstream 属不同源集）与
`release/pynq.hwh`（148,833 B），二者由同一 BD 导出；BRAM 单独
重新生成后，MIF 与最终 BIN 逐字节一致（128 KiB，含补零）。

> <span class="figslot" data-src="2-13">图 2-10</span> **Vivado Block Design：PYNQ overlay**：在 `pynq_overlay` 工程中
> 打开 Block Design，展示 PS7、AXI Interconnect、`proc_sys_reset` 与 PL 内 CONTROL / MAILBOX 窗口及 SoC 的连接。

时序与实现结果（100 MHz，2026-10-28）：

<span class="tabcap">表 2-14</span> **Overlay 时序与实现结果**

| 指标 | 数值 | 判据 |
|---|---|---|
| WNS / TNS | **+0.034 ns / 0** | setup 失败端点 0/62861 |
| WHS / THS | +0.020 ns / 0 | hold 失败端点 0/62861 |
| 未约束检查 | 内部未约束端点 0；`no_clock`、`no_input_delay`、`no_output_delay` 均为 0 | 本工程无外接 PL IO，故未套用 PL-only 的 UART/LED XDC |
| DRC | **0 Error / 0 Critical Warning** | 默认显示 53 项 Warning，含规则条数上限提示，不等于全部潜在 Warning 数 |
| 整机资源 | LUT 14269、FF 19691、BRAM 34.5 tile、DSP 4 | utilization.rpt；不沿用历史 PL-only 数字 |

> <span class="figslot" data-src="2-14">图 2-11</span> **Vivado 实现后时序摘要**：打开 `impl_1` 的 Report Timing Summary，
> 截取 Design Timing Summary 区域，应可见 WNS +0.034 ns、TNS 0、WHS +0.020 ns 与失败端点 0。

须注意：该 overlay 工程使用 `rtl_p0` 目录下的 `soc_top.v` 与 `ascon_mmio.v` 副本，其余 CPU 与 Ascon
模块按 manifest 记录选择。当前 KEY 由调用者写入，不能把工作树任意同名文件当作发布输入。
本轮不改 RTL、固件、bit/hwh 或 manifest，只对齐报告与已有证据。


##### 2.3.3.10 验证结果与板上实测

**仿真与主机侧验证**（`validation_20261028.md`，全部 exit 0）：

<span class="tabcap">表 2-15</span> **仿真与主机侧验证**

| 验证项 | 内容 | 结果 |
|---|---|---|
| `test_host_api.py` | 17 项，含历史 Notebook 顺序执行 | PASS |
| `test_mailbox.py` | 24 项协议编解码与错误分支 | PASS |
| `test_navigator.py` | 8 项 | PASS |
| `test_pynq_transport.py` | 14 项，含 real-service 标志回归 | PASS |
| `golden_checker.py` | 1,089 组官方 KAT、4,290 次拒绝（host 范围） | PASS |
| `run_bridge.py` | 真实桥 RTL：双向传输、空读、WSTRB、RX 满与溢出、顺序读回、复位中止发送 | PASS |
| `run_service.py` | 真实 CPU + 最终固件 + AXI-Lite/UART + 行为级 AXI 存储；三模式 36 请求（加密/解密/坏 tag），检查 `mcycle` 非零；半帧复位后重新握手 | PASS |
| 固件构建 | RV32IM_Zicsr/ilp32，24 条 custom-0，P12/P8 存在 | PASS |
| 镜像一致性 | Vivado BRAM MIF 与最终 BIN 逐字节比较（128 KiB 含补零） | PASS |

**板上结果**（正点原子领航者 ZYNQ7020，PYNQ 2.7.0，Python 3.8.2）：
overlay 加载成功，MMIO ID 检查通过；服务报告为 `firmware_id=pynq-svc-v1`、`simulated=false`、
`selftest_mask=7`、`max_message_bytes=16`、`max_ad_bytes=16`、`board_validation=PASS`。

板上在 16 字节容量内执行 message 与 AD 各 0 至 16 字节的全部 289 组组合，三模式均通过：

<span class="tabcap">表 2-16</span> **板上容量内 KAT 与周期统计**

| 模式 | 加密 KAT | 错误 Tag 拒绝 | 周期最小值 | 周期均值 | 周期中位数 | 周期最大值 |
|---|---:|---:|---:|---:|---:|---:|
| SW | 289/289 | 289/289 | 17584 | 23801.7 | 23543 | 33595 |
| HW | 289/289 | 289/289 | 1229 | 1589.0 | 1594 | 1797 |
| ISE | 289/289 | 289/289 | 3012 | 4122.0 | 4137 | 5209 |

据同一统计口径，均值之比为 **SW/HW ≈ 15.0×、SW/ISE ≈ 5.8×**，不是逐条加速比的均值。
该组数据不能与 §3.3.4.3 的历史 PL-only 独立基准
数值直接比较：后者为固定 16 字节、单一拍数的端到端测量（SW 20806、ISE 2570、MMIO 688），而本表为
服务固件覆盖 0 至 16 字节全长度组合的逐次统计，且调用内部包含适配、轮询与缓冲清理，不含请求帧传输。两组数值
差异的归因（尤以 HW 路径的平均 1589 周期与 P0 的 688 周期之差别）本轮<span class="blocked">尚未完成
</span>，故正文分列呈现，不作合并。

**证据身份**：板上测试使用发布版 bit、hwh 与固件，对应 Git `ac9143d5`，bit SHA-256
`6e7f9320…`，hwh SHA-256 `3ebd2640…`；证据归档于 `data/pynq/board_20261028/`（`pynq_board_full.json`、
`pynq_board_full.log`、`pynq_board_20261028.log`、`pynq_board_result.json`、`identity.txt`）。

**10-29 固定输入 benchmark 与 Notebook**：同 release、官方 KAT #529、PT=16 B、AD=0，
每模式预热 5 次后各 30 次加密/解密，全部 KAT 匹配。周期和墙钟见 §3.3.4.1–§3.3.4.2，
原始数组见 `data/pynq/notebook_20261029_130920/`。顺序执行结果存在；warm benchmark 已执行 ipynb 本体仍缺。

**10-29 V03 错误恢复**：9/9 checks、7/7 reset 恢复通过；epoch 1→8，
每次恢复后重新验证三模式 KAT。17 B PT/AD 返回 LENGTH；半帧、过期 deadline、重复 ID、错误 epoch、
RX FIFO overflow 均按门禁验证；每模式 50 次加密与 50 次解密匹配 KAT。
过期 deadline 用例验证主机截止时间与恢复机制，不证明硬件永久卡死也可自动恢复。
`data/pynq/error_gate_20261029_134023/` 含执行 Notebook、identity、JSON 与日志。

> <span class="figslot" data-src="2-10">图 2-12</span> **PYNQ 板测数据重排**：容量内 KAT、固定输入 warm benchmark 与错误恢复，
> 取自归档 JSON，不是原始终端截图或真实 Python 调用代码示例。


##### 2.3.3.11 未闭环项

<span class="tabcap">表 2-17</span> **PYNQ 通路未闭环项**

| 项 | 状态 | 说明 |
|---|---|---|
| 超出容量的 800 组板上用例 | NOT_RUN / 当前接口不支持 | 全量 host 已通过，不列为本次新增功能承诺 |
| warm benchmark 执行 Notebook 本体 | 待归档 | JSON/log 已存在，error-gate 本体已归档 |
| 小时级与资源泄漏 | not_measured | 每模式 50 次往返不等于小时级 RSS/FD 统计 |
| 协议错误与恢复 | 已有 9/9 实板证据 | 当前无共享 cacheable buffer，不伪造缓存测试 |
| 重复断电上电稳定性 | not_measured | 需冷启动与每次 smoke，软件 reset 不等于断电 |
| 独立 FCLK 测量 | not_measured | 配置 100 MHz 不等于独立测量 |
| 硬件轮询超时的错误语义 | <span class="todo">待完善</span> | 当前可能表现为内部失败或解密认证失败；异常时整链 reset 后重测，不作为认证性能数据 |

<span class="evid">证据 board/vivado_zynq7000_xc7z020_pynq/validation_20261028.md；board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md；data/pynq/board_20261028/pynq_board_full.json；data/pynq/notebook_20261029_130920/；data/pynq/error_gate_20261029_134023/</span>



#### 2.3.4 独立扩展原型：RO-PUF 与器件绑定通路

本章保留已实现的进阶探索，范围为独立 PL-only 扩展原型，不属于当前 PYNQ release。
其成果是 RO 采样、注册、重建判定、派生和内部接线的功能链，不宣称已经完成产品级硬件信任根或安全启动。

##### 2.3.4.1 架构与已实现代码

`src/rtl/keys/` 包含 device_dna、ro_unit、ro_puf_core、puf_key 和 key_mmio。
256 路 RO 经计数、两两比较及多次表决产生 128-bit 响应；注册保存参考响应与掩码，
重建将当前响应的掩码位与参考比较。Device DNA 提供 57-bit 器件标识，不是秘密熵源。

派生通路将固定上下文、响应及 DNA 组成 320-bit 状态，执行 P12 后取低 128 bit 作为 key。
这是项目自定义的置换派生原型，不是 NIST SP 800-232 对该 KDF 构造的认证或安全证明。
key 寄存器本身没有 CPU 读地址，内部连接至扩展版 ascon_mmio；当前 PYNQ 的调用者 key 路径与此不同。
采样窗口由构建参数决定，不使用旧稿的 3.3 ms 估算作为板级实测延迟。

> <span class="figslot" data-src="2-8">图 2-13</span> **独立扩展原型结构**：RO 阵列、计数与表决、参考和掩码、
> DNA 与 P12 派生、128-bit 内部 key；调试回读通路和未验收时钟边界均保留说明。


##### 2.3.4.2 实板观测与失败保留

证据为 `data/ascon/results/board/uart_20261027_keys3.txt` 及对应 XDat。
同一文件含两个版本片段，必须区分：

<span class="tabcap">表 2-18</span> **实板观测与失败保留**

| 片段 | 原始状态 | 可以支持的结论 |
|---|---|---|
| v2 抢跑片段 | busy 时启动，出现 quality=0，后续 127，最终 FAIL | 不能把该 127/128 当作正式通过结果 |
| v3 先等 idle | enroll=0x00008026，quality=128；MASK 全 1、DITHER 全 0、REF=RAW | 此次注册 128/128 位通过该采样判据 |
| v3 reconstruct | status=0x00008026；固件输出 PASS | 同次上电注册后，重建状态未报告 mismatch/fallback |

固件 `keys_rv32/main.c` 的 PASS 检查的是 ready、mismatch 与 fallback 状态，
并未在这份板级日志中直接比较两次秘密 key，也没有以派生 key 完成 AEAD Tag 验证。
因此“同次注册/重建自检通过”成立，“跨上电同密钥稳定”“认证启动通过”不成立。


##### 2.3.4.3 安全与实现边界

当前 key_mmio 可回读 REF、MASK、RAW 与 DNA，puf_key 的派生上下文和算法也可见。
因此仅有“key 寄存器不可直接读取”不足以证明软件无法重算派生值；本版应称为可观测的密钥生成实验原型，
不能称为已经实现密钥保密隔离。无 helper 或匹配失败时的 DNA-only 回退也不提供秘密密钥保证。

已有扩展源集的时序审查记录 no_clock=10944、未约束内部端点=27312，位于 RO 采样域。
正 WNS 只覆盖当时已约束路径，不代表该扩展全域时序签核；这些数值不能套到无该子系统的 PYNQ 发布版。
跨上电、温压、多器件唯一性及小时级稳定性未测，不是本次提交的阻塞条件，但报告不将其写成通过。

本原型作为已实施的探索展示；后续若开展可靠性或安全隔离改造，须独立立项、构建与验收，
不替换已验证的三模式 PYNQ 演示版本。

<span class="evid">证据 src/rtl/keys/puf_key.v；src/rtl/keys/key_mmio.v；src/firmware/keys_rv32/main.c；data/ascon/results/board/uart_20261027_keys3.txt；docs/io_timing_signoff.md 的 RO 采样域记录</span>




### 2.4 软件系统介绍

#### 2.4.1 软件整体介绍

软件分为 RV32 裸机固件、PS Python 调用层与开发机验证脚本。
历史 PL-only 使用 ascon_rv32、ascon_hw_rv32、ascon_ise_rv32；当前发布使用 pynq_svc，
在同一固件中按 mode 选择 SW/HW/ISE。固件由 COE 随 bitstream 初始化，不在运行时动态加载。

PS 侧由 AsconHost、MailboxBackend、PynqUartTransport 与 mailbox_protocol.py 完成请求、身份、
deadline 与 epoch 管理。超时需显式 reset/recover，不隐式重发；单客户端串行，未实现跨进程锁。
主机侧由 sim/ascon、sim/pynq、sim/board 的脚本分别执行标准验证、桥/服务仿真和回归。

> <span class="figslot" data-src="2-11">图 2-14</span> **软件分层与调用关系**：PS Python、RV32 服务固件与验证脚本，
> 标明 AXI-Lite/UART 帧协议与 MMIO/定制指令边界。

<span class="tabcap">表 2-19</span> **设计平台与工具链**

| 项 | 当前发布版本与历史边界 |
|---|---|
| 器件与板卡 | 工程 part=`xc7z020clg400-1`；正点原子领航者 ZYNQ7020；完整芯片丝印/速度等级仍待现场取证 |
| 当前时钟 | PS7 FCLK0 配置 100 MHz；独立频率测量 not_measured |
| 历史 PL-only 时钟 | 板载 50 MHz → clk_wiz_0 → 配置 100 MHz；不可替代当前 PS 时钟说明 |
| 存储 | 128 KiB BRAM，COE 初始化；当前固件 pynq-svc-v1 |
| EDA | Vivado 2025.2 SW6299465 / IP6300035；top=pynq_wrapper |
| 当前 IP | processing_system7 5.5、axi_interconnect 2.1、axi_bram_ctrl 4.1、blk_mem_gen 8.4、proc_sys_reset 5.0；以 manifest 为准 |
| 当前固件编译 | 归档构建使用 GCC 13.2.0，rv32im_zicsr / ilp32、-O2；以构建日志和 ELF/BIN 哈希为准 |
| 历史固件编译 | PL-only 基准使用 xpack GCC 15.2.0；不与当前发布版混用 |
| 仿真 | 归档 PYNQ 回归为 Icarus/vvp 12.0 devel、Python 3.14.3；模块另有 XSim 2025.2 证据 |
| 板端 | PYNQ 2.7.0、Python 3.8.2、Linux 5.4.0-xilinx-v2020.2 armv7l |

<span class="evid">证据 board/vivado_zynq7000_xc7z020_pynq/release/manifest.json；validation_20261028.md；validation_20261029.md；build/reports/pynq_final_20261028/</span>


#### 2.4.2 软件各模块介绍

##### 2.4.2.1 纯软件 AEAD 固件

纯软件路径调用生产 ascon/ascon_c/aead 的 crypto_aead_encrypt/decrypt，
按 Final 参数完成初始化、AD 吸收、域分离、消息处理与终结。tag 采用完整 16 B。
解密输入是密文与 tag 拼接，认证失败返回失败、输出长度归零并擦除候选明文。
锁定上游参考不改；生产失败处理与原参考失败分别保留证据。

当前服务对 PT/AD 统一限制为 16 B；host 完整 KAT 与板级容量内 KAT 分列。
固定 #529 的当前 warm 加密中位为 23342 cycles，历史 PL-only 20806 cycles 仅作独立对照。


##### 2.4.2.2 MMIO 加速器驱动固件

MMIO 驱动使用 0x30000000 寄存器窗口：写 KEY(+0x10–1C)、NONCE(+0x20–2C)、
ADLEN/MLEN，推入 AD_WDATA(+0x40)/MSG_WDATA(+0x44)，写 CTRL 启动，轮询 STATUS，
读取 OUT_RDATA(+0x48) 与 TAGOUT(+0x4C–58)，结束后显式清零。
消息与 AD 各 ≤16 B，BUSY 写忽略，认证成功且在有效长度内才允许输出。

当前 #529 加密中位 1439 cycles，解密 1388 cycles；两者包含驱动调用内搬运与轮询，不含 PS/UART。
HW 轮询异常当前可能表现为 INTERNAL 或认证失败，不能声称存在独立 TIMEOUT 状态码；异常后整链恢复。
历史 688 cycles 与核本体 103 cycles 不替代当前服务测量。


##### 2.4.2.3 定制指令固件

ISE 用 ascon.w/ascon.rd 访问 10 个 32-bit 状态字，以 ascon.p12/ascon.p8 执行置换。
主操作码 0x0B、funct7=0、funct3=0/1/2/3；inline assembly 使用 .insn，未修改 GCC backend。
构建归档检出 24 条 custom-0 静态编码；真实服务运行 KAT 提供动态正确性证据。

当前 #529 加密为 3995 cycles，相对 SW 为 5.843×；历史 PL-only 2570 cycles/8.10× 单列。
取消与 hold 的定向测试通过，不据此声称完整中断/抢占上下文保存恢复已验收。


##### 2.4.2.4 当前 benchmark 与采样工具

board_benchmark.py 对同一 release 完成身份检查、三模式 smoke 和固定输入采样。
官方 KAT #529、每模式预热 5 次，每操作 30 次，逐次核对 CT/tag/PT，并保存 raw_cycles/raw_wall_ns。
JSON 同时记录服务标志、发布哈希、测量范围和统计；错误结果不能混入成功性能统计。

周期来自 RV32 mcycle 的高低高一致读取。PS 端墙钟独立计量，不以事件计数器相加代替总周期，
也不将 CPU 周期加速比称为 PS 响应加速比。当前结果目录为 data/pynq/notebook_20261029_130920/。


##### 2.4.2.5 PS 端服务与帧协议

服务固件按 magic 识别 Y01E/Y01Q，校验 version、flags、epoch、request_id、mode、operation 与长度，
按 mode 调度三种实现，发送 Y01R；Y01S 发送固件身份、自检与 epoch 应答。当前帧没有 CRC 字段。
请求/响应头各 48 B，Y01S 为 64 B，Y01E 为 20 B；失败响应无 payload/cycles。

超时不自动重传，须主机 reset/recover、更新 epoch 并重新验证 KAT。
重复 ID 与错误 epoch 返回 INTERNAL；PT/AD >16 B 返回 LENGTH。
半帧与 FIFO overflow 后恢复已板测；服务端无本地半帧接收超时，单客户端无跨进程锁。
9/9 错误门禁与每模式 50 次往返有 JSON/log/已执行 Notebook 证据，非小时级验证。




### 2.5 大模型协作与技能包

#### 2.5.1 协作分工与智能体工作流

本作品按选题指南 3.3.3.1 使用大模型智能体辅助开发。分工原则是：**团队定目标、划边界、做裁决和实板验证，
智能体在边界内执行编码、构建、仿真与资料整理**。凡是影响结论的判断，例如是否降频、报告声明什么范围、
哪个版本可以上板，都由团队作出；智能体的输出只有经过脚本、仿真或实板复核后才进入成果。

<span class="tabcap">表 2-20</span> **协作分工与智能体工作流**

| 环节 | 团队负责 | 智能体负责 | 交接物 |
|---|---|---|---|
| 目标与范围 | 确定 100 MHz 不降频、PT/AD ≤16 B 的交付范围，删去证据不足的功能声明 | 按范围列出缺口与工作量 | 任务看板、决策记录 |
| 约束 | 维护仓库规则：不编造数据、未测写 not_measured、不自动提交、不改生成物 | 每次会话先读规则再动手 | `AGENTS.md`、`docs/technical_rules.md` |
| 方案 | 审阅端点归因、选择改造顺序与候选方案 | 给出多套方案及代价，执行被选方案 | 方案文档、构建脚本 |
| 执行 | 指定可改目录，安排多个智能体并行 | 父会话拆分子任务；子代理只改自己负责的目录 | 子代理会话、逐文件哈希 |
| 复核 | 交叉审阅另一模型的结论，上板运行，判定是否通过 | 跑回归、汇总报告、记录失败 | 回归 JSON、板测日志 |
| 沉淀 | 提出 Skill 要解决的问题与验证要求 | 整理成 Skill、测试与对照实验工具 | `skill/` 目录 |

智能体工作流采用"父会话规划、子代理分区执行、团队验收"。例如 10 月 29—30 日，团队要求"除上板外全部完成"后，
父会话把任务拆为 PUF 数字部分、CPU 侧集成、独立审查等子代理，每个子代理只拥有写定的目录，
并共享同一 Vivado 会话的使用约定；实板测试与是否采纳由团队决定。


#### 2.5.2 代表性协作记录与纠错轨迹

下列案例均摘自 `report/llm_collab/sessions/` 中的原始会话，提示词为原文，模型回答为节选。
每例给出团队提示、模型回答、纠错过程与最终裁决。

**案例一：拒绝降频，按端点归因完成 100 MHz 收敛（10-18）。**

<span class="tabcap">表 2-21</span> **案例一：拒绝降频，按端点归因完成 100 MHz 收敛（10-18）**

| 步骤 | 记录 |
|---|---|
| 团队提示 | "请你加载一下 AMD ROSS 的 skill……先看看当前数据中的时序问题，并给我一个修改方案" |
| 模型回答 | 策略扫掠后 WNS −0.177 ns；多次建议"降频到 98 MHz（强烈推荐）"，并给出"预期 WNS 0.523 ns"的样例输出 |
| 团队裁决 | "不能降频，我们想完成时序修正" |
| 纠错轨迹 | 两组实验 WNS 仍为 −0.177 ns，与基线完全相同。模型自查"是否真的应用了我们的修改"；团队判断"更改没有被识别到……不可能进行了更改带来的 WNS 是一样的"，叫停模型，改为手动打开工程复核 |
| 后续 | 团队在另一会话下达顺序：A（ISE 复位路径，预期清掉 93 个端点）→ C（乘法器 48 个端点）→ B（store/MMIO 绕行）→ 双策略复测 |
| 结果 | 两个策略在 100 MHz 下 WNS +0.001 / +0.007 ns，TNS 0；模型同时注明余量仅 1–7 ps，不能据此称上板通过（见 §3.3.1） |

**案例二：交叉审阅另一模型的结论，报告收缩到有证据的范围（10-29）。**

<span class="tabcap">表 2-22</span> **案例二：交叉审阅另一模型的结论，报告收缩到有证据的范围（10-29）**

| 步骤 | 记录 |
|---|---|
| 团队提示 | "这是另一个 ai 分析的，但是我感觉他的回复有可能是错的，请你给我分析一下现状距离我们想得到的还差什么" |
| 团队裁决 | "先将 PUF……、独立核 PPA 移除掉……先保证我们的技术报告可以和当前的版本和证据对上" |
| 纠错轨迹 | 按原始报告与 JSON 复算，纠正 23 类问题，如 MMIO/ISE 倍数写反、Vivado 版本写错、PUF key 位宽写成 320 bit、当前与历史周期混用；修订表见 `docs/tech_report/review_20261029.md` |
| 结果 | 当前 PYNQ 数据与历史 PL-only 数据分列；证据脚本与一致性检查纳入一键构建 |

**案例三：团队发现板测漏接 PUF，重新划定测试组合（10-30）。**

<span class="tabcap">表 2-23</span> **案例三：团队发现板测漏接 PUF，重新划定测试组合（10-30）**

| 步骤 | 记录 |
|---|---|
| 团队提示 | "今天我们发现之前做的测试中 PUF 并没有接入……你先给我说一下你的思路，我确认后，你进行操作" |
| 模型回答 | 核对构建脚本后确认"PYNQ 上做过的所有测试里，PUF 确实没有接入"，并给出合并方案 |
| 团队追问 | "这里的高速通道带来的优化有什么，如果……需要分开测试，为什么我们要加入这个高速通道呢" |
| 模型回答 | 分析指出高速通道绕开 RV32、与 PUF 无功能联系，合并只省一次下载却多一个未验证的 bit；建议不合并，给出 A/B/C 三案 |
| 团队裁决 | 选定方案 A：PUF 第一版接入 PYNQ 新 overlay，高速通道用已有候选单独测，其他扩展后续单独修 |
| 团队补充 | 指出另一版本的 setup.tcl 未把 PS 的 FIXED_IO/DDR 引出、日志中有 Netlist 29-160 严重警告，判定该 bit 不得上板，并要求给出最小闭环 PUF 方案 |
| 结果 | 当前报告只把 PUF 列为独立扩展原型（§2.3.4），不并入 PYNQ 主线成果 |

**案例四：版式迭代中的模型自我纠错（10-30）。**

团队逐页审阅 PDF，先后指出图被单独排成一页、公式与引导句分页、标题与图分离。模型第一次在每个标题前强制排出浮动图，
虽消除了分离，却留下约 1/4–1/3 页空白；团队反馈"图离得太远"后，模型撤销该做法，
改为按本页剩余版面决定原位、缩小或浮动，并用逐页填充率扫描确认除各部分末页外无大片空白。
同一轮中，构建因 PDF 被阅读器占用而失败，模型依据非零退出码停止发布，待团队关闭文件后重跑全流程。


#### 2.5.3 技能包的提炼与验证

技能包位于 `skill/`，每项都从开发中的具体失败或观察提炼，并写明适用范围、使用方法、失效条件与已验证程度。

<span class="tabcap">表 2-24</span> **技能包的提炼与验证**

| Skill | 来源（失败或观察） | 内容 | 已验证程度 |
|---|---|---|---|
| `rtl-design-discipline` | 队友观察到 AI 写 Verilog 的通病：同一逻辑多处等价重写、打补丁式修改、不关心综合出的硬件；取指单元中同一选择表达式被嵌套重写三次 | 先列寄存器清单、每个信号只在一处赋值、互斥条件用 case、改需求时重写整段选择逻辑等可判定规则 | 文本已成形；用与不用的对照实验未做（not_validated） |
| `pynq-overlay-workflow` | 本项目 PYNQ 实板中的真实问题：bit/hwh 不配套、ap_done 读清、无界等待、参考时钟假设、缓存一致性 | Overlay 加载与哈希校验、寄存器驱动与测试骨架、黄金参考比对、性能与报告采集工具；示例不含 Ascon 地址或长度 | 工具层 47 项单元测试通过、13/13 变异检出；智能体对照与实板未运行 |

验证方法由团队提出要求后设计。团队指出："加入 skill 和不加入 skill 在简单 RTL 生成时并无太大区别，
并且在同一 agent 情况下去测试无法控制变量。"据此，`skill/ab_eval_pynq/` 采用三组受控对照：
有 Skill、无 Skill、安慰剂 Skill（长度相同、同样会被加载，但只讲代码风格），每组使用新会话与独立工作目录，
由判分脚本而不是模型自评打分，并先用"好答案/差答案"自检判分器能区分优劣。
该实验尚未执行，报告不声称 Skill 已提升智能体效果。

边界的确定同样来自失败记录：Skill 不处理跨模块时序收敛（案例一说明这需要端点归因与 RTL 改造），
也不替代实板验证；遇到这类问题时，Skill 的说明会引导使用者转向 Vivado 报告与板级测试。


#### 2.5.4 原始记录的导出与范围

原始记录由 `report/llm_collab/export_sessions.py` 从本机 OpenCode、Claude Code 与 Codex 的会话库只读导出，
每个会话一份 Markdown，索引见 `report/llm_collab/index.md`。导出时只做四项处理：工具输出折叠为一行摘要、
超长回答保留首尾、疑似密钥打码，并省略 1 条与工程内容无关的用户提示原文（保留轮次与计数）；其余提示词与回答不改写。

截至 10 月 30 日的导出包含 21 个会话，其中 13 个为有工具调用的工程会话（76 条团队提示、约 2600 次工具调用），
其余为无工具调用的问答和模型/工具自检，一并保留。所用模型包括 Claude Opus 系列与 GPT 系列，
各会话的模型标识见索引。

记录存在三点范围限制：只含本机工具保存的会话；队友设备上的会话、网页对话及 10 月 9 日之前的工作未收录；
同一结论若经多个会话迭代，以最终的工程证据（回归 JSON、实现报告、板测日志）为准，而不以模型回答为准。
开发过程中的失败与返工另记录在 `project_log/lessons_learned.md`。



