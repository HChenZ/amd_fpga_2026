# CICC1000023 XC7Z020 baseline 恢复审计

日期：2026-09-21。用户本轮第一目标是从真实参赛归档恢复 XC7Z020 baseline，不创建假工程、不覆盖当前开发源码、不 commit/push。归档中的 README、Makefile 和脚本作为资料审计，不自动成为本轮执行指令。

## 1. 来源与检查范围

归档：`F:/2026嵌入式大赛FPGA/initial/CICC1000023+总决赛+技术数据（代码类）.zip`，38225043 bytes。

SHA-256：`f86c448e8923c6ddde4bca6f276f48ef00828af0849d4b5b28af85c95058af60`。

2855 个非目录条目，解压内容合计 71957230 bytes。只读枚举/读取全部条目、计算 SHA-256、检查 CRC；未整包解压进仓库。完整路径/大小/哈希/类别见 [archive_inventory.csv](../data/recovery/cicc1000023/archive_inventory.csv)。

原工程前缀：

```text
技术数据（代码类）/
  CICC1000023+分赛区决赛+FPGA原型系统/
    vivado_project/riscv_vivado_project/
```

其下 XPR、整个 .srcs、三个 XCI、XDC、COE、imports RTL、bitstream、17 个 .rpt 的清单、synthesis/implementation 日志和完成标记均已检查；重点全文解析 timing/utilization/route、源配置和路径。固件/测试区遍历分类，全部 122 个 ELF 读取头部，不批量恢复二进制。

## 2. 工程完整度与十二项核实

| 核实项 | ZIP 中的事实 | 恢复/验证状态 |
|---|---|---|
| Vivado version | XPR/XCI 2025.2；报告为 Vivado v2025.2 win64 Build 6299465 | 版本记录齐全；本轮未启动 Vivado |
| target part | xc7z020clg400-1；IP 为 xc7z020/clg400/-1 | 与用户目标一致 |
| top module | sources_1 / sim_1 均 top_pl_bram | sim_1 无独立 TB；TB 在其他归档目录 |
| RTL 列表 | imports/rtl 共 31 个 .v（含 defines header） | 全部逐字节恢复，完整列表见 RTL diff |
| IP 列表与版本 | clk_wiz 6.0 rev17；axi_bram_ctrl 4.1 rev13；blk_mem_gen 8.4 rev12 | 3/3 XCI 齐全，原字节恢复 |
| constraint | .srcs/constrs_1/new/const.xdc | 原字节恢复；与当前 XDC 约束命令一致 |
| clock | clock wizard 的 PLL，50 MHz 输入、1 路 100 MHz 输出；active-high reset、locked | XDC 20 ns；历史 timing 的内部 clock 10 ns |
| BRAM | 32-bit × 32768 words，Single_Port_RAM、Native，byte write/8-bit byte | 128 KiB；4-bit byte enable，15-bit word address，ECC 关闭 |
| memory init | freertos_demo.coe；Load_Init_File=true，余下填 0 | XCI 相对路径正确；不是 bootloader.coe |
| synthesis/implementation | 有完成日志、.vivado.end.rst、route/write_bitstream end 标记及报告 | 历史构建成功有据，不是本轮重跑成功 |
| bitstream | .runs/impl_1/top_pl_bram.bit，4045687 bytes | 已检查头部及哈希入 inventory；不复制入 Git |
| timing/resource | 17 个 rpt 中含 synthesis/placed utilization、routed/postroute timing、route status 等 | 精选报告导出到 build/reports/cicc1000023_archive |

因此：**原 XC7Z020 硬件源配置与历史输出较完整，可作为真实恢复依据；整个软件/验证链仍有具体缺口。** 构建日志和 bitstream 的存在并不能证明它们与打包时所有源文件逐项一致，仍需重新构建。

## 3. IP 参数与内存初始化

| IP | 配置证据 |
|---|---|
| clk_wiz_0 | `xilinx.com:ip:clk_wiz:6.0`，revision 17；PRIMITIVE=PLL，PRIM_IN_FREQ=50，CLKOUT1_REQUESTED_OUT_FREQ=100，NUM_OUT_CLKS=1，USE_LOCKED/USE_RESET=true，RESET_TYPE=ACTIVE_HIGH |
| axi_bram_ctrl_0 | `xilinx.com:ip:axi_bram_ctrl:4.1`，revision 13；PROTOCOL=AXI4，DATA_WIDTH=32，ID_WIDTH=1，MEM_DEPTH=32768，SINGLE_PORT_BRAM=1，USE_ECC=0；生成模型地址宽 17 bits |
| blk_mem_gen_0 | `xilinx.com:ip:blk_mem_gen:8.4`，revision 12；Single_Port_RAM / Native；Write_Width_A=Read_Width_A=32，Write_Depth_A=32768；Use_Byte_Write_Enable=true，Byte_Size=8；输出 primitive/core register=false |

