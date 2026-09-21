# 仓库现状审计

> **2026-09-21 原始归档恢复更正：** 本文后续章节是第一阶段、初始 Git HEAD `e35d42f` 的审计快照（含当时检查结果），不是恢复后工作区的现状。原先“缺少 IP 定义、固件与 XC7Z020 工程”应解读为 **not_in_current_repo（该 HEAD 未包含）**，不能解读为 **not_available**。用户补充的 CICC1000023 ZIP 中已找到真实 XC7Z020 XPR、三个 XCI、XDC/COE、固件/测试和历史 bitstream/report；现已选择恢复，尚未提交。FreeRTOS kernel 的准确源版本及 bootloader 源仅能记为 not_available_in_supplied_archive。完整更正与证据见 [恢复审计](cicc1000023_recovery_audit.md)、[RTL 比较](cicc1000023_rtl_diff.md)、[工程比较](vivado_project_diff.md)。本轮目标是复现原始真实 baseline，绝不从零造空工程。

日期：2026-09-21（Asia/Shanghai）。范围：`E:/amd_fpga_2026` 全部工作区文件（排除 Git 内部对象）；同时枚举全部跟踪文件、读取字节并计算 SHA-256，检索 RTL/软件/工程引用。审计属于静态工程检查，不是逐行功能或安全审查。

## 1. 审计基点与结果

| 项 | 观察 |
|---|---|
| 仓库 | https://github.com/HChenZ/amd_fpga_2026 |
| 初始分支 / HEAD | main / `e35d42f9638e9f56e7af6df492f424173922fac1` |
| 初始工作区 | 干净；62 个跟踪文件，总计 377199 bytes；没有额外非 Git 文件 |
| 入口文档 | 原 README.md 为 0 bytes，无 AGENTS.md、.gitignore |
| 本轮分支 | docs/repository-foundation；无 commit/push，main 指针不变 |
| 原工程保护 | 只修改原 README.md；其余原有 61 个文件必须保持逐字节一致，末尾列哈希依据 |

**第一阶段结论（仅针对原始 Git HEAD）：CPU 基础源码存在，但不能从该 clone 直接复现目标板。** 该 HEAD 的 XPR part 是 `xc7k325tlffv676-2L`；未找到 `xc7z020clg400-1` 配置。该 HEAD 未包含 IP 定义、TestBench、裸机固件与重建脚本；这些属于 not_in_current_repo。补充 ZIP 后，原始 IP/工程/固件/测试已找到，详见顶部更正；历史验证仍不代表本轮已完成重建。

## 2. 功能与路径映射

| 内容 | 实际位置 | 当前判断 |
|---|---|---|
| CPU 入口 | `src/rtl/cpu_core.v` | 五级流水线装配，连接 Cache/CSR/旁路/预测与控制 |
| 阶段/寄存器 | `if_stage.v`、`id_stage.v`、`ex_stage.v`、`mem_stage.v`、`if_id.v`、`id_ex.v`、`ex_mem.v`、`mem_wb.v`，均在 src/rtl | 已有 baseline；本轮无功能仿真 |
| 控制/运算 | `src/rtl/ctrl.v`（stall_ctrl）、`bypass.v`、`regfile.v`、`branch_predictor.v`（predictor）、`mult.v`（multiplier）、`divider.v`、`defines.v` | 文件名与 module 名有差异，不批量改名；默认 XLEN=32 |
| SoC / 顶层 | `src/rtl/soc_top.v`、`top.v`、`top_pl_bram.v` | XPR top 是 top_pl_bram；top 提供 AXI master |
| TestBench | **未找到** | XPR sim_1 top 仍是 top_pl_bram，未列独立测试激励；不是已有 TB |
| Vivado 工程 | `board/riscv_vivado_project/riscv_vivado_project.xpr` | 文件记录 Vivado v2025.2；BoardPart 为空 |
| 板级约束 | `board/riscv_vivado_project/riscv_vivado_project.srcs/constrs_1/new/constrs.xdc` | clk/UART/button/LED/reset pin；20 ns 主时钟；目标板兼容性未确认 |
| 软件 | `ascon/ascon_c/aead/`、`ascon/ascon_c/xof/`、`ascon/pyascon/` | 现有算法代码；未找到 RISC-V startup/linker/Makefile/测试映像/加载脚本 |
| CPI 事件 | `src/rtl/cpi_cnt.v`，由 cpu_core 探针经 soc_top 接入 | 0x60000000 MMIO；非总周期，flush 每次 +2 |
| cycle / CSR | `src/rtl/csr_file.v` | 64-bit mcycle 每周期递增，RV32 0xb00/0xb80；读地址未含 0xc00/0xc80 |
| AXI / bus | `src/rtl/bus_interconnect.v`、`cpu_axi_bridge.v`、`axi_full_master.v`（axi_master） | 已有 RTL；PS 控制接口尚不存在 |
| Cache | `src/rtl/icache.v`、`dcache.v` | cpu_core 实例化；后续需回归与一致性验证 |
| UART | `src/rtl/uart_ctrl.v`、`uart_rx.v`、`uart_tx.v` | MMIO 0x20000000；UART FIFO/IRQ 已有 RTL |
| GPIO | `src/rtl/gpio.v`（gpio_ctrl） | MMIO 0x20010000；LED / button |
| CLINT | `src/rtl/clint.v` | MMIO 0x12000000；mtime/mtimecmp/msip |
| Ascon RTL | `src/rtl/ascon/ascon_round.v`、`ascon_word.v` | 分别只有 ror、load_bytes/store_bytes；无完整 permutation/ISE，无 CPU/XPR 接入 |

