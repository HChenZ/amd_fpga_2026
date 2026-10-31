## 摘要 {.unnumbered}

本作品在正点原子领航者 ZYNQ7020 开发板上实现集成 Ascon-AEAD128 的 RISC-V SoC。
PL 内为五级流水线 RV32IM + Zicsr 处理器，包含分支预测、I/D Cache、AXI 互连及 UART、GPIO、CLINT。
密码功能以 NIST SP 800-232 Final 为基准，提供纯软件、存储器映射加速器和定制指令三种方案。
四条定制指令使用 custom-0 编码空间，以 inline assembly 调用，不修改 GCC backend。

当前 PYNQ 发布版由 PS 经两个 AXI-Lite 窗口及 PL 内 UART mailbox 控制 RV32 服务固件。
明文和关联数据各不超过 16 B，三模式各通过 289 组官方容量内 KAT 及 289 次错误 Tag 拒绝。
Notebook 顺序执行、9 项错误恢复门禁与每模式 50 次加解密往返均已有实板记录。
固定官方 KAT #529（PT=16 B、AD=0），各预热 5 次后采样 30 次，加密 SW/HW/ISE 中位周期为
23342/1439/3995，HW 与 ISE 的周期加速比为 16.221×、5.843×；解密为 24005/1388/4385 周期。
周期来自固件 AEAD 调用边界，不含 PS 与串口；PS 调用墙钟中位 4.262–5.216 ms 单列，不充作同倍数响应加速。

Vivado 2025.2 对当前 `pynq_wrapper` 发布版在配置 100 MHz 下实现 WNS +0.034 ns、TNS 0、
setup/hold 失败端点 0、DRC 0 Error/0 Critical Warning，普通 Warning 如实保留。
另实现独立的 256 路 RO-PUF 与 Device DNA 密钥通路原型，同次上电的注册/重建自检通过，
最新有效日志注册质量为 128/128；不声称跨上电稳定、密钥保密隔离或完整安全启动。
host 完整 1089 组 KAT 与板级 289 组分列；独立频率、小时级稳定性与干净环境端到端复现尚未完成。

**关键词**：RISC-V；Ascon-AEAD128；定制指令扩展；MMIO；Zynq-7000；PYNQ；RO-PUF 原型


## 第一部分 作品概述

### 1.1 功能与特性

本作品在 Zynq-7020 上实现 RV32/PYNQ 短消息认证加密平台。PL 内为五级 RV32IM + Zicsr CPU，
提供标准 Ascon-AEAD128 软件、MMIO 与定制指令三种方案。当前 PT/AD 各 ≤16 B，key/nonce/tag 各 16 B。
PS 通过两个 AXI-Lite 窗口与 PL 内 UART mailbox 调用 RV32 服务固件，Jupyter 展示正确性、CPU 周期与 PS 墙钟。
三模式各 289 组官方容量内 KAT、坏 Tag 拒绝及 9 项错误恢复门禁已有实板记录；
完整 1089 组仅为 host 范围，不承诺超容量板级功能。

本作品面向资源受限嵌入式设备的短消息认证加密，选择 NIST SP 800-232 Final Ascon-AEAD128，
在既有五级流水线 RISC-V CPU 上比较纯软件与两条硬件加速路径。算法公开参考实现与官方 KAT
提供独立正确性基准；可交互 PYNQ 演示提供调用、验证与性能展示入口。

本次交付聚焦标准正确性、同平台周期对照、可运行 overlay 与可追溯证据。
host 执行完整 1089 组 KAT；板端只声明容量内 289 组及负向验证，未验收项见 §3.3.5。


### 1.2 应用领域

本作品面向资源受限嵌入式系统的短消息认证加密评估，例如传感器状态、控制消息或设备间小包数据。
当前实测只证明开发板上的有限长度功能与性能，不等于已部署产品的安全认证。

平台也可作为体系结构与 FPGA 实验载体：同一 RV32 上比较纯软件、CPU 驱动 MMIO 与定制指令，
用相同向量和测量边界观察周期差异。替换算法或平台需重新适配验证，不能直接沿用本作品性能值。


### 1.3 主要技术特点

三方案同平台、同输入对照；custom-0 的四条定制指令以 .insn 调用，不修改 GCC backend；
AEAD 密文和 Tag 与锁定 Final 参考逐字节比对；CPU mcycle 与 PS 墙钟分别保存。
构建采用 Vivado 2025.2，bit/hwh/固件逐项记录哈希；仿真、板测、实现报告与未测项分层标注。
当前 PYNQ 数据通道为 AXI-Lite 字节 FIFO 与 RV32 uncached UART，不使用共享可缓存数据缓冲。


### 1.4 主要性能指标

<span class="tabcap">表 1-1</span> **主要性能指标**

| 指标 | SW | HW/MMIO | ISE |
|---|---:|---:|---:|
| 加密 cycles | 23342 | 1439 | 3995 |
| 加密周期加速比 | 1.000× | 16.221× | 5.843× |
| 解密 cycles | 24005 | 1388 | 4385 |
| 解密周期加速比 | 1.000× | 17.295× | 5.474× |
| 加密 PS 墙钟 ms | 5.216 | 4.479 | 5.154 |
| 板级 KAT / 坏 Tag 拒绝 | 289/289 | 289/289 | 289/289 |

上表为当前 PYNQ release 官方 KAT #529（PT=16 B、AD=0）预热 5 次、采样 30 次的中位数，周期不含 PS/UART。
整机 LUT 14269、FF 19691、BRAM 34.5、DSP 4；100 MHz 下 WNS +0.034 ns、TNS 0、DRC 0 Error，频率未独立实测。


### 1.5 主要创新点

1. 同一 RV32 平台、同输入比较软件、MMIO 和定制指令，避免跨平台拼接加速比。
2. custom-0 状态读写与 P8/P12 置换，经 inline assembly 调用，不改编译器后端。
3. 策略扫掠与端点归因结合 RTL 结构改造，形成带 run 记录的时序收敛过程。
4. 发布哈希、官方 KAT、原始周期和墙钟、错误恢复门禁构成可复核演示链。


### 1.6 设计流程

设计流程以"先定口径、再做实现、最后留证"为主线，分六个阶段（图 1-1）：
确定指标及出处；按模块完成 RTL 并同步编写 testbench；
以参考实现和官方向量建立期望值，经单元仿真与 SoC 回归逐层收敛；
先策略扫掠、再按失败端点改结构；板上验证三方案并采集 KAT、周期与错误恢复；
核验哈希后于 11 月 1 日提交前冻结。细节见附录 D。

> <span class="figslot" data-src="1-1">图 1-1</span> **设计与验证流程**

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

处理器以 CICC1000023 作品中的自研 RV32 五级流水 CPU 为基础，本作品不重新设计 CPU，
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
> ack 转换、陷入与中断取消分支，以及 ISE hold 与 ALU 单拍路径的复用关系。


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
4. 明文：按 16 byte 分块挤出 $C_i = P_i \oplus (s_0 \| s_1)$ 并执行 $P^8$；末块不足 16 byte 时先补
   `0x01` 再补 `0x00`，末块不再置换；
5. 终结：$s_2 \mathrel{\oplus}= K_0$，$s_3 \mathrel{\oplus}= K_1$，$S \gets P^{12}(S)$，
   $s_3 \mathrel{\oplus}= K_0$，$s_4 \mathrel{\oplus}= K_1$；
6. 标签：$T = \mathrm{LE64}(s_3) \,\|\, \mathrm{LE64}(s_4)$；密文与明文等长。

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

## 第三部分 完成情况及性能参数

### 3.1 整体介绍

当前 PYNQ release 已在领航者 ZYNQ7020 上运行：PYNQ 2.7.0、Python 3.8.2，PS7 FCLK0 配置 100 MHz。
Python 通过 AXI-Lite/UART mailbox 调用 PL 内 RV32，同一 overlay 可切换 SW/HW/ISE，无需重载 bitstream。
板级容量内 KAT、Notebook、warm benchmark 与错误恢复均已留证；小时级稳定性与独立频率尚未测量。

> <span class="figslot" data-src="3-1">图 3-1</span> **系统实物正面照片**：docs/tech_report/figs/board_photo.jpg，
> 可见领航者 ATK-DF7010/7020P 丝印与上电指示。照片不证明拍摄时运行的 bitstream、芯片速度等级或长时稳定性；
> 背面、核心芯片完整丝印、跳线与 SD 镜像记录仍需补齐。

