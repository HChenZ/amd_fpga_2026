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



