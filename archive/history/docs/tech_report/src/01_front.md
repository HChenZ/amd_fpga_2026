# 集成 Ascon-AEAD128 轻量密码加速的 RISC-V 处理器 SoC

> 全国大学生嵌入式芯片与系统设计竞赛 2026 · FPGA 创新设计赛道 · AMD 自主选题初级组
> 决赛技术文档（证据对齐稿 v0.9，2026-10-29）
> 队伍编号 41555 ｜ 团队名称 芯尽自然亮 ｜ 目标器件 XC7Z020CLG400-1

## 审阅须知 {.unnumbered}

本稿以当前已取得证据的 RV32/PYNQ 短消息 SW、MMIO/HW、ISE 三模式为主交付范围，
另保留独立 RO-PUF/Device DNA 密钥通路原型作为扩展成果。
message 与 AD 各 0–16 B，key、nonce、tag 均为 16 B；不承诺超出当前接口的功能。
历史 PL-only 基准仅作独立对照，不与当前 PYNQ release 的性能、源集、资源或时序合并。
原始记录保留失败与未测状态；本次文字更新不代表重新执行硬件验证或已完成 clean-clone。

正文源为 `src/*.md` 与 `src_template/new/*.md`，由脚本重排为五部分，再生成 Markdown、HTML 与 LaTeX。
`证据` 指可追溯文件；`待补` 指材料缺口；`未验证` 不计为通过。图中日志摘录为数据重排，非原始界面截图。

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

## 作品概要 {.unnumbered}

### 项目要点一览

| 维度 | 当前交付版本 |
|---|---|
| 处理器 | 五级流水线 RV32IM + Zicsr；I-cache 1 KiB、D-cache 2 KiB；旁路、分支预测与集中控制 |
| 密码方案 | 标准 C 软件、CPU 驱动的 MMIO 加速器、EX 级 P8/P12 定制指令 |
| 指令接口 | custom-0 `0x0B`；funct3=0/1/2/3 对应状态写、状态读、P12、P8 |
| 当前硬件入口 | `board/vivado_zynq7000_xc7z020_pynq/`；`pynq_wrapper`；Vivado 2025.2 |
| 展示通路 | PS7 GP0 → CONTROL/MAILBOX → 字节 FIFO/UART → RV32 服务固件 |
| 功能容量 | PT/AD 各 ≤16 B；key/nonce/tag 各 16 B；超长请求返回 LENGTH |
| 固件装载 | COE 作为 BRAM 初值随 bitstream 构建；不含运行时固件加载器 |
| 测量纪律 | CPU mcycle 与 PS 墙钟分列；host、RTL、板级与实现报告分别标注 |

### 关键指标汇总

| 指标 | 当前结果 | 原始证据 |
|---|---|---|
| 板级 KAT / 错 Tag | SW/HW/ISE 各 289/289、289/289 | `data/pynq/board_20261028/pynq_board_full.json` |
| 加密中位周期（SW/HW/ISE） | 23342 / 1439 / 3995 | `data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json` |
| 解密中位周期（SW/HW/ISE） | 24005 / 1388 / 4385 | 同上，KAT #529，各 30 样本 |
| 周期加速比（HW/ISE） | 加密 16.221×/5.843×；解密 17.295×/5.474× | 同输入、同次运行、相对 SW |
| PS 调用中位墙钟 | 4.262–5.216 ms | 同一 JSON 的 raw_wall_ns，含 Python/MMIO/UART |
| 板级错误恢复 | 9/9 checks，7/7 reset 恢复 | `data/pynq/error_gate_20261029_134023/pynq_board_error_gate.json` |
| 当前实现时序 | WNS +0.034 ns、TNS 0、WHS +0.020 ns | `build/reports/pynq_final_20261028/timing.rpt` |
| DRC | 0 Error / 0 Critical Warning，普通 Warning 非零 | `build/reports/pynq_final_20261028/drc.rpt` |
| 标准一致性（host） | 1089 组官方 KAT；综合验证 28661 PASS/0 FAIL | `data/ascon/results/host_validation.json` |