<span class="tabcap">表 3-1</span> **整体完成情况**

| 项目 | 已有证据 |
|---|---|
| 当前 KAT | 三模式各 289/289，坏 Tag 各 289/289 |
| 当前加密中位周期 | SW/HW/ISE=23342/1439/3995 |
| 错误恢复 | 9/9 checks、7/7 reset；每模式 50 次加解密往返 |
| 实现时序 | WNS +0.034 ns、TNS 0，DRC 0 Error/0 Critical |
| 当前 bit/hwh | 4045688 B / 148833 B，配套身份与哈希 |


### 3.2 工程成果

当前成果分为硬件/固件源、配套 release 与原始验证数据。
工程入口为 board/vivado_zynq7000_xc7z020_pynq/build.tcl；BRAM COE 由服务固件 build.sh 生成。
实际使用的 top、part、源集、IP 与源文件哈希见发布 manifest，不能以不存在的脚本或目录代替。

<span class="tabcap">表 3-2</span> **工程成果清单**

| 产物 | 实际位置 | 版本与范围 |
|---|---|---|
| 当前 overlay/固件 | board/vivado_zynq7000_xc7z020_pynq/release/ | bit/hwh/bin/coe/elf/manifest/sha256sums |
| 当前实现与回归 | build/reports/pynq_final_20261028/ | timing.rpt、utilization.rpt、drc.rpt、summary.json |
| 当前容量内 KAT | data/pynq/board_20261028/ | 官方 289 组 × 3 模式，含错误 Tag 拒绝 |
| 当前固定输入采样 | data/pynq/notebook_20261029_130920/ | 各档 30 样本与 PS 墙钟 |
| 当前错误恢复 | data/pynq/error_gate_20261029_134023/ | JSON、log、identity、已执行 ipynb |
| 历史 PL-only 镜像 | build/local/board_bitstream/ | 三镜像各 4045687 B；本地备份不是 clone 保证 |
| 历史 PL-only 日志 | data/ascon/results/board/ | uart_20261026_sw_and_ise.txt、uart_20261027_mmio.txt |

clean-clone 与最终证据包仍需独立验收；现有工件校验通过不等于源到板全流程已干净重建。

#### 3.2.1 资源占用

当前 `pynq_wrapper` 的完整资源原表为 `build/reports/pynq_final_20261028/utilization.rpt`，
数字由证据脚本抽取并列在附录 C，不用历史 PL-only 数字代替。

<span class="tabcap">表 3-3</span> **当前 PYNQ 实现时序与 DRC**

| 当前 PYNQ 指标 | 结果 | 原始报告 |
|---|---|---|
| WNS / TNS | +0.034 ns / 0 | timing.rpt |
| WHS / THS | +0.020 ns / 0 | timing.rpt |
| setup / hold 失败 | 均 0/62861 | timing.rpt |
| 内部未约束端点 | 0 | timing.rpt 的 check_timing 段 |
| DRC | 0 Error / 0 Critical Warning | drc.rpt |

整机资源为 LUT 14269、FF 19691、BRAM 34.5 tile、DSP 4。
DRC 默认报告有 53 项 Warning，其中包含规则条数上限提示；不能将该显示数当作所有潜在 Warning 的总数，
更不能写成“DRC 无任何警告”。DSP 流水、RAM 输出寄存器等提示保留在原始报告。

历史 PL-only 整机资源为 LUT 12426、FF 16156、BRAM 34.5 tile、DSP 4，WHS +0.021 ns。
原件位于 `build/local/proj_backup_first_time_20261027/first_time.runs/impl_1/`，不是当前工程报告。
这些是整机总资源，不据此推导每条加速路径的独立面积或功耗。

> <span class="figslot" data-src="3-6">图 3-2</span> **Vivado 实现后器件视图**：打开 Implemented Design 的 Device 窗口，
> 展示 PS7 与 PL 内 CPU、Cache、Ascon 等逻辑在 XC7Z020 上的布局。

> <span class="figslot" data-src="3-7">图 3-3</span> **Vivado 资源利用率报告**：Report Utilization 的汇总页，
> 应可见 LUT 14269、FF 19691、BRAM 34.5、DSP 4。


#### 3.2.2 可复现性与产物冻结

<span class="tabcap">表 3-4</span> **发布身份记录**

| 对象 | 当前记录 |
|---|---|
| release source commit | 86dc10f13e96adbb360f1adfe0c4891ce2f8e2a7；source_dirty=true |
| 板端 benchmark Git | ac9143d5c6acc9e7ac61f907a7e802eb6b35cddd |
| pynq.bit | 4045688 B；SHA-256 前缀 6e7f9320 |
| pynq.hwh | 148833 B；SHA-256 前缀 3ebd2640 |
| 固件 | pynq-svc-v1；ELF/BIN/COE 逐项哈希见 manifest |
| 身份核验 | 板端 release_hashes.log 与 identity.json；bit/hwh/固件必须配套 |

bit/hwh 来自同一 BD 实现；BRAM MIF 与最终 BIN 的 128 KiB 补零镜像有逐字节一致性证据。
manifest 的 source_sha256 是重建输入核对依据；source_dirty=true 表示只给 Git commit 不足以冻结全部输入。
manifest 中 hardware_validation=NOT_RUN 是构建时快照，后续板测应引用日期明确的外部证据，
本次不修改已发布 manifest 来追写状态。

从干净环境重建并运行的 D05 仍未完成；本文提供实际入口与现有记录，不承诺 clean clone 一键全部验收。
复建不要求 bitstream 字节必然相同，应分别核对源输入、功能、时序、资源和新产物身份。

<span class="evid">证据 board/vivado_zynq7000_xc7z020_pynq/release/manifest.json；board/vivado_zynq7000_xc7z020_pynq/validation_20261028.md；validation_20261029.md；build/reports/pynq_final_20261028/；docs/timing_acb_validation.md</span>



### 3.3 特性成果

本节按"时序 → IO → 功能 → 性能 → 完成度"五项列出已达成的量化成果。
前三项回答"这套设计能不能稳定工作"，后两项回答"它有多快、还有哪些没做"。
板上测量、仿真与实现报告分别标注；未测量项记为 `未测量` 或 `未验证`，不以估计值代替。

#### 3.3.1 时序收敛结果

本节为带原始记录的研制过程，不将历史余量称为当前 release 余量。
历史默认策略 WNS −0.942 ns，33 组策略中最优 Performance_ExploreWithRemap 为
−0.118 ns、TNS −1.008 ns、22 个失败端点。记录见
`data/ascon/results/strategy_sweep_20261017/strategy_sweep_summary.json`。
它说明已测策略的效果，不证明所有可能策略的理论上限。

对 fix_r1 快照的端点归因识别出 ISE 私有状态复位扇出、乘法器组合路径及 D-cache 请求通路三类问题。
对应结构改造为：局部复位注册化、乘法器输入输出注册与 ack/cancel 握手、MISS_CAPTURE 与
store/MMIO 绕过。归因分类不是互斥端点总数之和，不以分类数相加覆盖所有端点。

<span class="tabcap">表 3-5</span> **时序收敛历史记录**

| 历史 run | WNS ns | TNS ns | setup 失败端点 |
|---|---:|---:|---:|
| A+C+B / ExplorePostRoutePhysOpt | +0.001 | 0 | 0 |
| A+C+B / ExploreWithRemap | +0.007 | 0 | 0 |
| PL-only 三镜像报告 | +0.087 | 0 | 0/55572 |
| 当前 PYNQ release | +0.034 | 0 | 0/62861 |

前两项为历史策略快照，第三项为历史板测镜像实现，第四项为独立 PYNQ BD 实现；不能将相邻行之差
全归因于某一补丁。当前余量仅 34 ps，任何功能、约束或 IP 变化都须重新验证。

> <span class="figslot" data-src="3-2">图 3-4</span> **历史 PL-only 时序收敛记录**：默认策略、已测策略最优、
> 结构改造与历史板测镜像的 WNS；不替代当前 PYNQ 实现报告。


#### 3.3.2 时钟与 IO 的适用范围

当前 PYNQ 通路位于 PL 内部，通过 PS 的 AXI-Lite 窗口交互，没有沿用历史板外 UART、LED、按键 IO XDC。
当前报告内部未约束端点为 0，未列出 no_clock/no_input_delay/no_output_delay 问题。
这不等于测得了板外 IO 延迟，也不能把别的源集的 IO 覆盖检查作为本工程签核。