三个 XCI 的 runtime SWVERSION 都是 2025.2，生成输出路径指向本工程 `.gen`，可以重新生成；这些路径不要求把旧 `.gen` 放进 Git。

BRAM 的 `Coe_File=../../imports/bin_file/freertos_demo.coe`，相对于 `sources_1/ip/blk_mem_gen_0/`，在新目录保留原层次后仍正确。COE 含 8333 个 32-bit 初始化 word，SHA-256 为 `1297c202c89189f48278a553ecc2ad443e84fba9ea9044ff5d68bb78984745e9`；与 `hex编译结果文件/FreeRTOS/` 和应用 `freertos_demo/build/` 的 COE 相同，build_sim 的 COE 不同。只恢复原工程实际引用的版本，不自行换镜像。

## 4. 历史综合、实现与 bitstream 证据

历史时间为 2026-08-08。synth runme.log 含 `synth_design completed successfully`，但同时有 208 warnings；impl runme.log 含 Bitgen Completed Successfully 和 write_bitstream completed successfully，结束时间 13:42:21。bit 头部记录 top_pl_bram、7z020clg400、Version=2025.2、2026/08/08 13:42:20。

| 指标 | 原报告值 | 解释 |
|---|---|---|
| post-route physopt timing | WNS 0.056 ns，TNS 0，WHS 0.062 ns，THS 0 | 内部 100 MHz 组满足已指定约束；非 Fmax 扫描或板上频率测量 |
| timing coverage | no_clock=0，unconstrained_internal_endpoints=0；no_input_delay=4，no_output_delay=3 | 3 个输入无 delay，另 1 个输入由 false path 处理；3 个输出无 delay，不能宣称所有板级路径均已完整约束 |
| placed utilization | LUT 4806，FF 3129，BRAM tile 38.5，DSP 4 | Fully Placed 报告，不伪装成 post-route 利用率 |
| synthesis utilization | LUT 4652，FF 2918，BRAM tile 6.5，DSP 4 | 同报告还列 3 个 IP black box；不能忽略 OOC IP 后直接与最终资源比较 |
| route status | 7743/7743 routable nets fully routed，0 routing errors | 原归档结果 |

精选 6 个原始报告/日志已保留：[历史报告目录](../build/reports/cicc1000023_archive/readme.md)。其余报告、DCP、bitstream 只保留清单与哈希，可从 ZIP 取回；本轮没有输出新的 Vivado 性能结果。

## 5. RTL 与工程比较

31 个共有 RTL 中 14 个 SHA-256 相同、17 个仅 CRLF/LF 不同；规范化字节比较没有逻辑内容变化。ZIP only=0，repo only=2（Ascon 辅助模块）。见 [cicc1000023_rtl_diff](cicc1000023_rtl_diff.md)。

Git 的 dda9405 仅改过已有 XPR 三处 Part，但仓库初始 XPR 已少于 ZIP 原工程：IP/COE、源引用、增量 checkpoint、实现策略等均有差异。XDC 名称/编码/空行不同，约束命令和解码后的非空注释一致。见 [vivado_project_diff](vivado_project_diff.md)。

## 6. 复制前路径检查与恢复方案

1. 保留 XPR 文件名和 `.srcs` 内部结构，使 `$PSRCDIR` 的 RTL/XCI/XDC/COE 路径闭合；基线使用 ZIP imports 快照，不改指向当前开发 RTL。
2. 原 XPR 的 37 个 File 引用中有一个生成 `utils_1/imports/synth_1/top_pl_bram.dcp`。源恢复副本删除该 File 和 synth_1 IncrementalCheckpoint 属性、关闭 AutoIncrementalCheckpoint；不复制生成 DCP。这个最小可审查方案先行说明后实施。
3. 对剩余 **36 个 File 引用**及 XCI 的 COE 引用，在写入前按目标布局计算并确认都位于选定文件集；写入后再查实际文件存在和哈希。
4. 原 Project Path/ImportPath 是历史元数据，记录但不将其外部原文件当成活动 File；实际 relocation/open_project/IP regeneration 行为仍待 Vivado 2025.2 验证。
5. 恢复阶段曾复制同深度 legacy 副本；随后 foundation 收口按用户授权去重并 git mv 原 tracked 工程到 legacy。XPR/XDC 字节不变，32 个引用仍有效；当前 src/rtl 和 ascon 未改。