### 主要创新点

1. 同一 RV32 平台比较软件、外设式加速和定制指令三条调用路径，测量边界一致且结果逐字节比对。
2. 使用 RISC-V 预留 custom-0 编码与 inline assembly 完成状态读写及置换，保留标准工具链。
3. 结合策略扫掠、失败端点归因及 RTL 结构改造完成时序收敛，并记录不同 run 的边界。
4. 用发布身份校验、官方向量、原始采样和错误恢复门禁形成可复核的板级演示链。

## 1 项目概述

### 1.1 设计目标与选题依据

本作品面向资源受限嵌入式设备的短消息认证加密，选择 NIST SP 800-232 Final Ascon-AEAD128，
在既有五级流水线 RISC-V CPU 上比较纯软件与两条硬件加速路径。算法公开参考实现与官方 KAT
提供独立正确性基准；可交互 PYNQ 演示提供调用、验证与性能展示入口。

本次交付聚焦标准正确性、同平台周期对照、可运行 overlay 与可追溯证据。
host 执行完整 1089 组 KAT；板端只声明容量内 289 组及负向验证，未验收项见 §9.1。

### 1.2 研制历程

| 阶段 | 时间 | 已发生结果 |
|---|---|---|
| 资产恢复 | 2026-09 | 从原始 ZIP 恢复真实 XC7Z020 baseline，与 Kintex legacy 分开保存 |
| 标准锁定 | 2026-10-07 | 固定 Final 规范、参考实现提交、许可、KAT 与 SHA-256 |
| 三方案集成 | 2026-10-09–16 | AEAD RTL、MMIO、ISE 接入，目标固件仿真与安全契约验证 |
| 时序收敛 | 2026-10-17–20 | 33 组策略及结构改造；双策略芯片内部时序通过 |
| 历史 PL-only 板测 | 2026-10-26–27 | SW/ISE/MMIO 三镜像代表 KAT 与 warm 周期记录 |
| PYNQ 发布 | 2026-10-28 | 独立 BD、bit/hwh/固件对应；三模式各 289 组容量内 KAT 与坏 Tag 拒绝 |
| PYNQ 验证收口 | 2026-10-29 | Notebook 顺序执行、30 次 warm benchmark、9/9 错误门禁与每模式 50 次往返 |

### 1.3 设计平台与工具链

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

### 1.4 设计准则与证据分级

接口先于实现；未测量项不填零、不计为通过。分别记录 hardware_measured、simulation、
implementation_report 与 not_measured。正 WNS 只说明该 run 在给定约束下通过，不等于最大频率或跨温压稳定性。
相同模块源文件不等于共享一个硬件实例；全 SoC 资源不充作某一加速通路的独立面积。

当前 release 的 bit/hwh/固件由 manifest 与逐文件哈希对应。板端 Git、release source commit
和历史仿真 source_head 分别记录，不能视为同一个身份。构建记录 source_dirty=true，
因此重建须结合 source_sha256、源集选择与构建输入，不能只 checkout 单个 commit 即宣称可复现。

### 1.5 术语与统计口径

| 术语 | 定义 |
|---|---|
| 三方案 | SW 为软件 AEAD；HW/MMIO 为 CPU 读写寄存器的 AEAD 外设；ISE 为状态读写与 P8/P12 定制指令 |
| 周期加速比 | 同次运行、相同输入与操作下 SW cycles / 目标 cycles；不是 PS 响应时间加速比 |
| 固件调用周期 | RV32 svc_aead_encrypt/decrypt 边界 mcycle 差值，不含 PS/UART |
| PS 调用墙钟 | PS 侧一次 mailbox 调用时间，含 Python、MMIO、串口及等待 |
| 历史 P0/PL-only | 三套独立基准固件对应的 bitstream，仅为历史对照 |
| 当前 PYNQ release | 一个 overlay 内按 mode 切换三方案；服务 pynq-svc-v1；PT/AD 各 ≤16 B |
| 配置频率 | 当前设置 100 MHz，不等于独立实测频率或 Fmax |