历史板外 UART 的约束分析仅作为工程资料保留，不列为当前 release 的新增成果。
FCLK0 配置为 100 MHz，但独立频率测量仍为 not_measured；本报告不据配置值声称实测 Fmax。
时序报告中的 WNS、TNS、WHS、THS 与路径覆盖须联合检查，不能只展示一个正 WNS。


#### 3.3.3 功能验证

##### 3.3.3.1 验证体系与层级划分

<span class="tabcap">表 3-6</span> **验证体系与层级划分**

| 层级 | 对象 | 手段 | 判据 | 状态 |
|---|---|---|---|---|
| L0 标准一致性 | C 与 Python 参考实现 | 独立下载的官方 KAT 逐字节比对 | 1,089 组加密、解密与负向用例全部通过 | 完成 |
| L1 模块级 RTL | 置换器、AEAD 适配器、Cache、ISE | Icarus/XSim 定向 TB 与 golden 状态比对 | 与锁定参考逐字节一致，事务契约成立 | 完成 |
| L2 系统级 | 整个 SoC 与真实固件 | `run_tests.py` 自动回归（smoke 与 regression） | 报告 JSON/Markdown，非零退出即判失败 | 完成（含 NOT_RUN 项） |
| L3 板级 | 三份镜像与真实芯片 | 串口 KAT 与 benchmark 采集 | SW 6 组、ISE 与 MMIO 各 4 组官方向量，含篡改拒绝与周期数 | 完成 |
| L4 PS/PL 协同 | 当前 release、服务固件与 host API | 容量内 KAT、Notebook、warm benchmark、错误恢复 | 三模式各 289/289、9/9 错误门禁；simulated=false | 有限范围通过（见 §2.3.3.6–2.3.3.11） |

> <span class="figslot" data-src="3-4">图 3-5</span> **五层验证体系与证据流**：host → RTL → SoC 仿真 →
> 历史 PL-only 板测 → 当前 PYNQ KAT、benchmark 与错误恢复，各层单列范围。


##### 3.3.3.2 L0：标准一致性与向量冻结

该层的作用是将标准固化为不可变的字节序列，作为 RTL 与板级验证的唯一参照。

- **标准版本**：NIST SP 800-232 Final（2025-08-13 发布），本地 PDF 哈希 `1be9bb9a…`。旧版 Ascon v1.2
  的 Ascon-128 与 Ascon-128a 在端序、IV 与 padding 上均不同，不可沿用其 KAT；
- **参考实现**：ascon-c 固定 commit `446347f2`（上游 `crypto_aead/asconaead128/ref/`）与 pyascon 固定
  commit `ed24e54a`。pyascon 的 README 仍标注 draft，故"是否对应 Final"不以文档表述判定，而以
  "通过完整官方 KAT"为判据；
- **官方向量**：`LWC_AEAD_KAT_128_128.txt`（同 commit），共 1,089 组，即 PT 与 AD 长度在 0 至 32 的
  笛卡尔积，哈希 `bbbc3469…`。key、nonce、PT、AD 与 expected CT 均取自原始文件，未使用本仓库生成器
  自证；
- **扩展向量**：`aead_cases.json` 共 64 组，其中 54 组取自上游矩阵，10 组为锁定 C 参考的扩展用例
  （含空串、`a5` 与 `a500`、尾零、33/64/129-byte PT 及最长 81-byte AD），每组附带首、尾 CT 与 tag
  翻转输入；
- **置换向量**：22 个输入状态 ×（12 个单轮、P8、P12），共 308 组，源自锁定 C helper，并经 Python
  二次校核；
- **冻结机制**：`freeze_vectors.py` 先令两个锁定参考通过完整独立下载的 KAT，再由锁定 C 参考产生扩展
  用例、由 Python 交叉检查；仅写入新建空目录，不覆写上游 KAT；两次重生成的三个数据文件字节完全一致。

实测结果如下表。

<span class="tabcap">表 3-7</span> **L0 标准一致性检查**

| 检查项 | 结果 | 证据 |
|---|---|---|
| 两个锁定参考的完整 KAT 门禁 | **12,936 PASS / 0 FAIL**，exit 0 | `reference_gate.json` |
| 四个 backend 全套（含完整性检查） | **28,661 PASS / 0 FAIL**，exit 0 | `host_validation.json` |
| harness 与 golden 接口 | 5 tests PASS，exit 0 | `harness.log` |
| 生产 C raw 失败解密契约 | 23965 PASS / 0 FAIL | `failure_contract.json` |
| 修复前行为复现 | 失败输出保留为负向证据，不代表当前生产结果 | `failure_contract_original_reproduction.json` |
| 冻结数据重生成 | 4 文件 byte-identical，exit 0 | `audit_snapshot.json` |

生产 C 实现已修复 bad tag 时的候选明文擦除与长度归零，锁定参考保持原字节。
修复前失败与当前通过分别保存，不能以早期失败覆盖当前结果，也不能因 KAT 通过推断 raw buffer 已擦除。


##### 3.3.3.3 L1：模块级 RTL 验证

<span class="tabcap">表 3-8</span> **L1 模块级 RTL 验证**

| 被测对象 | TB | 覆盖点 | 结果 |
|---|---|---|---|
| `ascon_permutation`（单轮、P8、P12） | `tb_ascon_permutation`（golden memory） | 22 状态 × 14 操作 = 308 组，逐字节比对 | PASS |
| `ascon_aead_core`、`ascon_aead_2` | `tb_ascon_aead_regression`、`tb_ascon_decrypt_regression` | 全源加密与解密、篡改、长度边界 | PASS |
| AEAD ISE（`ascon_ise`） | 定向 TB 与 EX 级集成 TB | 四指令编码、非法索引、取消、跨完成 hold | PASS |
| D-cache | 修订版 TB（`dcache_tb_revision.md`） | 命中、miss、填充、`MISS_CAPTURE` 单拍、store 绕过、两路替换 | PASS |
| CPU 中断与异常 | 6 个真实 CPU 与 CLINT 中断场景 | 抢占、`mret` 恢复、`mepc` 正确性 | PASS |

关键做法为：**golden 数据不由 RTL 自身产生**。置换与 AEAD 的期望值均取自锁定 C 参考（编译为 shared
library，由 Python 侧 ctypes 调用），RTL 仅提供"输入状态至输出状态"的映射，两侧在 Python 中比对。
独立参考降低同源自证风险，但通过仅覆盖实际执行的向量与断言，不证明所有可能错误必被检出。

> <span class="figslot" data-src="3-8">图 3-6</span> **Vivado 仿真波形：ISE 置换执行**：在 XSim 中打开 ISE 集成测试，
> 截取 custom-0 指令进入 EX、`ex_stall_req` 保持、置换完成后 `done` 与流水推进的一段波形。


##### 3.3.3.4 L2：系统级自动回归

入口为 `sim/board/run_tests.py`，共两档：

<span class="tabcap">表 3-9</span> **L2 系统级自动回归**

| 档位 | 内容 | 实测结果 | 耗时 |
|---|---|---|---|
| `--mode smoke` | 快速入口：编译、镜像一致性、基础功能 | **6 PASS / 0 FAIL / 0 BLOCKED / 9 NOT_RUN**，exit 0 | 18.739 s |
| `--mode regression --pynq-p0` | 指定 PYNQ P0 源集：三固件、host KAT、Mailbox、镜像、Cache 与定向中断 | **15 PASS / 0 FAIL / 0 BLOCKED / 1 NOT_RUN**，exit 0 | 400.168 s |

NOT_RUN 为显式结果，而非遗漏执行项：其对应"需真实板卡或需 PS7"的用例，在仿真环境中无法通过，故既不计
PASS 亦不计 FAIL。该三态设计的目的在于防止"不可执行的用例被标记为通过"。

本表只引用 2026-10-28 的归档 `smoke/summary.json` 与 `regression_final/summary.json`，
source_head=0f5d49c，含 dirty 状态，不称为 10-29 当前 HEAD 的重新回归。
产物含工具版本、命令、退出码与日志路径；历史
FAIL 与负向日志全部保留，不作删除。本档运行于 Windows 侧（Icarus/vvp 12 devel、GCC 13.2、
Python 3.14.3），与 host KAT 所用的 WSL 环境（Python 3.12.3、GCC 13.3.0，见 §3.3.3.2）分属两套工具链，
故文中出现的多个 Python 版本各有其归属。