更细地址、周期计数和目标命令接口见 [interfaces](interfaces.md)。

## 3. 工程 target、引用和缺失依赖

- XPR 第 11 行的 Part，以及 synth_1/impl_1 的 Part 均为 **xc7k325tlffv676-2L**。全仓检索原始文件未找到 XC7Z020 配置。
- XPR 顶层 `top_pl_bram`；project path 元数据保留旧绝对路径 `D:/HCZ/Projects/amd_fpga_2026/...`。源引用使用 `$PPRDIR/../../src/rtl/...`，XDC 用 `$PSRCDIR/...`。不能仅看到旧 Path 就断言 Vivado 无法打开；也不能未验证就改路径。
- XPR 列出的 31 个 RTL/header 路径和 1 个 XDC 均存在；`src/rtl/ascon/` 两个文件未进 XPR。文件引用齐全仍不代表完整设计可展开。
- `top_pl_bram.v` 的 `clk_wiz_0`、`axi_bram_ctrl_0`、`blk_mem_gen_0` 没有 module 定义、XCI/BD 或重建 Tcl；本仓库也未含 .coe/.mem/.hex/.elf 等程序输入。
- `top.v` 的 `RAM_INIT_FILE` 参数存在但未传入实际存储加载链。复位 PC `0x10000000`；需要 B04 恢复固件/链接/加载方式。
- XDC 约束输入 50 MHz，wrapper 使用名为 clk_100m 的时钟；缺 clock IP 配置，输出频率不作已验证结论。没有 timing/utilization 报告，无法报告 PPA/Fmax。
- 未发现 PS block design、PYNQ notebook、bit/hwh/image 清单。具体板型未给出，必须由 B03 核板，不能根据芯片猜 image。

## 4. 生成文件与必须保留项

| 分类 | 路径 / 处理 |
|---|---|
| 已跟踪生成元数据 | `board/riscv_vivado_project/riscv_vivado_project.cache/wt/project.wpc`（61 bytes）；`.hw/riscv_vivado_project.lpr`（425 bytes）；本轮不删、不取消跟踪 |
| 核心必须保留 | 全部 `src/rtl/`、`ascon/`；即使尚未验证也不能删除旧实现 |
| 工程必须保留 | 原 XPR、XDC 和路径；虽然 XPR 由工具维护，它仍是当前唯一工程配置，不能按垃圾输出处理 |
| 来源/文档必须保留 | LICENSE、历史选题指南、既有 pyascon README；README 本轮由空文件补齐 |
| 后续必须保留 | Tcl/IP 源配置、内存初始化输入、synthesis/implementation/timing/utilization 摘要、benchmark CSV/JSON、KAT 结果、复现元数据 |
| 后续不入库 | .Xil、*.cache、*.runs、*.gen、*.sim、临时 waveform、Python/editor cache、私有 agent 工作目录；受控结果移至 build/reports 或 data |

本轮前无 .gitignore，本轮新增精确目录/后缀规则；不忽略整个 build，也不全局忽略 .tcl/.rpt/.csv/.json/.xci/.bd/.coe/.mem 或所有 .log。ignore 不会改变已跟踪文件，清理历史产物是后续独立任务。

