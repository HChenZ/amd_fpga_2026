## 2 CPU 架构与模块设计

本章描述处理器本体，即本作品的计算基础。处理器为自研设计，其功能与结构在 §2.1 至 §2.9 逐级说明；
与密码加速通路、时序收敛直接相关的结构改造汇总于 §2.10，密码加速的接入点见 §3.4。逐信号级 I/O 表
列于附录 B，正文不予展开。

### 2.1 总体架构

处理器采用经典五级顺序流水线结构：取指（IF）、译码与读寄存器（ID）、执行（EX）、访存（MEM）、
写回（WB），并配置 I-cache、D-cache、分支预测器、旁路网络与集中式冒险控制。顶层 `cpu_core` 之下
的并列单元构成如下表。

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

> <span class="figslot">图 2-1</span> **处理器与 SoC 总体框图**：CPU 五级流水、I/D-cache、旁路与
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

### 2.2 取指单元（IF）

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

> <span class="figslot">图 2-3</span> **IF 级数据通路与冲刷语义**：PC 选择、I-cache 查询、
> 预测改选、miss FILL 与分支冲刷（flush[3:2] 两级）；为结构示意，不作为实测周期波形。

### 2.3 译码单元（ID）

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

### 2.4 执行单元（EX）

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
带状态的多周期指令，其读写对象为 ISE 内部的 10 个 32-bit 状态字（§3.4），而非通用寄存器。执行级以
hold 方式使流水线跨越 P12/P8 的多拍执行，`done` 保持至指令推进；"完成有效方予退休"的判据保证该指令
不会因跨过完成的停顿而被重复执行。

> <span class="figslot">图 2-4</span> **EX 级功能单元与多周期握手状态图**：含 `Idle → Busy → Done →
> ack 转换、陷入与中断取消分支，以及 ISE hold 与 ALU 单拍路径的复用关系。

### 2.5 访存与写回（MEM/WB）及 Cache 结构

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

> <span class="figslot">图 2-5</span> **D-cache 与总线请求时序**：命中单拍、`MISS_CAPTURE` 一拍锁存、
> `FILL` 逐字写入，以及 store 与 MMIO 的绕过通路。

### 2.6 CSR、异常与计数

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

### 2.7 分支预测

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

### 2.8 总线与 SoC 外设

`bus_interconnect.v` 按地址高位将读写请求译码至各从设备；`cpu_axi_bridge.v` 与 `axi_full_master.v`
将内部事务转换为 AXI4 master（ID 1 bit、WSTRB = XLEN/8，支持单拍与 burst）。

| 窗口 | 基址 | 从设备 | 说明 |
|---|---|---|---|
| MEM | `0x1000_0000` | AXI BRAM Controller → Block RAM | 128 KiB，代码与数据统一空间，可 Cache |
| CLINT | `0x1200_0000` | `clint.v` | `msip`、`mtimecmp`、`mtime`，提供软件定时中断 |
| UART | `0x2000_0000` | `uart_ctrl.v` | 当前 PYNQ 内部链路 6.25 Mbaud；历史板外串口 115200；读 FIFO 有副作用 |
| GPIO | `0x2001_0000` | `gpio.v` | LED 控制、按键事件锁存（读清），两级同步与消抖 |
| ASCON | `0x3000_0000` | `rtl_p0/ascon_mmio.v` | AEAD 寄存器接口，由调用者写 key（§3.3） |
| CPI | `0x6000_0000` | `cpi_cnt.v` | 四组 64-bit 事件计数 |

MMIO 事务不进入 D-cache。当前发布工程显式选择 `rtl_p0/soc_top.v` 与
`rtl_p0/ascon_mmio.v`；不能直接用工作树中同名但不同版本的文件替代发布源集。

### 2.9 流水线控制与冒险处理

`ctrl.v` 输出两个 5 位向量 `stall[4:0]` 与 `flush[4:0]`，位序为 `{IF, IF/ID, ID/EX, EX/MEM, MEM/WB}`，
优先级由高至低如下表。

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
"陷入优先、ISE 状态一并清零、不发布迟到结果"为语义（§3.4）。

### 2.10 与加速及时序收敛相关的结构改造

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