##### 3.3.3.5 L3：纯 PL 镜像的板级验证

**KAT 与篡改拒绝**（三份镜像，同一板卡、同一串口、同日执行）：

<span class="tabcap">表 3-10</span> **L3 历史 PL-only 镜像 KAT 与篡改拒绝**

| 镜像 | KAT 覆盖 | 篡改拒绝 | 附项 |
|---|---|---|---|
| 软件 | empty、1 B、16 B、16 B+AD、17 B、32 B（6 组官方向量） | 通过 | — |
| ISE | empty、1 B、16 B、16 B+AD，另含解密往返 | 通过 | 解密往返一致性 |
| MMIO | 同 ISE 四组 | 通过 | **长度拒绝**（>16 B 显式拒绝） |

**benchmark**（16 字节加密、warm、`mcycle` 差值）：软件 20806 周期，ISE 2570 周期，MMIO 端到端
688 周期（核本体 103 周期）。同步采集的仿真值为 17353、2496、670 周期（核 99 周期），板级相对仿真
的开销分别为 **+19.9%、+3.0%、+2.7%**（核本体 +4.0%），开销与访存密度正相关。

板级与仿真使用不同存储环境，不能仅凭输出差值认定某一等待路径就是全部成因。
这些差异与存储模型、固件执行路径有关，但缺少分项实验，本文只保留观测，不声称已完成因果量化。

**原始证据**：串口日志按 XCOM 会话原始字节（`.XDat`）与去除非打印字符的可读版本（`.txt`）双份归档，
并记录 SHA-256。MMIO 版日志开头存在约 2 行乱码（打开串口瞬间的帧错），banner 之后数据完整，两份可
相互核对。覆盖组数以上表为准，不能把解密往返与篡改拒绝混记为额外官方向量。

> <span class="figslot" data-src="3-5">图 3-7</span> **历史 PL-only 串口日志摘录**：SW/ISE 日志的 KAT 与 benchmark，
> 为文本重排而非界面截屏；正面实物照片另见系统实物图，其他现场素材待补。


##### 3.3.3.6 缺陷发现与处置

本节记录验证过程中发现的问题及其处置，按"发现、定性、修复、复验"组织，其信息量高于"通过项"列举。

<span class="tabcap">表 3-11</span> **缺陷发现与处置**

| 序号 | 发现 | 定性 | 处理 | 状态 |
|---|---|---|---|---|
| 1 | 标准审计所得 7 项静态缺陷（R01–R07）：长度由最高非零 bit 反推、`p12/p8` 未接 `start`、tag 输出被覆盖、多块指针推进错误、AD=8 时 pad 走错分支、decrypt 为空壳、busy 时 `start` 覆盖状态 | 算法与 RTL 接口不达标 | 改用显式长度，引入请求、接收与完成握手，独立 tag 输出与 block 索引；重写 `decrypt` 并增加 tag 校验 | 已修 |
| 2 | 原生产 C 在 bad tag 后保留候选明文 | 失败 API 契约不满足项目要求 | 修生产 C 的擦除与长度归零；锁定参考不改，保留负向证据 | 23965 检查通过 |
| 3 | D-cache miss 至总线请求为长组合路径（11 端点） | 时序 | 新增 `MISS_CAPTURE`；store 与 MMIO 绕过 | 已修 |
| 4 | 乘法器组合深度（48 端点、−0.105 ns） | 时序 | 输入与输出寄存器化，引入 `mul_ack` 与 `cancel` | 已修 |
| 5 | ISE 私有状态复位扇出（93 端点、−0.128 ns） | 时序 | 局部复位寄存器化，取消当拍清架构态 | 已修 |
| 6 | 历史仿真与板级周期差达 +19.9% | 观测，分项归因未完成 | 各自保留原始值，不外推为通用误差规律 | 限定结论 |
| 7 | uart_rx 起始位检测涉及首级同步信号 | 同步链健壮性风险 | 没有独立错误率测量；不估计概率或声称风险不存在 | 未关闭 |
| 8 | 并行验证共享临时 .so，致 setup FAIL | 测试框架 | 每调用使用独立临时目录；同场景复验通过 | 已修 |

当前服务固件另已修复 UART RX 状态位读取、空输入 ISE padding 与服务帧标志问题，
桥 RTL 修复重复制入字节和复位恢复；真实 CPU 联合仿真与后续板测证据分别归档，不仅依赖 host 模型。


##### 3.3.3.7 未闭环项

<span class="tabcap">表 3-12</span> **验证未闭环项**

| 项 | 状态 | 影响 |
|---|---|---|
| 板上 ISA 抽样回归（含已知 `rv32ui_ma_data` 失败） | <span class="blocked">未执行</span> | 不得声称指令集已在板上全覆盖 |
| 完整 1,089 组 KAT 板级运行 | 289 组容量内通过；800 组超容量 NOT_RUN | 全量仅 host，当前服务不承诺超容量功能 |
| MMIO 长度能力 | 仅 ≤16 B | 不得泛化为任意长度 |
| 板级真实 IO 延迟 | <span class="blocked">not_measured</span> | 20 ns 为建模上界，见 §3.3.2 |
| PS/PL 与 PYNQ | Notebook、benchmark、9/9 错误门禁已执行；小时级、冷启动重复性未测 | 当前架构无共享可缓存 buffer；不应伪造缓存测试 |
| RV64 / 完整异常矩阵 | 未验收 | 定向中断通过不等于所有 ISE 抢占上下文均通过 |
| 芯片丝印速度等级现场核对 | <span class="blocked">未做</span> | 沿用 `-1` 约束，风险记录于 `docs/risks.md` |

<span class="evid">证据 docs/ascon_standard_baseline.md §3–§5、docs/ascon_key_management.md §自动验证入口、project_log/actual_progress.md 2026-10-25/10-26/10-27 条目、docs/freeze_checkpoint_20261027.md §3–§5</span>



#### 3.3.4 性能量化

##### 3.3.4.1 当前 PYNQ 固定输入 warm benchmark

输入为锁定官方 KAT #529，PT=16 B、AD=0；每模式预热 5 次，再各采集 30 次加密和 30 次解密。
全部结果与官方 CT、Tag、PT 比对，service simulated=false、selftest_mask=7。
周期测量范围为固件 svc_aead_encrypt/decrypt 调用边界，不含 PS 与 UART。

<span class="tabcap">表 3-13</span> **当前 PYNQ 固定输入周期与加速比**

| 模式 | 加密中位 cycles | 加密 cycles/B | 加密周期加速比 | 解密中位 cycles | 解密 cycles/B | 解密周期加速比 |
|---|---:|---:|---:|---:|---:|---:|
| SW | 23342 | 1458.875 | 1.000× | 24005 | 1500.312 | 1.000× |
| HW/MMIO | 1439 | 89.938 | 16.221× | 1388 | 86.750 | 17.295× |
| ISE | 3995 | 249.688 | 5.843× | 4385 | 274.062 | 5.474× |

六档 raw_cycles 各 30 个，且每档数值完全一致，故 min/median/P95/max 相同。
这是固定输入 warm 路径的重复采样结果，不是覆盖全部长度的平均性能，也不是小时级稳定性证据。
证据：`data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json`。


##### 3.3.4.2 PS 调用墙钟与 CPU 周期的区别

同一批采样的 PS 调用墙钟如下，由 raw_wall_ns 复算中位数：

<span class="tabcap">表 3-14</span> **PS 调用中位墙钟**

| 模式 | 加密中位 ms | 解密中位 ms |
|---|---:|---:|
| SW | 5.216 | 4.957 |
| HW/MMIO | 4.479 | 4.262 |
| ISE | 5.154 | 4.986 |

PS 墙钟包括 Python、MMIO 访问、UART 字节传输和轮询等待。CPU 周期下降并未等比例转化为
PS 响应时间下降；不得将 16.221× 或 5.843× 标成 Python API 的响应时间加速比。
两条测量边界分别保留，不以串口理论传输时间代替实测。


##### 3.3.4.3 历史 PL-only 基准的独立对照

历史三套基准固件在同一板卡、配置 100 MHz、16 B 加密 warm 条件下经串口输出 mcycle：

<span class="tabcap">表 3-15</span> **历史 PL-only 周期对照**