## 5. 文件名、编码与提交风险

- 原根目录 `AMD 自主选题赛道.md` 含中文、空格和大写字符；按保护现有文件要求保留，并列为 D05/D06 发布检查项。需要转换发布路径时先记录映射、验证所有引用，不能本轮静默重命名。
- README.md、AGENTS.md、LICENSE 与 .gitignore 等明确约定名称作为规范例外；新普通文件一律小写 ASCII，扩展名允许分隔点。
- 既有 `.srcs`、`.cache`、`.hw` 是 Vivado 工程惯例，本轮不改；不把工具生成目录命名当作手工新目录范例。
- XDC 注释无法按 UTF-8 严格解码；`defines.v` 部分注释含替换字符。命令和标识符可读，但不能为美化注释全量转码；记录独立问题。
- XPR 带旧机器路径元数据，干净环境是否自动重定位尚未实测；Tcl 和最终发布材料不得依赖该路径。
- 除该历史选题指南外，原始树未发现其他含中文或空格的路径；原文件树与清单附后。

## 6. 本轮目录映射

| 请求目录 | 处理 |
|---|---|
| src/ | 已有，保留 rtl，新增 readme.md；软件仍在 ascon/ |
| board/ | 已有，保留整个原工程，新增 readme.md |
| ascon/ | 既有软件目录，不强行归并 src/；README 显式映射 |
| docs/ | 新增审计、概览、架构、技术约定、接口、开发/agent 流程、决策、风险 |
| tasks/ | 新增 task_board、milestones，任务 owner 全 TBD |
| project_log/ | 新增开发活动、事实进度、失败经验 |
| sim/build/data/skill/report | 新增各 readme.md，使空骨架可被 Git 跟踪；不伪造实现或结果 |

## 7. 实际查阅范围

不是“所有代码已经逐行审查”。完整扫描包括 62 个文件的路径、大小、字节哈希、代码文本解码/特征检索；重点内容读取如下。

| 阅读方式 | 文件 |
|---|---|
| 用户输入全文 | 本轮附件“已粘贴的文本.txt”（仓库外），作为任务范围依据 |
| 文档/配置全文或完整输出读取 | 原空 README；历史选题指南；XPR/XDC；project.wpc、.lpr；ascon/pyascon/README.md |
| 核心完整内容读取 | src/rtl/top.v、top_pl_bram.v、defines.v、cpi_cnt.v、csr_file.v、clint.v；src/rtl/ascon 两文件；ascon/ascon_c/aead/api.h |
| 重点片段/模块引用/参数与地址检索 | cpu_core、soc_top、bus_interconnect、icache/dcache、cpu_axi_bridge/axi_full_master、UART/GPIO、if_stage、id_stage/ex_stage、其余流水/预测/乘除法 RTL |
| 算法标记与接口检索 | ascon/ascon_c 全部 .c/.h 的 includes/API/IV/版本；pyascon .py 的 variant/端序/入口；没有执行软件测试 |
| 协议识别 | LICENSE 的 Apache-2.0 开头；本轮未做第三方许可法律审查 |

参考仓库通过现有 Git 权限只读浅克隆到系统临时目录，未加入本仓库，未复制代码。固定提交 **9c34288aa040fb926eefa8603c85f0d19522e849**，实际查阅 `README.md`、`AGENTS.md`、`docs/agent对接.md`、`docs/技术约定.md`、`docs/文档维护.md`、`docs/项目整理.md`、`计划和任务/任务清单.md`、`项目记录/实际进度.md`、`项目记录/开发记录.md`、`项目记录/经验与踩坑.md`、`.gitignore`；重点读取长文档的任务、交接、节点与维护规则。只借鉴结构，不复制其小车内容。