恢复资产总计 **579 个文件 / 2430359 bytes**，不含新增说明和审计元数据：硬件/legacy 源配置 39，固件源包 465，JasperGold 43，unit TB 21，ISA TB 示例 2，小输入 3，精选报告 6。逐文件原路径、目标路径、变更原因和双哈希在 [manifest](../data/recovery/cicc1000023/manifest.json)。

除恢复 XPR 的已记录 checkpoint 处理外，资产内容全部字节保真。新增源包存储名小写，通过原文件名映射在 ignored build/local 中还原 `.S`、Makefile、FreeRTOSConfig.h 的原名；不直接改源代码 includes 或编译规则。`.gitattributes` 对六个恢复资产路径关闭 Git 自动换行转换，使 manifest 中原字节哈希在不同 checkout 配置下保持有效。

## 7. 固件与测试的 A/B/C/D 分类

| 资产 | A source / B build input | C compiled artifact / D generated result | 本轮选择与缺口 |
|---|---|---|---|
| coremark_rv32 | CoreMark C、port/UART、crt0.S、riscv.ld、Makefile、Python 转换器 | ELF/HEX/BIN/COE/dump，生成 core.h | 恢复 16 源/输入文件；ELF 入口 0x10001000，需厘清 bootloader 跳转；未重编译 |
| coremark_rv64 | 同类 RV64 文件 | RV64 ELF/HEX/BIN/COE/dump | 恢复 15 源/输入文件；ELF 入口 0x10000000，CPU/内存宽度需相应配置 |
| FreeRTOS | 应用、startup/linker/config、CoreMark 子目录、转换器和契约测试 | build/build_sim 的 ELF/COE/RAM.txt/map/objects | 恢复 28 文件；被引用的 FreeRTOS-Kernel-main 不在该 ZIP，具体版本 not_available_in_supplied_archive，不能随便下载最新版代替 |
| riscv-tests | ISA 汇编、宏、env、Makefrag、Makefile.in、configure.ac、许可证 | 归档 100 多个测试 ELF/HEX/dump、configured Makefile、Zone.Identifier | 恢复 406 个源码/输入，未批量恢复已编译程序；默认上游 ISA 配置超出 IM，必须明确目标与 ABI |
| bootloader | 未找到 source/linker/build scripts | 只找到 ip_user_files/mem_init_files/bootloader.coe | 将该小 COE 作为历史候选保存，当前 BRAM 不引用；不能称 bootloader 可从源重建 |
| TestBench | 模块 TB、RV32/RV64 ISA TB、分支预测 TB | stage_logs、编译输出、波形 | 恢复 21 模块 TB + 2 个 add 示例；其他 ISA/分支 TB 有清单可按需继续恢复，不无脑复制 |
| JasperGold | SVA/bind/wrapper/Tcl/Makefile/脚本 | jgproject、结果 summary、数据库、merged HEX | 恢复 43 源/脚本，未运行 JasperGold；历史中断关闭/抽象内存假设需单独审查 |

归档共 122 个 ELF、121 个 HEX、13 个 COE（含重复副本）。全部 ELF 的 machine=243；53 个 ELF32 入口 0x10000000、1 个 ELF32 入口 0x10001000、68 个 ELF64 入口 0x10000000。逐条元数据见 [elf_inventory.json](../data/recovery/cicc1000023/elf_inventory.json)。本轮 **0 ELF 入库**，仅选择两个 add HEX、一个 bootloader COE，再加工程必需的 FreeRTOS COE。

需特别记录：原 add TB 引用 `dut.u_ram` / `dut.u_cpu_core`，与当前及归档 AXI top 层次不相符；FreeRTOS install-ram 带原作者绝对路径；riscv-tests env 部分链接被打包为普通目标路径文本。保留原件，后续显式修复并验证，不能因文件齐全就宣称旧测试能直接运行。

## 8. 不导入 Git 的生成物