| 模式 | 历史板上 cycles | 对应 RTL 仿真 cycles | 历史周期加速比 |
|---|---:|---:|---:|
| SW | 20806 | 17353 | 1.00× |
| ISE | 2570 | 2496 | 8.10× |
| MMIO 调用 | 688 | 670 | 30.24× |
| MMIO 核本体观测 | 103 | 99 | 不与完整 AEAD 调用并列计算加速比 |

历史日志为 `data/ascon/results/board/uart_20261026_sw_and_ise.txt` 与 `uart_20261027_mmio.txt`。
688 与 103 的差额为 585 周期，占调用周期约 85.0%；这仅说明该历史测量中核外开销占比，
不直接套用到当前服务固件。板上与仿真差异的完整定量归因未完成，不外推为一般平台规律。
当前主表始终使用 §3.3.4.1 的 PYNQ 同次运行结果。


##### 3.3.4.4 资源与时序的统计范围

当前 PYNQ overlay 的资源、WNS、DRC 取自独立 pynq_wrapper 实现报告（§2.3.3.9）。
历史 PL-only 的 12426 LUT、16156 FF、34.5 BRAM tile、4 DSP 为整个 SoC 的实现资源，
包含 CPU、Cache、总线、存储与加速逻辑，不是单独密码运算逻辑的面积。
SW/ISE/HW 历史镜像共用同一硬件结构，固件 COE 不同，不能据此推导各方案的边际资源消耗。
复用同一个 Verilog 模块定义也不意味着不同实例在运行时共享一块电路。

本文只陈述已有整机实现结果及同平台周期对照，不提供未测的功耗、Fmax 或各加速通路独立面积。


##### 3.3.4.5 对比结论的适用边界

当前结论限于相同 RV32/PYNQ 平台、相同输入与操作、相同固件调用边界的三模式对照。
host 的完整标准验证、历史 PL-only 周期和当前 PYNQ 结果分别成立，不互相替代。
超出 16 B 的板级运行不属于当前服务能力，既不计为通过，也不列为本次交付必须完成的新功能。
不据整机资源或短消息延迟宣称优于其他器件、其他工具或其他论文实现。

<span class="evid">证据 data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json；board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md；data/ascon/results/board/uart_20261026_sw_and_ise.txt；data/ascon/results/board/uart_20261027_mmio.txt</span>



#### 3.3.5 完成度与判据矩阵

<span class="tabcap">表 3-16</span> **完成度与判据矩阵**

| 工作项 | 当前状态 | 证据与边界 |
|---|---|---|
| RV32 平台与三方案运行 | 已有实板证据 | 当前 pynq-svc-v1 在同一 overlay 下切换 SW/HW/ISE |
| Final 标准一致性（host） | 1089 组通过 | 完整 host 结果不等于完整板级结果 |
| 当前板级容量内 KAT | 三模式各 289/289 | PT/AD 各 0–16 B，错误 Tag 各 289/289 |
| 当前 warm benchmark | 已执行 | KAT #529、预热 5 次、每档 30 次，原始 cycles 与墙钟齐全 |
| Notebook 从头顺序执行 | 已有运行结果 | warm benchmark 已执行本体尚未归档；不能写成未执行 |
| 板级错误恢复 | 9/9 checks PASS | 7/7 reset 恢复，每次三模式 KAT 通过 |
| 连续请求 | 已验证有限次数 | 每模式 50 次加密与 50 次解密；非小时级验证 |
| 当前实现时序 / DRC | 已有报告 | WNS +0.034 ns、TNS 0、DRC 0 Error/0 Critical；Warning 非零 |
| 独立 RO-PUF/DNA 原型 | 已实现并有一次板级自检通过 | v3 quality=128/128，同次重建状态通过；非 PYNQ release，见扩展原型章节 |
| 完整 1089 组板测 | NOT_RUN | 800 组超接口容量；本稿不承诺全量板级支持 |
| 板上 ISA 抽样 | NOT_RUN | 历史仿真 49/50，ma_data 因非对齐访存失败；不称全套 ISA 通过 |
| RV64、完整异常与抢占矩阵 | 未验收 | 不作为当前 RV32 bare-metal 演示的已验证能力 |
| 小时级资源泄漏与冷启动重复性 | not_measured | 无 RSS/FD 长时曲线，不以有限次数请求替代 |
| 独立 FCLK 与完整实物取证 | 部分缺失 | 已有正面照片；芯片完整丝印、跳线与 SD 镜像等仍待归档 |
| 实际交付 Skill | rtl-design-discipline 与 pynq-overlay-workflow 已成形 | 后者工具层 47 项测试、13/13 变异检出通过；智能体对照与实板未运行，不称效果已验证（见 §2.5.3） |
| clean-clone / 最终包 | 未完成 | 已能使用 release 不等于已在干净环境端到端重建 |



### 3.4 复现说明

#### 3.4.1 环境与版本

以下步骤从空白环境开始，按"主机验证 → 仿真回归 → 构建比特流 → 上板"顺序执行。每一步都有可判定的通过标准，
失败时保留日志并停止，不跳到下一步。所有命令在仓库根目录执行。

<span class="tabcap">表 3-17</span> **环境与版本**

| 项 | 版本或要求 |
|---|---|
| 源码 | `git clone https://github.com/HChenZ/amd_fpga_2026.git`，记录 `git rev-parse HEAD` 与 `git status --short` |
| EDA | Vivado 2025.2（`build.tcl` 会检查版本，不符即退出） |
| 固件工具链 | RV32 GCC（归档构建为 13.2.0，`rv32im_zicsr` / `ilp32`） |
| 主机与仿真 | Python 3、Icarus Verilog；主机标准验证可在 WSL/Linux 运行 |
| 板卡 | 正点原子领航者 ZYNQ7020，PYNQ 2.7.0 镜像，网口与电脑同网段 |


#### 3.4.2 主机验证与仿真回归

```sh
# 1. 主机标准验证：完整 1089 组官方 KAT 与认证失败契约
python3 sim/ascon/run_validation.py
python3 sim/ascon/check_failure_contract.py

# 2. RTL 回归：独立向量 + 生产源集门禁
python3 sim/ascon/prepare_rtl_vectors.py
python sim/ascon/run_rtl_regression.py

# 3. SoC 回归：真实 CPU、三模式固件、mailbox 与 PYNQ 桥
python -B sim/board/run_tests.py --mode regression --pynq-p0
python sim/pynq/run_bridge.py
python sim/pynq/run_service.py
```

通过标准为各命令 exit 0，且生成的 JSON 汇总中无 FAIL。归档结果见 `build/reports/pynq_final_20261028/`。


#### 3.4.3 固件与比特流构建

```sh
# 1. 编译服务固件
#    产物：build/local/pynq_svc/pynq_svc.{elf,bin,coe}
bash src/firmware/pynq_svc/build.sh

# 2. 构建独立 PYNQ overlay
#    不打开、不修改历史冻结工程
vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq/build.tcl
```

固件反汇编中应能找到 custom-0 指令（P12、P8），证明 ISE 确实进入二进制。构建完成后核对时序报告
WNS ≥ 0、TNS = 0、DRC 无 Error。复建的 bitstream 不要求与发布版逐字节相同，
应分别核对源输入、功能、时序、资源与新产物哈希；直接复现已发布结果时使用 `release/` 中的配套文件。


#### 3.4.4 上板运行

写卡、串口跳线与启动模式按 `board/vivado_zynq7000_xc7z020_pynq/handoff_20261028.md` 第 C 节执行。
登录板卡后：

```sh
cd ~/jupyter_notebooks
git clone https://github.com/HChenZ/amd_fpga_2026.git
cd amd_fpga_2026
# bit/hwh/固件必须配套
sha256sum -c board/vivado_zynq7000_xc7z020_pynq/release/sha256sums.txt
# 三模式各 289 组 KAT 与坏 Tag 拒绝
python3 src/pynq/board_demo.py --full-kat --out pynq_board_full.json
# KAT #529，预热 5 次，采样 30 次
python3 src/pynq/board_benchmark.py --out pynq_warm_benchmark.json
# 9 项错误恢复，每模式 50 次往返
python3 src/pynq/board_error_gate.py --out pynq_board_error_gate.json
```