外部入口（2026-09-21 查阅）：[参考仓库](https://github.com/Freebird415/phantom-drive)、[NIST final 发布页](https://csrc.nist.gov/pubs/sp/800/232/final)、[ascon-c README](https://github.com/ascon/ascon-c)、[pyascon README](https://github.com/meichlseder/pyascon)。本轮未锁定后两者的实现提交；这是 C01 待办，不能作为已完成 KAT 的证据。

## 8. 实际检查与结果

环境：Windows PowerShell；Python 3.14.3；Icarus Verilog 12.0 devel（s20150603-1539-g2693dd32b）。PATH 未发现 vivado/vitis/verilator/riscv64-unknown-elf-gcc/riscv32-unknown-elf-gcc，不代表这些工具一定未安装。

静态命令使用 `src/rtl/` 顶层全部 .v，include path 为 src/rtl；输出在系统临时目录。复跑代码见 [build/readme](../build/readme.md)。

| 命令 | 结果 | 限制 |
|---|---|---|
| `iverilog -g2012 -I src/rtl -s top -o <temp>/top.vvp <rtl_files>` | exit=0，无诊断 | 只 elaboration，无 TB/程序执行 |
| `iverilog -g2012 -I src/rtl -s top_pl_bram -o <temp>/top_pl_bram.vvp <rtl_files>` | exit=4 | 缺 IP 定义；没有注入假模块 |

第二条原始诊断核心：

```text
src/rtl/top_pl_bram.v:28: error: Unknown module type: clk_wiz_0
src/rtl/top_pl_bram.v:161: error: Unknown module type: axi_bram_ctrl_0
src/rtl/top_pl_bram.v:214: error: Unknown module type: blk_mem_gen_0
4 error(s) during elaboration.
```

未执行 Vivado 构建、功能仿真、KAT、benchmark、上板或 PYNQ。最终文档与保护检查结果附后。

## 9. 优先阻塞与下一步

1. **B02**：找回 CICC1000023 的可复现源/IP/Tcl/TB/固件资料，建立独立 baseline 重建记录；B04 同步恢复启动/链接/加载。
2. **B03**：核实目标板卡与 image/约束，在独立 XC7Z020 配置完成 sanity；保留原 Kintex 工程。
3. **C01**：锁定 SP 800-232 final 对应可信 reference/KAT/许可证/哈希，之后才判断已有代码是否需修改。

当前最大五项风险：器件/IP 不匹配（R13）、无法 clean clone（R10）、标准/KAT 混淆（R1）、计数器和 benchmark 语义（R14/R4）、PYNQ 板级兼容（R6）。

## 本轮收尾核验

- 原始 62 文件中仅空 README.md 获准改写；其余 **61 文件 SHA-256 与审计基点一致**，无删除/搬迁/批量重命名/工程改写。
- 新增 **23 文件**：.gitignore、AGENTS.md、docs 的 9 个文件、tasks 的 2 个文件、project_log 的 3 个文件，以及 src/sim/build/board/data/skill/report 下的 7 个 readme.md。改动集中在文档与忽略规则。
- 新增/修改的 **23 个 Markdown 文件**可按 UTF-8 严格读取，**43 个本地链接**存在；所有新增路径符合命名约定。
- **41 项任务**均包含 8 列（ID/task 加用户要求的 6 项字段），owner 全 TBD；任务号不重复、引用存在、依赖图无环、前置日期不晚于下游日期。PUF 继续 gated。
- XPR **32 个文件引用**均指向存在路径；缺少的三个 IP 是 module/IP 配置依赖问题，并非上述文件引用消失。
- `git check-ignore --no-index` 的 **16 个保留样例**（Tcl、4 类报告、元数据、CSV/JSON/KAT、XCI/BD/COE/MEM、notebook、验证日志和 Skill 说明）及 **14 个排除样例**（Vivado/Vitis/Python/editor/agent 缓存与临时构建）全部符合预期。
- `git diff --check` 通过；没有暂存、commit 或 push。普通 `git diff --stat` 仅显示已跟踪 README 的 108 行新增，23 个新文件仍为 untracked，需结合 `git status` 审查。
- 上述文档核验没有关闭 B02/B03/B04 的硬件/固件复现阻塞。原始 tree 和 SHA-256 清单见下文。

## 10. 整理前完整目录树

排除 `.git/` 内部数据；没有折叠源文件，以下对应初始 62 个跟踪文件。

```text
amd_fpga_2026/
├── AMD 自主选题赛道.md
├── LICENSE
├── README.md
├── ascon/
│   ├── ascon_c/
│   │   ├── aead/
│   │   │   ├── aead.c
│   │   │   ├── api.h
│   │   │   ├── ascon.h
│   │   │   ├── constants.h
│   │   │   ├── permutations.h
│   │   │   ├── printstate.c
│   │   │   ├── printstate.h
│   │   │   ├── round.h
│   │   │   └── word.h
│   │   └── xof/
│   │       ├── api.h
│   │       ├── ascon.h
│   │       ├── constants.h
│   │       ├── hash.c
│   │       ├── permutations.h
│   │       ├── printstate.c
│   │       ├── printstate.h
│   │       ├── round.h
│   │       └── word.h
│   └── pyascon/
│       ├── README.md
│       ├── ascon.py
│       ├── genkat.py
│       └── writer.py
├── board/
│   └── riscv_vivado_project/
│       ├── riscv_vivado_project.cache/
│       │   └── wt/
│       │       └── project.wpc
│       ├── riscv_vivado_project.hw/
│       │   └── riscv_vivado_project.lpr
│       ├── riscv_vivado_project.srcs/
│       │   └── constrs_1/
│       │       └── new/
│       │           └── constrs.xdc
│       └── riscv_vivado_project.xpr
└── src/
    └── rtl/
        ├── ascon/
        │   ├── ascon_round.v
        │   └── ascon_word.v
        ├── axi_full_master.v
        ├── branch_predictor.v
        ├── bus_interconnect.v
        ├── bypass.v
        ├── clint.v
        ├── cpi_cnt.v
        ├── cpu_axi_bridge.v
        ├── cpu_core.v
        ├── csr_file.v
        ├── ctrl.v
        ├── dcache.v
        ├── defines.v
        ├── divider.v
        ├── ex_mem.v
        ├── ex_stage.v
        ├── gpio.v
        ├── icache.v
        ├── id_ex.v
        ├── id_stage.v
        ├── if_id.v
        ├── if_stage.v
        ├── mem_stage.v
        ├── mem_wb.v
        ├── mult.v
        ├── regfile.v
        ├── soc_top.v
        ├── top.v
        ├── top_pl_bram.v
        ├── uart_ctrl.v
        ├── uart_rx.v
        └── uart_tx.v
```

## 11. 初始逐文件清单与 SHA-256

用于保护原工程的字节核验；README 原为空且本轮获准改写，其余文件保持原值。

| path | bytes | sha256 |
|---|---:|---|
| `AMD 自主选题赛道.md` | 10088 | `61755c2666ee910b79947ba82c21ae20175204dd80013873b7cac5c3bc77e17e` |
| `LICENSE` | 11558 | `1eb85fc97224598dad1852b5d6483bbcf0aa8608790dcc657a5a2a761ae9c8c6` |
| `README.md` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `ascon/ascon_c/aead/aead.c` | 6651 | `1cd8acf61ef195c15043de3281e1ac2795f4e75de2af706af6c6afecc451d0e3` |
| `ascon/ascon_c/aead/api.h` | 224 | `4102b37b91cef127fd059a0319fd1b69d284299dd2386cb8ea2c3468b0bcbaf0` |
| `ascon/ascon_c/aead/ascon.h` | 140 | `24b8b35c623b30f6fb55908170f920a8e059842c7e4f12cad0fdd04ad5f9be99` |
| `ascon/ascon_c/aead/constants.h` | 4714 | `6e95f0ca2457f41fd6f0f301e608804c492a3c9244e21d0e8354b5cd564b1875` |
| `ascon/ascon_c/aead/permutations.h` | 835 | `b9f0d9c50549a0a5c8733196217a352bea10c12420249ceccd809a7ccf0a97c1` |
| `ascon/ascon_c/aead/printstate.c` | 1250 | `1f7c69900b61138987d46f27837a8249a7a19adcd5290b71574fd4e90b037b32` |
| `ascon/ascon_c/aead/printstate.h` | 682 | `49d911e69a3ee4873be8a3a2211549659d9efbc97ec5297e18200c6fd19c8381` |
| `ascon/ascon_c/aead/round.h` | 1257 | `b44435ff8c33966a2fdc11aefce83df3f1923b956e82913734480dc6da66d294` |
| `ascon/ascon_c/aead/word.h` | 1026 | `257b5e3248e29ed1b65c9e670ade92bcf0432790364e332c6ae78f5fd9fa5ab1` |
| `ascon/ascon_c/xof/api.h` | 150 | `f68a50a6f1ea01497c96606845c135f609ccfa0ef72b4154b496f73f7b7e1713` |
| `ascon/ascon_c/xof/ascon.h` | 140 | `24b8b35c623b30f6fb55908170f920a8e059842c7e4f12cad0fdd04ad5f9be99` |
| `ascon/ascon_c/xof/constants.h` | 4714 | `6e95f0ca2457f41fd6f0f301e608804c492a3c9244e21d0e8354b5cd564b1875` |
| `ascon/ascon_c/xof/hash.c` | 2068 | `8e8c7d27c9a55b7bbd2f61a9ddac00a1bf787996489b6a5d5964781ed93ed2b7` |
| `ascon/ascon_c/xof/permutations.h` | 835 | `b9f0d9c50549a0a5c8733196217a352bea10c12420249ceccd809a7ccf0a97c1` |
| `ascon/ascon_c/xof/printstate.c` | 1250 | `1f7c69900b61138987d46f27837a8249a7a19adcd5290b71574fd4e90b037b32` |
| `ascon/ascon_c/xof/printstate.h` | 682 | `49d911e69a3ee4873be8a3a2211549659d9efbc97ec5297e18200c6fd19c8381` |
| `ascon/ascon_c/xof/round.h` | 1257 | `b44435ff8c33966a2fdc11aefce83df3f1923b956e82913734480dc6da66d294` |
| `ascon/ascon_c/xof/word.h` | 1008 | `77409ad234d666bb3fa14a5fb34cf6f40196bac40eeff8ca73f9fbe54d8f3bb3` |
| `ascon/pyascon/README.md` | 5183 | `2b858ec527002892d07a220419b6b14382b2e3c6dfd1291f5a4d12946651cc72` |
| `ascon/pyascon/ascon.py` | 20625 | `d1f3e185ff299a891eb7ab286c2c053ae75ccf25a1246f99eb2946625123b66e` |
| `ascon/pyascon/genkat.py` | 5139 | `6fd7a93dcccb2976494d8dd02fadce23cd0a809d2b84d98ba8650edbc9ccf1ac` |
| `ascon/pyascon/writer.py` | 5885 | `d532175d5b71ffbfc1b3c44da7d792e12323a5c36bc1ce566a85c5e6e9a653cf` |
| `board/riscv_vivado_project/riscv_vivado_project.cache/wt/project.wpc` | 61 | `ee9038c533d94eb3a610d16227d9cce9db798352497f0ba7e005afc06ad7aa3e` |
| `board/riscv_vivado_project/riscv_vivado_project.hw/riscv_vivado_project.lpr` | 425 | `b373cf9663fa8b6acdd3cceeb201aea1c7fbbee5cf7c6d675bf0c6ccd52f4c69` |
| `board/riscv_vivado_project/riscv_vivado_project.srcs/constrs_1/new/constrs.xdc` | 901 | `e13fefdc309c09271ad8780208edaa13fda6d5a290f5c40b08e15ae7b4eae290` |
| `board/riscv_vivado_project/riscv_vivado_project.xpr` | 19858 | `a5f54c758adea1ccbbf6042e3ed6823a46139d57250133a32f2b60943552c6e6` |
| `src/rtl/ascon/ascon_round.v` | 269 | `0c04effa44590673ae048d958d0b65887e0eb33b0cfe4b5ec80dc58115a657be` |
| `src/rtl/ascon/ascon_word.v` | 651 | `daea6ac80b1e8a8f20f15c3eb8696eba4a58671f6939378a41909413d703f51b` |
| `src/rtl/axi_full_master.v` | 15512 | `7130b046b3e9074a5dab20099a5c49aa49c5b6ddd24bb9e67b261ea2153b1dd5` |
| `src/rtl/branch_predictor.v` | 3964 | `c8e9c26c8f74ff6d7f11046e6a2b36a5b6cd84fc0196eab806790da8e6da9df1` |
| `src/rtl/bus_interconnect.v` | 15222 | `a0c8a1d52b4247e422a034297a1e653423abd2086a605e6b8b267d8348b04365` |
| `src/rtl/bypass.v` | 988 | `31796dd4efa681cd72057f39d9ee5fc2aa4b9a9bfd6f72c402469c740f1cecf5` |
| `src/rtl/clint.v` | 4469 | `539b86f859db13e08a5923832ff7443ec272eeaf17f0872365a8da7b653db95c` |
| `src/rtl/cpi_cnt.v` | 2254 | `01a7e126bdbdb481bf3301aa350457996976690a58ab303312435db63d3f06de` |
| `src/rtl/cpu_axi_bridge.v` | 10651 | `1c08e8ca0a7588ebbfa9938d304172c4bade8ad6fab4ca9fdac10bcb51547987` |
| `src/rtl/cpu_core.v` | 25326 | `ccc51a554da4abc3e44d779a68e842f30db7310ae0ce3c914b5dd40f27cb3b67` |
| `src/rtl/csr_file.v` | 8130 | `b017d3f876957fa5818a3fdbb5f6c1fb6682b8f4f2b67c85973afe7e49838c49` |
| `src/rtl/ctrl.v` | 4624 | `b6f4eef20b1e1c2394c5d6c48cd121e6943224f06d751bc7b2bf6b794a0cb559` |
| `src/rtl/dcache.v` | 17130 | `5532245684c1ccabef440d105dda66f44fb8e5b4a522589740bbe7269924dc11` |
| `src/rtl/defines.v` | 6268 | `c8958c2f2523ec73980c74de726728d1da4e473137d43077812ebb24bb056e80` |
| `src/rtl/divider.v` | 7061 | `1b553787ab718b493cf89cbc3cb817f28b06104851920e2cf2fe610aafa5b32a` |
| `src/rtl/ex_mem.v` | 2754 | `d656b3387ca73ce2e4d9eb4e01f1503fe8a91c05f9f70fd054c69a9b6fddd7e6` |
| `src/rtl/ex_stage.v` | 18328 | `34061bbba1caab321390067af9b01ad8fddf18f8b0532245ec72fd96edd9cfdf` |
| `src/rtl/gpio.v` | 7465 | `9bc51017dc6e1d280125a59bcc9d0b095b25c6746438f9107d835d403da0af5b` |
| `src/rtl/icache.v` | 11226 | `ab2001b57bac463f168714a7843f07330c2072f91d1c80ec0014fbf4f9dc988f` |
| `src/rtl/id_ex.v` | 6210 | `7588b49e7a4b12d61ee933f73fda8136f902c578cf7cf809c31e540efac9ca84` |
| `src/rtl/id_stage.v` | 43041 | `e7cc97c530ba792549070a200c0056b625e872de81aefbaefea1dc677e267310` |
| `src/rtl/if_id.v` | 3664 | `a9df4d2c0ee14fa70e166459caee4b68cf0f491888c3d2bc29c4dbff042468ce` |
| `src/rtl/if_stage.v` | 1418 | `e2770b86300b4209dda7ed9673c976ff2efbe7ecabf120b32458bfcc8400a0cb` |
| `src/rtl/mem_stage.v` | 4591 | `9afab521420ad1a6241b571a61269ee4774b87f55fbcf63af0601b616ff26317` |
| `src/rtl/mem_wb.v` | 1415 | `26a5880c73a089249c6278cb8b93b1db6d23ec0f02c2fd8ecfcf1cc4e58e6e10` |
| `src/rtl/mult.v` | 2148 | `dcff59d086098167667f2365364743b26c1dad82fd7544be616fd0eb3ae0a904` |
| `src/rtl/regfile.v` | 1646 | `5aacf513bb2db596afebe3428ff472c1639d7369769c718a3af64a6d19cfca69` |
| `src/rtl/soc_top.v` | 16844 | `623cc69b19d26533fbfc952fea2ccaa95304b1be4d08b80ebe0c3222c9dfc91f` |
| `src/rtl/top.v` | 4651 | `37405e5d5b8f5f5b565499264fac463d7346ee9561ad0b0cbae39ab461229dc2` |
| `src/rtl/top_pl_bram.v` | 6813 | `6098a6f7056fad1fe8275df55e53ef15bbf448e4756e89037ad4a522c7d1fc31` |
| `src/rtl/uart_ctrl.v` | 7014 | `c9a0bba23e8d23c528ba9c7e7e4063624216a1085634aa36c677f534f631a5bc` |
| `src/rtl/uart_rx.v` | 4455 | `b2de3abd1e006c8f3bef4cfd55e8a9cce96606ddbf10a3a13fd17f4dbb697a40` |
| `src/rtl/uart_tx.v` | 2391 | `3e72b58918843c2a57b10b8b52456c4a9f8e0102a7ceee6e0d79b73a7f370c1d` |

## repository foundation 收口补记

上述目录树、路径和 61 文件保护结论是最初审计快照。用户随后批准去重：XPR/XDC 核对相同后，原 tracked Kintex 经 git mv 统一为 board/vivado_kintex7_legacy，旧入口移除；两项 .cache/.hw 生成元数据从索引和工作区清理。RTL/XPR/XDC 未修改。当前目录、579 资产分类与 Git 检查见 [收口检查](repository_foundation_closeout.md)。
