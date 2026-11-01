## 5 验证体系

密码加速器的验证难点不限于"能否得到结果"，而在于证明其结果符合标准，且在异常情形下不产生错误放行。
本章按 L0–L4 五个层级展开：标准一致性、模块 RTL、系统回归、历史 PL-only 板测与当前 PYNQ 板测。各层判据性质
不同：host 层考察逐字节一致性，RTL 层考察事务契约与波形，板级层考察同一固件在真实芯片上是否产生
相同密文。

### 5.1 验证体系与层级划分

| 层级 | 对象 | 手段 | 判据 | 状态 |
|---|---|---|---|---|
| L0 标准一致性 | C 与 Python 参考实现 | 独立下载的官方 KAT 逐字节比对 | 1,089 组加密、解密与负向用例全部通过 | 完成 |
| L1 模块级 RTL | 置换器、AEAD 适配器、Cache、ISE | Icarus/XSim 定向 TB 与 golden 状态比对 | 与锁定参考逐字节一致，事务契约成立 | 完成 |
| L2 系统级 | 整个 SoC 与真实固件 | `run_tests.py` 自动回归（smoke 与 regression） | 报告 JSON/Markdown，非零退出即判失败 | 完成（含 NOT_RUN 项） |
| L3 板级 | 三份镜像与真实芯片 | 串口 KAT 与 benchmark 采集 | SW 6 组、ISE 与 MMIO 各 4 组官方向量，含篡改拒绝与周期数 | 完成 |
| L4 PS/PL 协同 | 当前 release、服务固件与 host API | 容量内 KAT、Notebook、warm benchmark、错误恢复 | 三模式各 289/289、9/9 错误门禁；simulated=false | 有限范围通过（见 §8） |

> <span class="figslot">图 3-4</span> **五层验证体系与证据流**：host → RTL → SoC 仿真 →
> 历史 PL-only 板测 → 当前 PYNQ KAT、benchmark 与错误恢复，各层单列范围。

### 5.2 L0：标准一致性与向量冻结

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

### 5.3 L1：模块级 RTL 验证

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

> <span class="figslot">图 3-8</span> **Vivado 仿真波形：ISE 置换执行**：在 XSim 中打开 ISE 集成测试，
> 截取 custom-0 指令进入 EX、`ex_stall_req` 保持、置换完成后 `done` 与流水推进的一段波形。

### 5.4 L2：系统级自动回归

入口为 `sim/board/run_tests.py`，共两档：

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
Python 3.14.3），与 host KAT 所用的 WSL 环境（Python 3.12.3、GCC 13.3.0，见 §5.2）分属两套工具链，
故文中出现的多个 Python 版本各有其归属。

### 5.5 L3：纯 PL 镜像的板级验证

**KAT 与篡改拒绝**（三份镜像，同一板卡、同一串口、同日执行）：

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

> <span class="figslot">图 3-5</span> **历史 PL-only 串口日志摘录**：SW/ISE 日志的 KAT 与 benchmark，
> 为文本重排而非界面截屏；正面实物照片另见系统实物图，其他现场素材待补。

### 5.6 缺陷发现与处置

本节记录验证过程中发现的问题及其处置，按"发现、定性、修复、复验"组织，其信息量高于"通过项"列举。

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

### 5.7 未闭环项

| 项 | 状态 | 影响 |
|---|---|---|
| 板上 ISA 抽样回归（含已知 `rv32ui_ma_data` 失败） | <span class="blocked">未执行</span> | 不得声称指令集已在板上全覆盖 |
| 完整 1,089 组 KAT 板级运行 | 289 组容量内通过；800 组超容量 NOT_RUN | 全量仅 host，当前服务不承诺超容量功能 |
| MMIO 长度能力 | 仅 ≤16 B | 不得泛化为任意长度 |
| 板级真实 IO 延迟 | <span class="blocked">not_measured</span> | 20 ns 为建模上界，见 §4.3 |
| PS/PL 与 PYNQ | Notebook、benchmark、9/9 错误门禁已执行；小时级、冷启动重复性未测 | 当前架构无共享可缓存 buffer；不应伪造缓存测试 |
| RV64 / 完整异常矩阵 | 未验收 | 定向中断通过不等于所有 ISE 抢占上下文均通过 |
| 芯片丝印速度等级现场核对 | <span class="blocked">未做</span> | 沿用 `-1` 约束，风险记录于 `docs/risks.md` |

<span class="evid">证据 docs/ascon_standard_baseline.md §3–§5、docs/ascon_key_management.md §自动验证入口、project_log/actual_progress.md 2026-10-25/10-26/10-27 条目、docs/freeze_checkpoint_20261027.md §3–§5</span>