交互演示使用 `src/pynq/pynq_board_demo.ipynb`（修改首个单元的仓库路径后 Restart Kernel → Run All）；
CLI 与 Notebook 共享同一通道，不要同时运行。通过标准：boot 自检 mask=7、固件标识 pynq-svc-v1、
simulated=false，三模式 KAT 与坏 Tag 拒绝全部通过；周期结果应与 1.4 节主要性能指标同量级。


#### 3.4.5 复现边界

- 干净环境下从克隆到上板的完整端到端复现尚未由第三方执行；本节命令均为本项目实际使用过的入口。
- PT/AD 超过 16 B 的 800 组官方 KAT 超出当前接口容量，板上不执行；完整 1089 组只在主机验证。
- 当前时序余量 34 ps，换用其他 Vivado 版本、IP 版本或约束需重新签核。
- 板卡速度等级与独立频率未实测；独立 RO-PUF 原型不在 PYNQ 发布版中，其复现见 §2.3.4 所列工程。

## 第四部分 总结

### 4.1 可扩展之处

以下方向均未实施，属后续计划，不计入本轮成果。

1. 长消息支持：当前 PT/AD 各 ≤16 B，经 AXI-Lite 字节 FIFO 传输；可改为共享缓冲或流式搬运，
   并补齐完整 1089 组板级 KAT 与多块吞吐测量。
2. 器件绑定密钥：将独立 RO-PUF/Device DNA 原型并入当前 overlay，关闭派生输入回读通路，
   补充跨上电、温压与多器件统计后再评估密钥用途。
3. 指令与算法：在现有 custom-0 状态指令上扩展 SP 800-232 中的 Ascon-Hash256/XOF128，
   并以 intrinsic 封装降低软件调用开销。
4. 工程验证：补独立频率测量、小时级稳定性、完整 ISA/异常矩阵与干净环境复现。


### 4.2 心得体会

实现可运行与结论可复核是不同目标。标准 KAT、真实 CPU 仿真与实板测试各自覆盖不同问题，
不能用某一层通过替代另一层验收；相同文件名也不能证明工件属于同一构建。
因此，发布身份、逐文件哈希、source_dirty 和源集选择应与原始样本一并保存。

性能比较首先是测量边界的比较。当前固定 16 B 输入下 MMIO 与 ISE 均降低了固件调用周期，
但 PS 侧调用仍包含 Python 与通信开销，响应时间没有获得同倍数改善。
保留这一区别，比仅展示最大的周期加速比更有解释力。

验证框架同样需要负向用例。错误长度、过期 epoch、重复请求及 FIFO overflow 的拒绝与恢复，
为演示链的健壮性提供了有限但可复查的证据；它们不构成无限时稳定性、完整 ISA 合规或安全认证证明。
报告应保留已知失败与未测项，不以文字更新代替工程验证。



## 第五部分 参考文献

1. NIST, *Ascon-Based Lightweight Cryptography Standards for Constrained Devices*, SP 800-232, Aug. 2025. DOI: 10.6028/NIST.SP.800-232.
2. C. Dobraunig et al., “Ascon v1.2: Lightweight Authenticated Encryption and Hashing,” *Journal of Cryptographic Engineering*, 2021（背景，不作 Final 向量来源）.
3. Ascon C reference implementation, `ascon/ascon-c`, commit `446347f2`，`crypto_aead/asconaead128/ref/`，CC0-1.0.
4. M. Meichlseder, *pyascon*, commit `ed24e54a`（锁定第二参考，Final 一致性由 KAT 验证）.
5. RISC-V International, *The RISC-V Instruction Set Manual*, Volumes I and II.
6. AMD/Xilinx, *Zynq-7000 SoC Technical Reference Manual*, UG585.
7. AMD/Xilinx, *Vivado Design Suite User Guide: Implementation*, UG904.
8. AMD/Xilinx, *Vivado Design Suite User Guide: Using Constraints*, UG903.
9. AMD/Xilinx, *Vivado Design Suite User Guide: Design Analysis and Closure Techniques*, UG906.
10. 全国大学生嵌入式芯片与系统设计竞赛 2026 FPGA 创新设计赛道《选题指南（AMD 自主选题初级组）》（比赛名称以实际报名及可追溯原件为准）.


## 附录 A 术语与缩写 {.unnumbered}

<span class="tabcap">表 A-1</span> **术语与缩写**

| 缩写 | 全称与含义 |
|---|---|
| AEAD | Authenticated Encryption with Associated Data，认证加密 |
| AD | Associated Data，关联数据 |
| ISE | Instruction Set Extension，本文的状态读写与置换定制指令 |
| MMIO | Memory-Mapped I/O，存储器映射访问 |
| KAT | Known-Answer Test，已知答案测试 |
| WNS / TNS | Worst Negative Slack / Total Negative Slack |
| WHS / THS | Worst Hold Slack / Total Hold Slack |
| DRC | Design Rule Check |
| COE | BRAM 初值文件 |
| mcycle | RV32 的 64-bit 周期来源，CSR 0xB00/0xB80 |
| warm | 经过预热的执行状态，不等于首次调用或长期平均 |


## 附录 B 地址映射与指令编码 {.unnumbered}



#### SoC 地址映射

<span class="tabcap">表 B-1</span> **SoC 地址映射**

| 窗口 | 基址 | 从设备 |
|---|---|---|
| MEM | 0x10000000 | 128 KiB AXI BRAM，统一代码数据空间 |
| CLINT | 0x12000000 | 定时器与软件中断 |
| UART | 0x20000000 | 当前 mailbox 的 RV32 uncached MMIO 端 |
| GPIO | 0x20010000 | LED 与按键事件 |
| ASCON | 0x30000000 | 当前 rtl_p0/ascon_mmio 的 AEAD 寄存器 |
| CPI | 0x60000000 | 指令与停顿等事件，不能相加替代总周期 |


#### 定制指令编码

主操作码 custom-0=0x0B、funct7=0；funct3=0/1/2/3 分别为 ascon.w/ascon.rd/ascon.p12/ascon.p8。
状态共 10 个 32-bit 字，按 s0 低/高至 s4 低/高排列；非法索引读零、写忽略。
索引取自寄存器值而非寄存器编号；具体接口与取消边界见 §2.3.3.4，不声称完整非法编码空间已验收。


#### MMIO 加速器寄存器

当前寄存器为 CTRL(0x00)、STATUS(0x04)、ADLEN(0x08)、MLEN(0x0C)、KEY(0x10–1C)、
NONCE(0x20–2C)、TAGIN(0x30–3C)、AD_WDATA(0x40)、MSG_WDATA(0x44)、OUT_RDATA(0x48)、
TAGOUT(0x4C–58)。当前交付采用调用者写入的测试 key，具体规则见 §2.3.3.3。


#### PYNQ AXI-Lite 窗口

<span class="tabcap">表 B-2</span> **PYNQ AXI-Lite 窗口**

| 窗口 | PS 基址 | 功能 |
|---|---|---|
| CONTROL | 0x40000000（4 KiB） | 复位、按键控制、LED/复位状态、ID、VERSION |
| MAILBOX | 0x40001000（4 KiB） | 字节 TX/RX FIFO、状态、overflow、计数、ID |

地址由当前 HWH 校验；不是 RV32 本地 MMIO 地址。详细定义见 §2.3.3.7。



## 附录 C 证据索引 {.unnumbered}

证据按版本与验证层级分组。`evidence/build_evidence.py` 自动生成工件哈希、原始报告摘录与
当前板测复算结果；缺文件或哈希不一致应返回失败，不用旧摘要填补。

<span class="tabcap">表 C-1</span> **结论与主要证据对照**

| 结论 | 主要证据 |
|---|---|
| 当前 release 身份 | `board/vivado_zynq7000_xc7z020_pynq/release/manifest.json`、`sha256sums.txt` |
| 当前时序 / DRC / 资源 | `build/reports/pynq_final_20261028/` 的 timing.rpt、drc.rpt、utilization.rpt |
| 容量内 KAT | `data/pynq/board_20261028/pynq_board_full.json` |
| 当前 warm benchmark | `data/pynq/notebook_20261029_130920/` 的 identity、smoke、benchmark JSON/log |
| 错误恢复与执行 Notebook | `data/pynq/error_gate_20261029_134023/` |
| host 标准验证 | `data/ascon/results/host_validation.json`、`reference_gate.json` |
| 生产 C 认证失败契约 | `data/ascon/results/failure_contract.json` |
| 历史 PL-only 周期 | `data/ascon/results/board/uart_20261026_sw_and_ise.txt`、`uart_20261027_mmio.txt` |
| 历史 PL-only 实现 | `build/local/proj_backup_first_time_20261027/first_time.runs/impl_1/`，本地备份，不保证随 clone 可用 |
| 仿真回归 | `build/reports/pynq_final_20261028/smoke/summary.json`、`regression_final/summary.json` |
| 33 策略记录 | `data/ascon/results/strategy_sweep_20261017/strategy_sweep_summary.json` |
| 实物正面照片 | `docs/tech_report/figs/board_photo.jpg`；不据照片推断拍摄时运行镜像或芯片速度等级 |
| 独立 RO-PUF 原型 | `data/ascon/results/board/uart_20261027_keys3.txt`；`src/rtl/keys/`；`src/firmware/keys_rv32/main.c` |