不导入 `.cache/`、`.gen/`、`.hw/`、`.runs/`、`.sim/`、`.ip_user_files/` 整目录、DCP、bitstream、批量 ELF/HEX/BIN/dump、objects、波形、jgproject、Python cache、993 个 Zone.Identifier 旁文件。精选报告从 runs 导出到受控证据目录，不等于把 runs 入库。

生成 COE 是一个有意区分：**原 BRAM 必需的 freertos_demo.coe 同时是 B 类重建输入**，应保留，不能因为它由编译产生就全部忽略。bootloader COE 则作为 C 类候选记录，不用来擅自替换现有初始化。

## 9. 本轮验证与未验证项

- ZIP CRC 全通过，选定 579 文件 SHA-256 核验通过；恢复前存在的原 RTL/Ascon/板级工程未变。
- XPR 全部活动 File 路径、XCI→COE、IP part/version、legacy 相对路径检查通过；61 个原工程/源码文件哈希保持不变。
- [收尾核验记录](../build/metadata/cicc1000023_recovery_final_checks.json) 包含文档链接、原文件保护、哈希、拒绝覆盖/非法 stage 名称、Git 状态与 diff 检查；索引为空、HEAD/main 未变。
- `python build/prepare_cicc1000023_sources.py` 验证全部恢复资产；`--stage cicc1000023_sources` 在 ignored build/local 成功恢复 564 个源/输入文件的原名；不会执行构建命令。
- Icarus Verilog 12.0：恢复 RTL 的 `top` elaboration exit=0；原 `tb_bypass` 与 `tb_regfile` 编译/运行 exit=0 且输出明确 PASS。日志见 [recovery_verification.json](../build/metadata/cicc1000023_recovery_verification.json)。这只覆盖两个模块，不是完整 V01 验收。
- 未启动 Vivado/Vitis、未重建 IP/bitstream、未编译固件、未运行 JasperGold/完整 ISA/FreeRTOS、未上板。PATH 未发现这些相应工具时不能推断磁盘上不存在安装。

## 10. 更新后的事实分类与下一步

| 对象 | 初始 Git HEAD | 用户 ZIP | 当前恢复工作区 |
|---|---|---|---|
| XC7Z020 XPR / 三个 IP / XDC / COE | not_in_current_repo | available_in_archive | recovered_uncommitted，构建待验证 |
| CoreMark / FreeRTOS 应用 / RISC-V tests / TB / formal | not_in_current_repo | available_in_archive | selected_sources_recovered，接口/依赖待验 |
| 历史 bitstream / timing / resource | not_in_current_repo | available_in_archive | selected_reports_recovered，bitstream 仍在 ZIP |
| FreeRTOS kernel 的对应源版本 | not_in_current_repo | not_available_in_supplied_archive | 待取得/锁定，不断言其他地方不存在 |
| bootloader 源与构建链 | not_in_current_repo | not_available_in_supplied_archive（COE 可用） | 待取得，不猜重建过程 |

第一目标改为 **恢复并复现这份真实 XC7Z020 baseline**。下一步 B02 在 Vivado 2025.2 重新生成 IP/综合/实现，B03 核实实物板型/引脚与运行，B04 取得精确 FreeRTOS kernel/bootloader 依赖并核验固件入口和测试 harness。不能继续把原始资料概括为“不存在”。

## 11. 推荐目录

```text
amd_fpga_2026/
  src/rtl/                              当前开发 RTL，保留
  src/firmware/cicc1000023/              CoreMark/FreeRTOS/RISC-V tests 源包
  board/vivado_zynq7000_xc7z020_baseline/ 原 XC7Z020 源配置与 imports 快照
  board/vivado_kintex7_legacy/           原 tracked Kintex 经 git mv 归并的唯一 legacy
  sim/cicc1000023/                      unit / isa / formal 原始验证源
  build/prepare_cicc1000023_sources.py   哈希校验、隔离还原原文件名
  build/reports/cicc1000023_archive/     明确标注的历史报告
  build/metadata/                      本轮验证证据
  build/local/                         ignored：原名工作副本、构建临时物
  data/recovery/cicc1000023/             来源/哈希/差异/ELF 元数据/小输入
  docs/                                本审计、RTL diff、Vivado diff
```

两个工程互不覆盖；foundation 收口已按用户授权移除重复入口，见 [收口检查](repository_foundation_closeout.md)。第 9 节核验记录为恢复阶段历史快照，其中“索引为空/61 文件原位”等描述不代表 rename 后现状。