本地备份与未跟踪报告不是远程仓库可访问性保证。提交前须提供实际材料快照及对应证据包，并验证链接与文件。


报告表格为原始 JSON 复算；下列文本报告保留所选原文行。发布哈希与板测引用一致不等于已完成干净环境重建。

### 当前发布身份

来源：`board/vivado_zynq7000_xc7z020_pynq/release/manifest.json`

```text
{
  "source_commit": "86dc10f13e96adbb360f1adfe0c4891ce2f8e2a7",
  "source_dirty": true,
  "part": "xc7z020clg400-1",
  "top": "pynq_wrapper",
  "vivado": "2025.2 SW6299465 IP6300035",
  "artifacts": {
    "pynq.bit": {
      "bytes": 4045688,
      "sha256": "6e7f93203519269e1509f4ece1ee76b93c25c8254fe0f8ae9c942314a197d30d"
    },
    "pynq.hwh": {
      "bytes": 148833,
      "sha256": "3ebd26408504ed6181a1eac1f31a79ab0e5449c0f0d4d8f76f53fa6332067581"
    },
    "pynq_svc.bin": {
      "bytes": 47592,
      "sha256": "723631655c30d92352e2b0c557bdb07a5776927c3f75baa57b4b330a85e33a4e"
    },
    "pynq_svc.coe": {
      "bytes": 327742,
      "sha256": "401cbfdc1dfeb40a02bbfa28a329553eb22f77dce22b6887ef3874f2b4dcb946"
    },
    "pynq_svc.elf": {
      "bytes": 53880,
      "sha256": "c8b7001d5fd70df46f35f2b18390ab577f6562ec1841d032e94369b529b93f5b"
    }
  }
}
```

### 当前实现原件

#### 时序原文

来源：`build/reports/pynq_final_20261028/timing.rpt`

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Wed Oct 28 15:06:19 2026
| Host         : xyq running 64-bit major release  (build 9200)
| Command      : report_timing_summary -file E:/amd_fpga_2026/build/local/pynq_final/vivado/timing.rpt
| Design       : pynq_wrapper
| Device       : 7z020-clg400
| Speed File   : -1  PRODUCTION 1.12 2019-11-22
1. checking no_clock (0)
2. checking constant_clock (0)
3. checking pulse_width_clock (0)
4. checking unconstrained_internal_endpoints (0)
5. checking no_input_delay (0)
6. checking no_output_delay (0)
7. checking multiple_clock (0)
8. checking generated_clocks (0)
1. checking no_clock (0)
------------------------
 There are 0 register/latch pins with no clock.
4. checking unconstrained_internal_endpoints (0)
------------------------------------------------
 There are 0 pins that are not constrained for maximum delay.
5. checking no_input_delay (0)
------------------------------
 There are 0 input ports with no input delay specified.
6. checking no_output_delay (0)
-------------------------------
 There are 0 ports with no output delay specified.
    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints
    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------
      0.034        0.000                      0                62861        0.020        0.000                      0                62861        3.750        0.000                       0                 20822
Clock             WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints
-----             -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------
clk_fpga_0          0.034        0.000                      0                51421        0.020        0.000                      0                51421        3.750        0.000                       0                 20822
From Clock    To Clock          WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints
----------    --------          -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------

Path Group         From Clock         To Clock               WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints
----------         ----------         --------               -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------
**async_default**  clk_fpga_0         clk_fpga_0               0.771        0.000                      0                11440        0.873        0.000                      0                11440
```

#### 整机资源原文

来源：`build/reports/pynq_final_20261028/utilization.rpt`

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Wed Oct 28 15:06:23 2026
| Host         : xyq running 64-bit major release  (build 9200)
| Command      : report_utilization -file E:/amd_fpga_2026/build/local/pynq_final/vivado/utilization.rpt
| Design       : pynq_wrapper
| Device       : xc7z020clg400-1
| Speed File   : -1
| Slice LUTs                 | 14269 |     0 |          0 |     53200 | 26.82 |
| Slice Registers            | 19691 |     0 |          0 |    106400 | 18.51 |
| Slice Registers                            | 19691 |     0 |          0 |    106400 | 18.51 |
| Block RAM Tile    | 34.5 |     0 |          0 |       140 | 24.64 |
| DSPs           |    4 |     0 |          0 |       220 |  1.82 |
```

#### DRC 汇总原文

来源：`build/reports/pynq_final_20261028/drc.rpt`

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Wed Oct 28 15:06:23 2026
| Host         : xyq running 64-bit major release  (build 9200)
| Command      : report_drc -file E:/amd_fpga_2026/build/local/pynq_final/vivado/drc.rpt
| Design       : pynq_wrapper
| Device       : xc7z020clg400-1
| Speed File   : -1
1. REPORT SUMMARY
2. REPORT DETAILS

1. REPORT SUMMARY
-----------------
            Netlist: netlist
          Floorplan: impl_1
| CHECK-3   | Warning  | Report rule limit reached  | 2      |
| DPOP-1    | Warning  | PREG Output pipelining     | 3      |
| DPOP-2    | Warning  | MREG Output pipelining     | 4      |
| RBOR-1    | Warning  | RAMB output registers      | 3      |
```

### 容量内 KAT 复算

来源：`data/pynq/board_20261028/pynq_board_full.json`

```text
sw: KAT=289/289 bad_tag=289/289; cycles min/mean/median/max=17584/23801.7/23543/33595
hw: KAT=289/289 bad_tag=289/289; cycles min/mean/median/max=1229/1589.0/1594/1797
ise: KAT=289/289 bad_tag=289/289; cycles min/mean/median/max=3012/4122.0/4137/5209
```

### 固定输入 warm 复算（KAT #529，PT16/AD0，5 次预热）

来源：`data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json`

```text
sw/encrypt: n=30 median_cycles=23342; median_wall_ms=5.215529
sw/decrypt: n=30 median_cycles=24005; median_wall_ms=4.956839
hw/encrypt: n=30 median_cycles=1439; median_wall_ms=4.478620
hw/decrypt: n=30 median_cycles=1388; median_wall_ms=4.262073
ise/encrypt: n=30 median_cycles=3995; median_wall_ms=5.154210
ise/decrypt: n=30 median_cycles=4385; median_wall_ms=4.985971
```

### 错误门禁记录

来源：`data/pynq/error_gate_20261029_134023/pynq_board_error_gate.json`

```text
initial_health: PASS
over_capacity_data_17B: PASS
over_capacity_ad_17B: PASS
half_frame_requires_reset: PASS
deadline_timeout_requires_recovery: PASS
duplicate_request_id_rejected: PASS
stale_epoch_rejected: PASS
rx_fifo_overflow_detected: PASS
repeated_requests: PASS
```

### 归档仿真回归

#### smoke

来源：`build/reports/pynq_final_20261028/smoke/summary.json`

```text
{
  "timestamp_utc": "2026-10-28T06:36:22.776263+00:00",
  "source_head": "0f5d49c38597947dace3f1c99220deca8ef48e14",
  "evidence_kind": "host_and_rtl_simulation",
  "counts": {
    "PASS": 6,
    "FAIL": 0,
    "BLOCKED": 0,
    "NOT_RUN": 9
  },
  "elapsed_s": 18.739,
  "status": "PASS"
}
```

#### regression_final

来源：`build/reports/pynq_final_20261028/regression_final/summary.json`

```text
{
  "timestamp_utc": "2026-10-28T06:47:35.854091+00:00",
  "source_head": "0f5d49c38597947dace3f1c99220deca8ef48e14",
  "evidence_kind": "host_and_rtl_simulation",
  "counts": {
    "PASS": 15,
    "FAIL": 0,
    "BLOCKED": 0,
    "NOT_RUN": 1
  },
  "elapsed_s": 400.168,
  "status": "PASS"
}
```

### host 标准验证与失败契约

#### host_validation

来源：`data/ascon/results/host_validation.json`

```text
{
  "passed": 28661,
  "failed": 0,
  "exit_code": 0
}
```

#### reference_gate

来源：`data/ascon/results/reference_gate.json`

```text
{
  "passed": 12936,
  "failed": 0,
  "exit_code": 0
}
```

#### failure_contract

来源：`data/ascon/results/failure_contract.json`

```text
{
  "passed": 23965,
  "failed": 0,
  "exit_code": 0
}
```

#### failure_contract_original_reproduction

来源：`data/ascon/results/failure_contract_original_reproduction.json`

```text
{
  "passed": 1,
  "failed": 1,
  "exit_code": 1
}
```

### 历史 PL-only 日志选行

#### SW 与 ISE 镜像（2026-10-26）

来源：`data/ascon/results/board/uart_20261026_sw_and_ise.txt`

```text
=== ASCON-AEAD128 software on RV32IM ===
KAT empty : PASS
KAT 1B : PASS
KAT 16B : PASS
KAT 16B+AD : PASS
KAT 17B : PASS
KAT 32B : PASS
tamper reject : PASS
KAT: 6/6 PASS
enc 16B : 20806 cycles, 4495 inst, CPI 462 (x100)
enc 32B : 25787 cycles, 5606 inst, CPI 459 (x100)
dec 16B : 21360 cycles, 4722 inst, CPI 452 (x100)
dec 32B : 26444 cycles, 5857 inst, CPI 451 (x100)
===DONE===
KAT empty  : PASS
KAT 1B     : PASS
KAT 16B    : PASS
KAT 16B+AD : PASS
dec round  : PASS
tamper     : PASS
ISE cycles   : 2570
===DONE===
```

#### MMIO 镜像（2026-10-27）

来源：`data/ascon/results/board/uart_20261027_mmio.txt`

```text
!hi
"
?
?
?
A
A?
?
-
KAT empty   : PASS
KAT 1B      : PASS
KAT 16B     : PASS
KAT 16B+AD  : PASS
dec roundtrip: PASS
tamper reject: PASS
len reject  : PASS
crypto latency : 103 cycles
full MMIO      : 688 cycles
===DONE===
```

### 历史 PL-only 时序原文

来源：`build/local/proj_backup_first_time_20261027/first_time.runs/impl_1/top_pl_bram_timing_summary_routed.rpt`

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Tue Oct 27 18:42:44 2026
| Host         : DESKTOP-5H4M0DR running 64-bit major release  (build 9200)
| Command      : report_timing_summary -max_paths 10 -routable_nets -report_unconstrained -file top_pl_bram_timing_summary_routed.rpt -pb top_pl_bram_timing_summary_routed.pb -rpx top_pl_bram_timing_summary_routed.rpx
| Design       : top_pl_bram
| Device       : 7z020-clg400
| Speed File   : -1  PRODUCTION 1.12 2019-11-22
    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints
    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------
      0.087        0.000                      0                55572        0.021        0.000                      0                55572        3.750        0.000                       0                 17227
Clock                     WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints
-----                     -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------
clk                                                                                                                                                                     7.000        0.000                       0                     1
From Clock    To Clock          WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints
----------    --------          -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------

Path Group          From Clock          To Clock                WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints
----------          ----------          --------                -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------
**async_default**   clk_out1_clk_wiz_0  clk_out1_clk_wiz_0        0.448        0.000                      0                11217        0.983        0.000                      0                11217
```

### 历史策略 sweep 记录

逐项记录为 JSON/CSV，篇幅较长不摘录；路径与哈希见证据清单 C-10。

### 实物正面照片

照片即图 3-1（`docs/tech_report/figs/board_photo.jpg`），不替代芯片完整丝印取证。

### 独立扩展原型状态摘录（保留失败段，非可靠性统计）

来源：`data/ascon/results/board/uart_20261027_keys3.txt`

```text
# 来源：XCOM 串口捕获（COM7 / 115200 8N1），原始字节见 xcom_raw_20261027_keys3.XDat
# 本文件含两段连续捕获：
#   第 1 段 = PUF 握手 v2 固件（固件未等 idle 抢跑，读数误判，结论作废，仅作问题记录）
#   第 2 段 = v3 固件（先等 idle 再发 START），板级全通过

[第 1 段：v2 固件 — 抢跑误判]
=== KEY SUBSYSTEM SELF-TEST ===
STATUS boot   : 00000001 busy=1 enrolled=0 done=0 quality=0
STATUS pre-enr: 00000001 busy=1 enrolled=0 done=0 quality=0
STATUS enrol: 00000023 quality=0
FAIL enroll not marked
FAIL quality=0
STATUS pre-rec: 00007f05 busy=1 enrolled=1 done=0 quality=127
STATUS recon: 00007f26
FAIL
[第 2 段：v3 固件 — 板级通过]
STATUS boot   : 00000001 busy=1 enrolled=0 done=0 quality=0
STATUS idle   : 0000003a busy=0 enrolled=0 done=1 quality=0
STATUS enrol: 00008026 quality=128
STATUS recon: 00008026
PASS key subsystem: enroll + reconstruct stable
```



## 附录 D 研制历程、证据分级与统计口径 {.unnumbered}

#### 研制历程

<span class="tabcap">表 D-1</span> **研制历程**

| 阶段 | 时间 | 已发生结果 |
|---|---|---|
| 资产恢复 | 2026-09 | 从原始 ZIP 恢复真实 XC7Z020 baseline，与 Kintex legacy 分开保存 |
| 标准锁定 | 2026-10-07 | 固定 Final 规范、参考实现提交、许可、KAT 与 SHA-256 |
| 三方案集成 | 2026-10-09–16 | AEAD RTL、MMIO、ISE 接入，目标固件仿真与安全契约验证 |
| 时序收敛 | 2026-10-17–20 | 33 组策略及结构改造；双策略芯片内部时序通过 |
| 历史 PL-only 板测 | 2026-10-26–27 | SW/ISE/MMIO 三镜像代表 KAT 与 warm 周期记录 |
| PYNQ 发布 | 2026-10-28 | 独立 BD、bit/hwh/固件对应；三模式各 289 组容量内 KAT 与坏 Tag 拒绝 |
| PYNQ 验证收口 | 2026-10-29 | Notebook 顺序执行、30 次 warm benchmark、9/9 错误门禁与每模式 50 次往返 |


#### 设计准则与证据分级

接口先于实现；未测量项不填零、不计为通过。分别记录 hardware_measured、simulation、
implementation_report 与 not_measured。正 WNS 只说明该 run 在给定约束下通过，不等于最大频率或跨温压稳定性。
相同模块源文件不等于共享一个硬件实例；全 SoC 资源不充作某一加速通路的独立面积。

当前 release 的 bit/hwh/固件由 manifest 与逐文件哈希对应。板端 Git、release source commit
和历史仿真 source_head 分别记录，不能视为同一个身份。构建记录 source_dirty=true，
因此重建须结合 source_sha256、源集选择与构建输入，不能只 checkout 单个 commit 即宣称可复现。


#### 术语与统计口径

<span class="tabcap">表 D-2</span> **术语与统计口径**

| 术语 | 定义 |
|---|---|
| 三方案 | SW 为软件 AEAD；HW/MMIO 为 CPU 读写寄存器的 AEAD 外设；ISE 为状态读写与 P8/P12 定制指令 |
| 周期加速比 | 同次运行、相同输入与操作下 SW cycles / 目标 cycles；不是 PS 响应时间加速比 |
| 固件调用周期 | RV32 svc_aead_encrypt/decrypt 边界 mcycle 差值，不含 PS/UART |
| PS 调用墙钟 | PS 侧一次 mailbox 调用时间，含 Python、MMIO、串口及等待 |
| 历史 P0/PL-only | 三套独立基准固件对应的 bitstream，仅为历史对照 |
| 当前 PYNQ release | 一个 overlay 内按 mode 切换三方案；服务 pynq-svc-v1；PT/AD 各 ≤16 B |
| 配置频率 | 当前设置 100 MHz，不等于独立实测频率或 Fmax |
