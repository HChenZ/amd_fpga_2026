# 经验与踩坑

## 2026-10-31 — 路径发现不能只检查有限层父目录

- L3 入口最初只检查 `cwd` 与两级父目录，而 `skill/ab_eval_pynq/test_board/` 到仓库根
  实际是四级，导致 `repository not found`。若采用自动发现，应遍历
  `Path.cwd().parents` 并在失败信息打印候选路径。
- 本项目随后按用户要求改为唯一固定板端路径
  `/home/xilinx/jupyter_notebooks/amd_fpga_2026`；此时不再读取环境变量或 cwd，
  避免同一 Notebook 在不同路径下产生不可比证据。

## 2026-10-30 — 完整 KAT 通过不等于 PUF 验收完成

- `FULL_KAT=True` 的第二次板测已将 PUF3 的 SW/HW/ISE KAT 从代表性样本扩展到项目定义的
  全部 289 组，并保留 30 次 benchmark 和 PUF 流程证据；结果应引用
  `data/pynq_puf3/notebook_20261030_144328/`，不要继续引用早先的 6 组结果作为最新值。
- 这仍是单次上电会话内证据。helper 为会话内数据，跨电源周期、温度/BER/熵/唯一性
  和 RO 域 timing signoff 未测；文档必须把 PUF3 标为功能通过/其余门禁 pending，
  不能写成安全启动或 PUF 完成。
- 时钟记录应使用 HWH/SLCR 推算和 mcycle 实测（约 100 MHz）；PYNQ 2.7 在本板上
  显示 150 MHz 是参考时钟假设造成的派生显示，不应进入 benchmark 的平台频率结论。

## 2026-10-30 — pynq_puf3 首次板测通过但验收边界必须保留

- `notebook_20261030_131920` 已在真实板上完成一次完整 Notebook 流程并以 exit code 0 结束：时钟、身份、SW/HW/ISE 代表性 KAT、benchmark、enroll/reconstruct/HWKEY 流程均通过。
- 该结果只证明单次上电会话内的功能行为。helper 每次复位都重新 enroll，跨电源周期、
  温度/BER/熵/唯一性仍不能从这次结果推断；`529` 是 benchmark KAT 编号，不是 PUF3
  的完整 KAT 数量；RO 振荡环计数器域的负 slack 也仍未签核。
- 报告中 `pynq.Clocks.fclk0_mhz=150` 不代表板上实际频率；应以 SLCR 推算 `99.999999 MHz` 和 mcycle 实测 `99.9882 MHz` 为时钟证据。

## 2026-10-30 — 按魔数分帧时，文本日志里不能出现魔数

- 固件 banner 写了 "puf: Y01P/Y01K"，主机按魔数分帧把这段文本当成 Y01K 帧，吞掉了 Y01S。文本与二进制帧共用同一字节流时：日志里不能出现帧魔数；同时解码器只在确实有请求待响应时识别对应帧，并校验帧头里的 cmd/seq。
- 仿真 TB 按"期望的魔数"跳过文本，模型测试的 banner 也是另写的，所以都没覆盖到真实固件的文本。模型的 banner 要与固件逐字一致，或者直接回放真实板上日志。
- 定位时先看 `tx_bytes`/`service`：tx_bytes=0、service=null 说明失败发生在握手阶段，与 PUF 命令本身无关。

## 2026-10-30 — PYNQ overlay 的 FCLK 不等于 hwh 里写的频率

- PYNQ 加载 overlay 只写 FCLK 分频，不改 PLL；Vivado PS7 IP 在只开 GP0+FCLK0 时自选 IO PLL 1600 MHz，而这块板的启动镜像是 1000 MHz，结果 hwh "100 MHz" 实际只有 62.5 MHz。overlay 的 PS7 时钟必须按启动镜像的 PLL 固定（或改用 PYNQ 按频率设置），并在板上读 SLCR 核对 PLL。
- 原版 PYNQ 2.7 `Clocks.fclk0_mhz` 固定按 50 MHz 参考计算，晶振 33.333333 MHz 的板子读数会偏 1.5 倍；它既不是测量也不是正确的推算。可靠的做法是用 hwh 晶振值重算，并用 CPU 周期计数对 PS 时间独立实测。
- 之前"发布版上板通过、100 MHz"只验证了功能和 cycles，频率本身一直是 not_measured；配置值不能写成实际运行频率。

## 2026-10-30 — pynq_puf3 集成

- 不能把"换一份 COE"当作功能集成：PUF RTL 的 `key_hw_sel` 自动锁定会悄悄改变 MMIO 模式的密钥来源。反例 cosim 要用同一份固件配原 RTL，确认开机 mask 变成 0x05，才能证明修复确实来自 RTL 改动。
- 同一套 SoC+PUF，换了固件/HWKEY 后网表略有变化，旧的最佳策略（RefinePlacement +0.208）在新网表上变成 −0.123。策略结论不能跨网表沿用，每个新网表都要单独过门禁和策略探索。
- `explore_impl.tcl` 在 `open_checkpoint` 之后再调用 `get_runs` 会报错（工程已关闭）：汇总循环崩溃，但各 run 已经完成。数值改从每个 run 自己的 post-route 报告读取，并在 explore 记录中写明；脚本已改成先缓存策略名。
- PowerShell 5 的 `Set-Content -Encoding utf8` 会给文件加 BOM，替换文本没有匹配时也会重写文件；Python 源文件要用编辑工具或 Python 按字节写入。

## 2026-10-25（二）— 扇出复制：候选、别名、只读属性、钩子断链

- **`-force_replication_on_nets` 只是"塞进候选清单"，不是"一定复制"。**
  2025.2 帮助原文是 "Forces the drivers of the specified net objects to be replicated, regardless of
  timing slack"，但实测同一句调用在 `sel_*`（fo 172/141/172/140）上 12 个臂一律只打
  `Identified N candidate nets` + `Optimized 0 net. Created 0 new instance.`；对 `state[3]`（fo=628）才真的
  从 628 降到 25。→ **判断"复制是否生效"只能看副本数与网扇出前后值，不能看命令是否执行成功。**
  另外该选项在 post-route 阶段直接被拒（`ERROR: [Vivado_Tcl 4-265]`），只能在放置后用。

- **`get_nets` 的结果里，一根网可能以多个父子别名反复出现，别把它当成"多根网"。**
  R1 那臂报 `candidates=12`，实际只是 4 根网 × 3 层别名；Vivado 自己会打
  `INFO: [Vivado_Tcl 4-166] Using parent net '<parent>' of the net '<alias>'`。
  → 统计候选数时先按 `Using parent net` 折叠，或者直接用 parent net 名做 `-filter {NAME == ...}`。

- **`MAX_FANOUT` 写网上还是写驱动单元上，对这个判据没有区别**（128 与 16 都试过，结果逐位相同）。
  想用属性调复制，别在这上面反复试；这不是"属性写错对象"的问题。

- **`PERIOD` 是只读属性，改时钟周期只能重新 `create_clock`。**
  hook 里 `set_property PERIOD 18.0 [get_clocks clk]` → `ERROR: [Common 17-107] Cannot change read-only
  property 'PERIOD'`，臂在 phys_opt 之前就死掉（日志里只剩 `period_before`）。
  正确做法：`create_clock -period 18.000 -name clk [get_ports clk]`（同名覆盖），做完再 `create_clock`
  恢复原周期；MMCM 派生时钟会自动跟着变（hook 里两边都打 `core=` 确认）。

- **TCL.POST 钩子不要拷进 run 目录。** 钩子如果用 `[file dirname [info script]] .. <lib>.tcl` 找共用库，
  拷到 `build/local/<wave>/<tag>/` 后相对路径就断了，钩子在 phys_opt 阶段报
  `missing hook file` / `can't read`。要么原地挂（推荐，钩子是纯 ASCII、只读），要么把库一起拷。

- **验证"布局有没有变"最省事的办法：导出 post-place DCP 的 `NAME → LOC` 做 diff。**
  `open_checkpoint top_pl_bram_placed.dcp` + `get_cells -hier -filter {IS_PRIMITIVE}` 各写一行，
  32579 行 diff 为空就是布局逐单元相同。这比 `report_design_analysis` 直观，也足以把
  "收益来自布局还是布线"一刀切开（本轮就是靠它把 +0.097 归到布线解）。

- **phys_opt 自报的"估计 WNS"不能当结论。** `r2_tight` 里恢复约束后它自报 `est_wns=+0.709`，
  布线后实测只有 **+0.057**；生产策略里它自报 +0.247 就"跳过全部 setup 优化"，也是一回事。
  → 任何 phys_opt 阶段的数字都要等 `route_design` 之后的 `get_timing_paths` 才算数。

## 2026-10-18 — V10 文件留存与清理

- 清理范围按用户后续明确授权更新：最终双策略RPT保留、旧报告可删除；原始恢复归档不在
  本轮裁剪范围。不能把“没进综合”直接当作可删，KAT、测试、hash与控制JSON是当前验证依赖。
- 删除前冻结清单和保留文件hash；删除后用新label真实重编译/仿真并比较二进制与mcycle，
  不能仅重读旧JSON宣称回归通过。本次真实复验已证数据全部一致。
- 历史汇总器在缺报告时必须先退出，不能生成空策略结果或先重写全部历史JSON再报错。
- 用户明确删掉的历史证据应在文档标注已裁剪，不继续宣称旧路径存在；最终报告和源/DCP留存完整。
- 并行会话可能恢复/重新生成刚删除的报告。本次8项镜像/周期及231hash一致，但最终留存断言
  因6路径重现而exit 1。不能改掉FAIL或说数据回归失败；分别记录数据PASS和留存待定，先询问用户。
  用户最终选择暂保留并行产物，因此不反复删除或停止其他会话。

## 2026-10-18 — V09 端点分类与握手

- L88：从 top-20 推测全部端点会漏掉第二瓶颈；导出所有 failing endpoints 才确认
  ISE 93、乘法 48、dcache 11、其他 4。A 只能消除一类，不能据此承诺收敛。
- L89：给私有 reset 注册化时，释放要和 start 寄存器同拍；若直接延迟旧 perm_run 复位表达式，
  首个 start 会在 reset 期间被吞。安全清零的额外一拍必须写入接口并用断言验证，不偷偷删清零。
- L90：恢复 riscv-tests 不等于已具备当前 SoC harness；新增明确 M-mode 启动/链接/外部 BRAM
  完成信号适配，不改原测试指令体。ma_data 要求硬件非对齐访存，控制/候选同样失败；保留
  49 PASS/1 FAIL 与 runner exit 1，不能跳过后叫全绿或称标准特权 compliance。
- L91：Ross MCP 以命令字符串做短时间重复过滤，不察觉中间 project/top 已改变；相同
  close_project/launch_simulation 可能误跳过。检查返回值中的 SKIPPED，使用语义相同的显式参数
  重发，并从真实 simulator transcript 核实本次 top 和终止 PASS，不能复用上次输出。
- L92：A+C+B 后两策略均能过既有 100MHz，但仅 +1/+7ps。端点归零与板级签核不同；
  仍缺输入/输出 delay 的 STA 不能升级为上板就绪。保存完整 timing summary 的 coverage 检查，
  不仅保存 RESULT 行。双策略胜出余量不可外推到其他源码、工具或布局。
- L93：HDL 有输入/输出寄存器不等于所有 DSP 的对应寄存器均打包。实际查询本轮 Remap：
  4个DSP均 AREG/BREG=1，仅1个PREG=1，MREG全部0；报告实际属性，不从编码意图猜映射。

## 2026-10-18 — V08 dcache fix_r1

- L81：先前诊断"AXI 握手未完成"不准确：MMIO 外设走互连本地译码、固定一拍读回，
  cpu_rdata_valid 只来自 cacheable 填充，MMIO 读根本没有 valid。修复前先读互连 RTL 核实数据通路。
- L82：给流水线插状态时，新状态里所有决策必须用捕获值；stall 是寄存输出，插入拍里
  cpu_addr_i 已是 EX 下一条指令。同理请求选通必须保持单拍——互连自己锁存 mem_re，保持高会排队伪突发。
- L83：插一拍后固定延迟要整体后移（MMIO 由 T+2 变 T+3），照搬旧的 2 拍移位会早一拍采样。
- L84：PowerShell `git show ... | Set-Content` 会加 BOM 并转码中文注释，导出的 RTL 被 Vivado
  报语法错；导出原字节用 Git Bash 重定向并以 `git hash-object` 对 blob hash 核实。
- L85：MCP 批命令里一条失败（close_design 无设计）会跳过同批其余命令，后续 lint 读的仍是旧文件；
  不能把第二次相同输出当成 HEAD 对照。每次 lint 用独立会话/目录并核对日志中的文件路径。
- L86：布局后估计 WNS=+0.221，布线后 -0.128；只认最终 post-route 报告（延续 L64）。
  局部 RTL 改动后最差路径可能整体迁移到无关模块（本次为 ISE s_reg 复位扇出），WNS/TNS/端点数需一起看。
- L87：2025.2 不支持 lint Skill 的 `linterCsvFile` 参数（Synth 8-734）；按 Skill 的 <2026.1
  分支清空该参数，用 .rpt + parse_lint_report.py 生成 CSV。

## 2026-10-18 — V08 全量扫掠与 dcache 评估

- L76：Vivado `-tclargs` 会把 `=` 也拆成独立词（`jobs=6` → `jobs` `6` 两个 argv 元素），
  正则匹配 `jobs=(\d+)` 永远不命中。参数解析必须按位置参数（`jobs 6 extra 文件`）。
  此前一轮 jobs=6 从未生效，只是默认值恰好相同。
- L77：Vivado Advanced Implementation 2025 流程在 7 系 part 上不支持：create_run
  报 12-25131 并**静默回退**标准流程（实测产物与标准流程逐位相同），VDAI 独有策略名
  （AggressiveExplore/NetDelay_medium/SSI_medium/Advanced Defaults）批处理报 not found。
  7 系上别测高级流程，直接记录不可测。
- L78：同名 module 文件并存，Vivado **不报错**、静默按文件顺序选一个综合（时序测量会
  测错对象）；iverilog 会报重复声明（全量编译必炸）。实验文件必须移出编译 glob
  （挪进子目录即可），并 grep "synthesizing module" 日志确认实际综合的文件。
- L79：33 策略全量结论：最优 ExploreWithRemap（-0.118，2025.2 自带布线后 phys_opt+
  Remap）；Auto_1/2/3 三兄弟结果完全相同（ML 指令收敛）；SLL 三兄弟/Flow_RunPhysOpt 与
  PostRoute 在单 die 上退化相同；SpreadLogic 实际 medium>low>high（单点采样 high 会误判）。
  "内置策略列表"以安装目录 Vivado/strategies/VDI2025.psg 为准（33 个）。
- L80：CPU 卡死类回归失败的定位法：TB 加层次监视器（pc/stall/state/总线信号按拍
  $display），8M 拍 TIMEOUT 也能两分钟定位到具体拍数与 PC。dcache 死锁根因=MMIO 读
  等待依赖 bus_rdata_valid_i，而请求只发 1 拍脉冲 → 握手永不完成；改等待语义时
  必须保证请求保持到握手接受，或恢复固定延迟等待。

## 2026-10-18 — V08 策略扫掠

- L70：`get_timing_paths` 不能 `-delay_type max` 与 `-setup` 同用（Vivado 12-608 直接
  error 退出整个批处理）。WNS/TNS 汇总代码放在所有 run 完成后才执行，一处 API 误用
  就白丢一轮；先在小验证脚本里跑通新 API 再进主脚本。
- L71：`launch_runs -to_step` 的上下文会跨 resume 持久化。用不同 to_step 重启同一个
  run 时，wait_on_run 后 PROGRESS 停在 <100%、STATUS="Not started <下一步>"，主进程
  报错退出。每个 run 必须始终以其策略的最终流步骤为目标启动，并行波按最终步骤分组。
- L72：杀进程残留孤儿 run 子进程 + 双主进程会互相顶掉 run（"already running"）。
  ps -W 第 4 列才是 WINPID（第 1 列是 MSYS PID，taskkill 用错列报"找不到进程"）；
  杀掉后必须数 vivado|vrs 进程为 0 再重开，启动前 archive 上次日志。
- L73：器件的 open_project 报错 "part not available" 是缺器件支持包而非 XPR 问题；
  本机 Vivado 只装了 artix7/kintex7 没有 zynq7。开始菜单 "Add Design Tools or
  Devices"（xsetup.exe 缓存在 <install>/.xinstall/<ver>/）Modify 勾 Zynq-7000 即可，
  ~1-2 GB；装完用 get_parts 验证再跑长任务。
- L74：跨机器可复现性是真实且可依赖的：同工具/part/RTL，本机重跑 Default 与
  ExplorePostRoutePhysOpt 的 WNS/TNS/失败端点与 xyq 机 V06 报告逐位一致。build_context
  必须记 host/date/git HEAD，否则跨机对比失去依据。
- L75：扫掠结论本身：10 个内置策略无一收敛 100 MHz（最优 -0.177/31 端点）；布线后
  phys_opt 是最大杠杆（Explore -0.273→-0.177），Retiming 在本设计适得其反（-0.518），
  Congestion_Spread 无效（LUT 仅 22% 无拥塞）。策略空间关闭后必须转 RTL：
  id_ex→dcache CE/DIADI 地址计算链。

## 2026-10-17 — V07 工具与证据门禁

- L67：all空集合为True；只遍历已有实现文件会把缺失/不完整快照误判为匹配。必须先核目录及完整RTL文件集合，再比内容hash；5个小型回归锁定该门禁。
- L68：Ross的整体测试基线与各Skill最低版本不同；最新版lint有旧版本解析分支，不能凭印象一概拒绝或宣称全部兼容2025.2。没有二进制/实际MCP查询时只记not_measured。
- L69：安装Markdown Skills不等于执行其流程。分别记录安装hash、Codex发现结果、实际只读审查和未执行的诊断/TDD脚本；通用方法不替代HDL/STA/实板验证。


## 2026-10-17 — V06 收尾门禁

- L65：两轮最终负WNS必须记录为100 MHz timing not met，即使hold和route status通过；31个剩余端点属于cache地址/保持使能路径。达到授权上限即停止，保留完整证据并提交已验证的阶段成果，不能用降低频率或无依据例外宣称收敛。
- L66：复核发现Vivado自动改写隔离副本blk_mem_gen XCI的enabled元数据与checksum。功能值不变，但不能声称副本XCI字节完全未变；同时保存原件/副本hash与差异，原baseline继续保持不变。


## 2026-10-16 — V06 时序续接

- L62：可变尾块掩码的64-bit减一形成7级CARRY4；改成固定字节选择后，867请求的输出与完成周期完全一致，独立Final黄金回归也通过。系统最差路径随后转移到CPU CSR/cache和hold控制，不能把剩余违例继续归因于Ascon算法。
- L63：Vivado的属性 `STEPS.POST_ROUTE_PHYS_OPT_DESIGN` 与 `launch_runs -to_step` 阶段名不同。2025.2实际接受 `{phys_opt_design (Post-Route)}`；第一次退出1发生在实现启动前，保留日志，仅继续Not started的run，不重做已完成综合。
- L64：报告中的WNS要取最终timing summary，不能拿placer/router的中间估计代替。源文件记录实际工作区字节hash，并另给LF规范化hash；原始报告与build_context禁用Git行尾转换，避免提交后证据hash漂移。

## 2026-10-16 — V06 密钥/CPU/Vivado实测

- L53：只验返回码隐藏了ISE候选明文残留；非整块decrypt还漏了移动Tag指针。新增canary/整段候选检查、错误Key/Tag/密文与多种Key、1/7/8/9/15/17-byte长度，不能只看16-byte往返。
- L54：id_stage认得custom操作数还不够。if_id提前译码未更新，旁路/load-use条件为0，本机GCC13.2实际所有ISE KAT失败。修提前译码后独立黄金和CPU测试通过，不能用队友另一编译布局的PASS替代。
- L55：多周期done一拍脉冲遇下游全流水hold可能重入。完成状态必须保持到EX推进ack；测试需覆盖完成后的继续hold与cancel，不能只让perm_start自行下降。
- L56：MMIO大数组和16-byte算法接口不是同一容量。无OUT读门禁会发布旧结果/尾部；读出失败计算Tag也不合适。START/失败撤销、长度门禁、末字屏蔽和idle ZEROIZE必须一起验证。
- L57：旧RTL runner把“新增error”写成永恒条件；统一core后故障注入还修改已删除FSM。按当前真实接口/统一core更新harness；保留初始误报。并发Vivado/CPU负载下30秒回归超时，保留timeout记录，将外部限时放宽120秒，TB自身watchdog不变。
- L58：Icarus12不支持原TB的void'($value$plusargs)，改为等价if调用；Windows stdout用GBK会在reset打断UART字符后失败，runner显式UTF-8、UART帧按reset epoch丢弃。force/release变量后须重新赋值释放复位，首个错误注入进程终止并保留失败。
- L59：Vivado以Verilog解析现有i++失败，修独立构建file_type=SystemVerilog，不改生成HDL。原归档impl_1的GeneratedRun元数据生成了空-source命令；保留日志、在副本创建新implementation run并复用已通过synth，不编辑runme/generated脚本。
- L61：重新编译后的ELF容器hash可能变化，不能据此断言目标代码回归；六个objcopy后实际加载镜像逐字节相同。保存ELF原hash与binary比对证据，不伪造容器一致。
- L60：软件volatile擦除只证明指定对象的存储动作；不证明CPU cache/寄存器/栈副本或FPGA物理抗提取。interrupt取消ISE清除state也不等于实现了任务上下文恢复，部署必须另验抢占策略。


## 2026-10-15 — 目标软件在自研 CPU 上 bring-up

- L43：git-bash 里 `python3` 指向 Microsoft Store 存根（调用 exit 49），不是真 Python；
  真实解释器是 `python`（3.11.16）。build.sh 写 `python3` 会静默产出空 hex 且 exit 49。
  脚本统一用 `python`。iverilog/vvp 是 Windows 原生二进制，`.vvp/.hex` 写相对路径即可。
- L44：AXI BRAM slave 的读数据若与 beat 计数器同一 `always` 用非阻塞寄存器，会晚一拍：
  4 拍 WRAP 变成 word0/word0/word1/word2（丢 word3），CPU 取到重复字跑飞、长时间无 UART
  输出。读数据必须组合逻辑（assign）由 rd_beat/地址寄存器直接驱动，rvalid/rlast 也组合
  输出；icache 的填线顺序是 `miss_woff + fill_cnt` 取模，即 WRAP，slave 按此送 4 拍即匹配。
- L45：全 SoC vvp 仿真约 2 万 cycles/s；Ascon 软件 + UART(115200) 输出共 ~2.2M cycles，
  单次 ~2.5 分钟。cycle 数被 UART 主导（每字节 4340 clk），加密/解密 warm 测量要跑两遍。
  `$write` 重定向到文件时被 C stdio 全缓冲，实时看进度必须 `$fflush`；`$readmemh` 文件行数
  < RAM_DEPTH 会告警，把 hex 补零到 BRAM 深度(32768)消除。用 UART 打印 DONE/FAIL 标记，
  TB 用移位寄存器 `hist=(hist<<8)|ch` 匹配 4 字节标记，避免跨字符边界漏判。
- L46：软件基线（uint64_t Ascon 在 RV32）确实需要 libgcc（`-lgcc` 跟在源文件后），
  `-nostdlib` 不自动链 libgcc；`-msmall-data-limit=0` 关闭 gp 相对寻址，crt0 仍设置 gp 无害。
  复位 PC=0x10000000 与链接 ORIGIN 必须一致，否则首条指令错位。mcycle 读 CSR 0xB00/0xB80
  （本核无 0xC00 别名），CPI 用 cpi_cnt MMIO；指令/周期测量含少量读计数开销，标注近似。

## 2026-10-15 — Ascon MMIO 加速器集成与第一次硬件优化

- L47：集成两个已验模块时，同名含义相反的信号最坑。crypto_aead 的 `mode`=0 加密/1 解密，
  ascon_aead_core/IO 契约的 `encrypt`=1 加密/0 解密，初版直连让所有加密按解密跑；空消息
  因 tag 与方向无关而"恰好"通过，非空消息全错，掩盖了极性 bug。跨模块接控制信号先逐字核对
  注释里的语义，别只看名字。用 $display 打 data/tag 实值定位，比猜快。
- L48：include 已验 .v 进模块体会把其文件级 `timescale` 带进 module 内报错；正确做法是把它
  当独立源文件编译、用 -I 指 include 路径，模块里只实例化不 include。`(a-b)[1:0]` 这种对
  括号表达式取 part-select Icarus 不认，先接中间 wire 再取 [1:0]。
- L49：iverilog 的"declaration after use"在新增 assign 引用后声明 net 时必现——把
  `assign x = wdata_32` 放到 `wire wdata_32` 声明之后即可，别和现有外设顺序反着写。
- L50：MMIO 加速器是软件→ISE 之间的第一级：软件 16840 cyc → MMIO 纯 crypto 99 cyc(~170×)、
  完整往返 544 cyc(~31×)。往返开销被寄存器写(10+ 字)+轮询+读回主导，正是下一步 ISE 要省的。

## 2026-10-15 — Ascon 置换 custom instruction (ISE)

- L51：GAS 的 RISC-V `.insn r` 操作数顺序是 `opcode,funct3,funct7,rd,rs1,rs2`（funct7 在 rd
  之前），不是直觉的 `opcode,funct3,rd,rs1,rs2`。写错报 "bad value for funct7 field"。custom
  opcode 0x0B 合法（低 2 位=0b11），GAS 会按该字段顺序校验。用 `.insn` 不用手算 `.word`，
  反汇编 objdump 看 custom 指令条数确认真编码而非 fallback。
- L52：CPU 内加多周期 custom 指令，直接复刻 divider/mult 的握手：模块用"电平 start + 内部
  只触发一次(run 标志)"，ex_stage 用 `ex_stall_req = ~done` 冻结流水线；done 为 1 周期脉冲，
  start 电平在其间自然回零。状态 load/store 指令单周期、置换指令多周期，结果经 logic_out 复用
  EXE_RES_LOGIC 通道写回。不要在置换模块里用脉冲 start（电平会每周期重锁存跑飞）。

## 2026-10-10 — 发布暂存检查

- L42：git diff --check不检查未跟踪的新日志；暂存后发现修复前日志拼接输出
  留有多余EOF空行。用固定raw JSON命令输出重新渲染，只修日志生成规则、保留
  原exit codes/FAIL文本；cached diff --check作为commit前门禁，不手改失败结果。

## 2026-10-09 — 远端Decrypt整合

- L38：Windows worktree的绝对E:/gitdir不能被WSL Git直接解析，reference Report
  取HEAD时exit128。改新worktree定位为相对路径，native/WSL都读到0a425f9。
  三方merge输入也须统一CRLF/LF，避免仅换行造成全文冲突；不据此选择RTL版本。
- L39：remote已有完整解密，不能沿用旧本地“空壳”判断覆盖远端。保留队友
  原算法/15端口与tag输出，只适配独立TB和必要认证/长度修复；接口逐项及位置连接验证。
- L40：correct和m在reset/start未清除，busy时实测X/旧认证状态；只在done检查
  比较正确会漏掉此错误。逐拍外部明文/认证门禁发现，初始化/撤销后完整KAT通过。
- L41：TB include AEAD并列production源码时重复三个module，compile exit6。
  首轮guard只包AEAD未包get_bytes仍exit2；guard扩大至整个文件后原TB/全源通过。
  保留两次真实FAIL，不排除必要模块或改掉队友include来掩盖。

## 2026-10-09 — RTL decrypt 与生产全源集收口

- L32：提交标题“解密认证失败修复”实际只改C；当前RTL decrypt仍空壳。以源码、
  端口与实际仿真为准，不沿用队友聊天/旧文档完成状态；本轮补齐并独立KAT核验。
- L33：旧AEAD已删除，runner仍强制编译旧路径，造成无关功能的真实exit1。
  before日志保留；按当前全production文件枚举门禁，而不是排除现存必要模块。
- L34：128-bit总线配5-bit length不意味着支持31 bytes。原17-byte请求实际正常
  done但数据不足；before probe保存exit1。显式拒绝17..31，并扫735种超长组合。
- L35：decrypt尾块不能直接复用encrypt XOR/pad：必须替换有效ciphertext bytes、
  保留未消费state；16-byte整块P8后仍有空padded tail。全0..16×0..16独立KAT
  覆盖这些分支，不只做Encrypt→Decrypt反向运行。
- L36：只查失败result不足以发现认证前明文泄露。TB每拍检查外部m/mlen/result，
  错tag/错明文/提前输出三个隔离源码变体都确实fatal exit1；生产源不受注入修改。
- L37：复位测试的延迟超过done可误称“abort”。首轮73cycle测试已在70cycle
  完成，改69cycle认证发布前并检查复位前busy。最终五个in-flight点与restart通过。

## 2026-10-07 — regression 提交换行收口

- L31：data/ascon 按原字节保留，Windows Path.write_text 默认 CRLF；拼接含 CRLF 的
  工具 stdout 后又产生 CRCRLF，暂存检查将报告每行判为 trailing whitespace。
  修生成器规范化 stdout 换行、显式 newline=LF，并重新生成/运行验证；不手改生成
  日志或关闭 whitespace 检查。生产 RTL 与失败门禁不变。

## 2026-10-07 — 最新 RTL 回归追加

- L24：同目录不同 .v 文件可声明重复 module；ascon_aead 与 ascon_aead_2 同时进生产
  source-set 实际 compile exit 6，isolated 新版 PASS 不能推导 whole-source PASS。
- L25：permutation 从 reset 改为 rst_n 后，旧 AEAD .reset 连接实际 elaboration exit 2。
  独立旧入口检查避免错误被 duplicate-module 诊断掩盖；未修改生产源来消除失败。
- L26：队友 TB 5组 expected 数学值已被锁定 C/Python独立证实，但原始出处未记录。
  TB 本身 wait 无 timeout、错误仅打印后正常 finish。自己的 TB 必须 watchdog/fatal，
  wrapper 同时检查退出码与失败标记，不能仅相信 ALL PASS。
- L27：5-bit length 并不等于物理接口能处理31 bytes；128-bit m/ad 只容纳16 bytes。
  不把截断/重复数据当成17-byte测试。当前无长度拒绝码，待接口规范收口。
- L28：AEAD key 未锁存，busy期间换 key 实测改变 tag；busy-start 在 permutation
  restart、在 AEAD ignore。算法 PASS 条件与协议未冻结事项分开记录，不宣称任意时序正确。
- L29：短 ciphertext 总线含有效长度外的状态，empty 后保留旧 c；比较只读 mlen bytes，
  单独记录总线观察，接收方需要明确屏蔽规则。decryption 仍 not_implemented。
- L30：Windows Git whitespace 输出包含 UTF-8 字符；默认 GBK 解码导致审计 helper
  异常。改为 bytes + UTF-8 解码并重查 checkpoint；CRLF-aware 剩余诊断均为锁定
  上游原件。不要把输出编码/CRLF 诊断当成算法失败，也不能静默抹掉来源原字节。

## 2026-10-07 — C01/C03 已观察结果

- L18：Python README 写 draft，C 保留 128A 命名，但 AEAD 参数与完整 Final KAT
  实测一致。不能凭名字或本地 C/Python 相互一致认定标准；先锁定 Final 与独立 KAT。
- L19：bad tag 返回码正确不等于失败输出安全。本地 C 实测 rc=-1、mlen=17、
  buffer 等于明文；`check_failure_contract.py` exit 1。测试 adapter 丢弃候选不修复
  C02 生产 API。接收 C02/TBD；原始失败日志保留。
- L20：并行 reference gate/validation 同时链接固定 upstream-c.so，发生一次加载
  失败，证据 `runner_race_before_fix.*`。改用每调用独立 TemporaryDirectory 后
  复验相同并行场景通过；失败不是算法 KAT mismatch。
- L21：NIST PDF urllib 首次 HTTP 403，浏览器可读；加 User-Agent 后取得原始 PDF
  与真实 SHA-256。访问失败不等于没有来源，不编造向量或 hash。
- L22：锁定原件 hash 需防 Git checkout 换行转换。仅给新增 data/reference 路径
  -text，新测试脚本 LF；不格式化 upstream KAT/source 或现有 RTL。
- L23：收尾检查器最初把 Git 的 LF→CRLF 提示和 no-index diff 的 exit 1 当成
  whitespace 失败；修正为检查实际 whitespace 输出。PDF diff 又触发文本解码错误，
  新 PDF 设 -diff，按来源/hash 审查二进制，不修改原件。这些不是 KAT 失败。

更新：2026-09-21。区分“已观察”与“待验证假设”，失败不删除，结论变化时追加证据。

| ID | 现象 / 状态 | 原因或证据 | 应对与关联任务 |
|---|---|---|---|
| L01 | 项目目标是 XC7Z020，现有 XPR 却是 Kintex（已观察） | 初始 Git HEAD 的 Part/synth/impl 均为 Kintex；后续 ZIP 已找到 XC7Z020 配置 | 以源码事实写审计，不因背景描述而改 part；B02/B03 独立恢复与核板 |
| L02 | `top` 静态展开成功，工程顶层失败（已复现） | 初始 HEAD 的 top_pl_bram 实例化 3 个未入库 IP，Icarus exit=4；XCI 现已恢复；源码文件路径存在不代表依赖齐全 | 不用空壳 IP 掩盖缺失；B02 恢复源配置/Tcl，V01 再验证功能 |
| L03 | CPI 名称容易被当成 cycle counter（已观察语义） | cpi_cnt 统计指令/停顿/flush，flush 每次加 2；真正 mcycle 在 csr_file | C04 使用 CSR 差值与 RV32 一致读取；保留计数器微测试和开销 |
| L04 | 软件目录存在但版本正确性无证据（待 C01/C03） | C api.h 是 1.3.0，Python README 链接 draft，没有锁定 final KAT 结果 | 不武断宣称旧版或合规；固定来源、逐项核对、可信 KAT 比对 |
| L05 | 文件名 ascon_round.v 不能证明 round 已完成（已观察） | 内容只定义 ror；ascon_word.v 只定义 load_bytes/store_bytes；未接 CPU/XPR | I02 从 spec 出发；不把辅助代码标成已完成 ISE |
| L06 | 参考仓库匿名访问返回 404，Git 有权读取（已观察） | API 404，git ls-remote/只读浅克隆成功 | 404 不等于仓库不存在；不索要凭据、不输出令牌，用已有 Git 权限读取结构 |
| L07 | 既有中文/空格路径与新增命名规范冲突（已观察） | 根目录历史选题指南文件名；XDC 注释非 UTF-8，defines.v 部分注释出现替换字符 | 不批量改名/转码；审计保留问题，D05/D06 制定发布映射并验证引用 |
| L08 | ignore 不会清除已跟踪 cache（Git 行为，当前有 2 个生成元数据文件） | project.wpc 和 .hw/*.lpr 已入索引 | 本轮保持不动，未来有重建证据再单独评审清理；不执行 git rm |
| L09 | PATH 检查不足以判定工具未安装（检查局限） | 只发现 Python/Icarus/Git，未全盘查 Vivado 等 | 写“PATH 未发现”，不写“机器未安装”；B02 记录实际 tool version |
| L10 | 文档验证脚本首次误报所有任务列数不符（检查脚本问题） | 检查器误设 9 列；实际规范是 ID/task 加 owner/prerequisite/deliverable/acceptance/deadline/status，共 8 列 | 修正检查器后重跑，不能按误报修改正确任务表；同时核对 P1 Skill 完成日期先于 PUF 门禁 |
| L11 | 任务日期检查发现 C02 目标编译排在 B04 固件基础之前（已修正） | C02 原内部日期 09-27、B04 为 09-28；依赖存在但日期不一致 | C02 调到 09-28，保留 C03 09-29、C04 09-30，未改变用户里程碑；依赖图与日期检查通过 |

新增条目模板：任务/日期、触发条件、完整现象、命令与日志、原因（已证实/假设）、尝试与结果、最终处理、未解决项、影响下游。不要把未运行的测试记成失败或成功。

## 原始 ZIP 到达后的证据更新（2026-09-21）

L01/L02 仅描述初始 Git HEAD；三个 IP 与原 XC7Z020 工程现已在 ZIP 找到并恢复。not_in_current_repo 不等于 not_available。

| ID | 已观察事实 | 处理 |
|---|---|---|
| L12 | 原 ZIP 与 Git 的 17 个 RTL 哈希不同，但只有 CRLF/LF 差异 | 同时给原字节哈希与规范化 diff，不武断判断哪个更新 |
| L13 | 后续 Git 提交只改 Part，初始 Git XPR 却已不同于 ZIP | 分开证明两段历史，不能以后一段推断更早的转换 |
| L14 | 原 XPR 引用生成 incremental DCP | 独立恢复副本最小移除 checkpoint；保持源路径，不导入整个 runs/gen |
| L15 | FreeRTOS app/COE 齐全不等于 kernel 源齐全；bootloader 只有 COE | 精确列缺口，不下载任意最新版冒充原版本，不擅自替换初始化 |
| L16 | 旧 add TB 使用 u_ram/u_cpu_core，AXI top 已不同；部分 env 链接扁平化为文本 | 保存原件，后续显式适配/测试；HEX 存在不是 ISA 回归通过 |
| L17 | 历史 WNS 为正但有未设 IO delay，资源报告有阶段差异 | 报告时注明时钟/覆盖和 placed/synthesis 阶段，不冒充 Fmax/本轮实测 |

## foundation 收口更新

L08 的“保留两个跟踪生成元数据”是此前策略；本轮按用户“无 generated build cache”要求完成清理。ignore 不会取消跟踪，需显式移出索引。git mv 会暂存 rename，故收口后不能继续报告“索引为空”；普通 git diff --stat 也不包含 staged rename 或 untracked 资产，应同时检查 cached diff 和状态。

收尾发现：默认 cached diff 检查把原 Kintex XPR/XDC 的 CRLF 判作行尾空白。保持源字节不动，仅在 `.gitattributes` 对这两个文件声明 cr-at-eol，同时保留 blank-at-eol、blank-at-eof、space-before-tab 检查；复核原哈希和检查结果。

## 2026-10-07 — C02 认证失败输出契约

- 返回 -1 只证明认证拒绝，不能证明 buffer 不含明文。原 C 先写候选明文再验 tag，
  bad tag 仍返回 mlen=17 和原明文。原 KAT adapter 丢弃失败输出，掩盖 raw API 问题。
  新门禁直接检查整个已知输出区域，不能按返回 mlen 截断后误报擦除成功。
- 同一个扩展门禁实测修复前 8,926 FAIL / exit 1、修复后 0 FAIL / exit 0。
  保存 source hash、真实失败与 raw byte 示例；两侧 A5 canary 验证擦除边界，
  加密 aggregate SHA256 前后相同。禁止为修 production 改 locked reference/KAT。
- 短输入以前先 return -1，未写 mlen，调用者旧长度可残留。入口归零 mlen 后再
  检查 clen<16；没有明文候选时不擦 buffer，也不发生 clen-16 下溢。
- NIST 算法 fail、SUPERCOP C 返回 -1、项目失败擦除是不同层的约束；不把项目
  增强契约声称为上游强制规则。完整 16-byte XOR/OR comparison 保留，失败用
  volatile stores 避免优化丢弃；host disassembly 不是全平台 timing proof。
- 从 main 开始的未提交工作依赖另一 feature 时，先用 stash 保存全部状态，再让
  修复分支直接基于依赖分支，只恢复本任务增量；整文件恢复 project_log/readme
  会丢掉依赖分支记录，应采用增量合并并用三点 diff 审计。
- 本轮 PowerShell→wslpath 原 Windows 路径传参丢反斜杠，脚本路径变为 /sim/...，
  exit 2、没有测试运行。使用仓库根目录下 WSL 相对路径成功，不写死本机盘符。

## 2026-10-21 — 后端复制/floorplan 战役的六条教训

- **复制成功 ≠ 时序变好。** 全局 `MAX_FANOUT 128/256` + `-force_replication_on_nets`
  确实把 9650/3989/1280/661/457 pin 的网络全部拆到 256 pin 以下（可逐网络核对
  `route_high_fanout.rpt`），但 WNS 从锚点 +0.016 掉到 −0.074/−0.188/−0.295。
  复制前必须先看**这个锥自己的最差裕量**：本例是 +0.9~+2.8 ns，它根本不在失败路径上。
- **只给属性不触发复制。** `MAX_FANOUT` + `EQUIVALENT_REGISTER_REMOVAL=NO` 但不加
  `-force_replication_on_nets` 时，结果与无属性臂**逐位相同**；2025.2 的复制入口只有
  `phys_opt_design -force_replication_on_nets <get_nets 结果>`。
  加 `-force_replication_on_nets` 时不要试图用它去拆最大的那几个锥（实测拆不动），
  它的有效用法是**只喂失败端点的 CE 锥**。
- **`DATAPATH_NET_DELAY` 是整条路径的累计走线**，不是一条网络。本例 10~11 级逻辑、
  net 7.1~7.5 ns，等于每跳约 0.7 ns 的分布式线长；因此"找到那条坏网络复制一下"不成立，
  只能靠更短的跳（布局，上限 ±0.1 ns）或更少的跳（RTL）或更长的周期。
- **floorplan 生效与否要数溢出，不能看 bbox。** `add_cells_to_pblock` 只给层次单元是
  有效的（pb_cpu 覆盖 10404 个 leaf），但 place 之后的 `phys_opt_design` 会插入副本并做
  critical-cell 优化，把 2.6% 单元放到区间外；模块 bbox 越界 20 行并不等于约束没生效。
- **"布局疏松"在这颗器件上是伪需求。** 22% LUT 占用下 Vivado 默认布局已经散开；
  `place_design` 没有 `-place_density`，pblock 的 `PLACE_DENSITY` 在 2025.2 直接报
  `Netlist 29-177 property does not exist`（脚本必须 catch，否则整臂崩）；
  `AltSpreadLogic_medium/low` 实测 +0.002 / −0.027。
- **先建生产指令锚点，再谈差值。** 裸 `place_design` 的对照臂是 −0.102，而同一网表的
  生产策略是 +0.007/+0.016；把 place Explore + phys_opt Explore + prout
  ExploreWithHoldFix 的臂作为锚点（实测 +0.016）之后，其余 30 多个臂的差值才有意义。
  另外必须有一个**跨波次的重复臂**证明流程确定性（本例 3 组逐位相同），
  否则 0.03 ns 级的排序只是在读布局随机性。

- **WHS 为正时，所有布线后 hold 修复指令都是空操作。** `phys_opt_design -hold_fix` /
  `-aggressive_hold_fix` / `ExploreWithHoldFix` / `ExploreWithAggressiveHoldFix` /
  `-clock_opt` 五个臂打在同一个已布线网表上，WNS/WHS/LUT **一个数都没变**
  （+0.138/+0.017/不变）——help 原文写的是只修 "high hold violators"。
  想把正余量抬高只能改最小延时或偏斜：要么把 hold 关键的那对寄存器在物理上拉开
  （pblock 子区），要么整体放松布局，两者都用 setup 换 hold。
  本例 35 臂 `corr(WNS,WHS) = −0.516`，WHS ≥ 0.05 的 7 个臂 WNS 全部 ≤ −0.102，
  说明"项门限式"的 hold 指标在这版网表上无法与 setup 同时满足，应改口径而不是硬扫。

- **hold 余量由"一整群短路径"决定，不是一条。** 把最差 hold 的那对寄存器用 pblock
  拉开后，最差路径只是换人（`s_out→s4` 0.381 ns → `p8_inst/s_reg` 0.389 ns →
  `nonce_r` 0.375 ns …），WHS 只从 +0.017 抬到 +0.032，WNS 却从 +0.138 掉到 −0.110
  （73 个失败端点），交换率约 1:16。判断一个 hold 指标值不值得追：先数
  `report_timing -hold` 里有多少条 < 目标值的路径、逻辑级数是 0 还是 1；
  如果是一群 0~1 级路径，除了改 RTL 或降频没有解。


## 2026-10-24 — 100 MHz 提余量的九条教训（F/C/80 MHz 实测）

- **降频不能"改约束重跑实现"。** 12.5 ns 重跑只有 +0.483 ns，而同一张按 10 ns 布线的网表
  重算 12.5 ns 是 +2.34 ns；差 1.9 ns 全是 P&R 按松约束松手（route 7.6→9.17 ns）。
  正确做法：实现保持 10 ns 过度约束，只把 MMCM 输出降到 80 MHz。
- **RTL 改动的验收要看路径族条数，不能只看 WNS。** F 把目标族 8858→60 条、WNS 却 −0.079；
  只看 WNS 会把"生效但被新墙顶掉"误判成"无效"。
- **方案文档要带"当前 RTL 是否已是该形态"一列。** 计划里的"路线 A"（旁路决策提前到 ID 段末寄存）
  在 `cpu_core.v:373-386` 早就这么写了，照计划再做一遍是空跑。
- **后端配方不可迁移。** campaign 的 +0.138 靠复制最差端点的 CE 锥；F 之后墙移到 D 端
  （valid_way/lru），同一配方只剩 −0.226，C 之后也只有 +0.017。配方要跟着"当前最差端点类型"重选。
- **`MAX_FANOUT` 只在综合/opt 阶段生效。** 在 post-opt checkpoint 上设属性不会复制寄存器，
  必须 `phys_opt_design -force_replication_on_nets`；否则得到"两臂逐位相同"的假结果。
  另：post-route 不支持 `-force_replication_on_nets`（2025.2 直接报错并让该步失败）。
- **改 BRAM 写地址会打碎 RAM 推断。** 读写同址才能推成单口模板；写地址一换成 buffer 地址就
  报 `Synth 8-2914 Unsupported RAM template`。正确形态是 SDP：读口独立、写口与 fill 共用。
- **"0 周期"要连硬件 MMIO 一起验。** F 的 MMIO 全卸载 670→675 拍，C 仍 670 拍；
  同为"写路径打一拍"，区别在 F 把延迟放进了软件可见的回合。
- **dcache 这类模块最划算的回归是逐拍差分**：同一份确定性激励 + 逐拍信号 dump + diff +
  末尾存储器校验和，比写定向断言省一半时间，还能抓到"看着对但时序变了"。
- **复用别处脚本先改相对层数。** 脚本按自身位置算 root，`backend_opt_20261021/` 的脚本是
  `../..`，搬到 `build/local/tests_20261024/` 后要多一层，否则会在仓库里生成 `build/build/`。

- **`include` 一个"同时也是源文件"的 .v 必须配 include guard。** 队友给 `ascon_mmio.v` 加了
  `` `include "ascon_aead_core.v" ``，而三者都没有 guard → 模块重复定义、整库 elaboration 失败。
  判据：被 include 的文件若同时出现在源文件列表里，文件头必须是 `` `ifndef X_V/`define X_V ... `endif ``；
  同目录已经有 4 个文件这么写（`crypto_aead.v` 等），新加 include 时照抄即可。

- **要拆长锥，先看锥里哪一项是 pc 衍生、哪一项是寄存器输出。** D 只把 `inter_accept_ready`
  里唯一 pc 衍生的 `!icache_stall` 挪进一个触发器，就把"起点为 pc 的 1389 条路径"一次清零
  （worst +0.057 → +1.491），而资源只多 1 个 FF。判据：与门的输入里，哪些来自寄存器/FSM 状态
  （快），哪些来自异步 RAM/加法器（慢）；只把慢的那几项打拍，其余保持当拍，语义变化最小。
- **"CP 侧没墙了"不等于"整机没墙了"。** D 之后最差路径换成了 Ascon 核心内部
  `p12_in_reg` 的 1 级逻辑 / 9.29 ns 走线（94% route），说明下一刀要么拆 p12/ad_shf，
  要么动 floorplan；继续在 CPU 上做结构改动已经没有边际收益。
- **改动落在没有测试覆盖的逻辑上时，要先把"为什么等价于空操作"写清楚。** D 动的是中断接受
  判决，而全部固件都没开中断（`interrupt_en=0` → `inter_req` 恒 0），所以现有 6 场景
  cycles 一字不变；风险窗口是"以后启用中断"，必须在启用前补定向 TB，而不是等它出问题。

- **扇出复制必须在放置之后做，不能在 RTL 里写 `max_fanout`。** 同一根 fo=628 的网
  （`u_crypto_aead/state[3]`，单根走线 9.29 ns）：放置后 `phys_opt_design
  -force_replication_on_nets` 让 WNS 从 +0.003 抬到 **+0.130**；而 RTL 里加
  `(* max_fanout = 64 *)` 由综合期复制，结果 **−0.008、1 个失败端点**。
  原因：放置后复制是把负载分给已经摆好的位置（本地化），综合期复制只是多出几个 FF，
  还要跟整张网表一起被重新摆放。
- **复制要外科手术，不要扫全局。** 只复制 1 根（+0.130）优于复制 24 根宽网（+0.124）；
  复制 24 根多出 33 个副本、多扰动布局。选点是关键：必须用**布线后** DCP 的最差路径
  反推网名，post-opt 视图里最差路径完全不是同一批（只有逻辑延迟）。
- **防折叠用 `EQUIVALENT_REGISTER_REMOVAL NO`，不要用 `DONT_TOUCH`。**
  前者只禁止把等价寄存器合并，后者还会冻结放置，副本就搬不到负载旁边。

- **在一个"本身就很差"的流程上验证出来的收益，必须回生产流程再验一次才能当结论。**
  单根 `state[3]` 复制在自定义流程（对照 +0.003）上是 +0.130，接进生产策略后是 +0.039
  （对照 +0.087）——同一改动、同一根网（fo 628→25），结论完全相反。
  差别在于：对照越差，越有"被复制补回来"的空间；生产策略本来就把这根网放得可接受。
- **在 run 流程里插步骤用 `STEPS.<STEP>.TCL.PRE/POST` 属性，不要自己手写 directive 序列。**
  这样 opt/place/phys_opt/route 的 directive 与策略完全一致，结果才和生产基线可比
  （`prod_ctl` 逐位复现 `d_100` 就是这条的验收方式）。
- **写入 run 钩子文件的脚本必须是纯 ASCII。** Vivado 生成/读取 TCL.PRE/POST 用平台编码，
  带中文注释的 heredoc 会把大括号串写坏（表现为 `can't read "cand": no such variable`）。
- **按名字选网时，注意综合会改寄存器名、但保留网名。** `state[3]` 这根网的驱动 FF 被改名成
  `FSM_sequential_state_reg[3]`；只按单元名匹配会选出 0 个候选而静默空转（钩子照跑，什么都不复制）。

- **"复制有效"不能跨流程迁移。** 同一根 fo=628 的 `state[3]`：自建流程（`opt Explore / place Default /
  phys_opt Aggressive / route Aggressive`，同流程对照 `rep_ctl` **+0.003**）复制后 **+0.130**；
  生产流程（`Performance_ExploreWithRemap` + 放置后钩子，对照 `pr_ctl` **+0.087**）复制后 **+0.039**。
  判据：先看两条流程**各自对照臂**差多少（这里 0.084），再判断"这份收益"属于流程还是属于复制。
  换流程重测的成本远小于被一个跨流程数字误导的成本。

- **"物理上发生了"不等于"时序上有效"。** `pr_rep2_state` 里副本 51 → 60、`state[3]` 从高扇出清单
  消失（复制确实做了），WNS 仍从 +0.087 掉到 +0.039：拆掉目标墙的同时把 CPU 侧
  `ex_mem/ex_rd_data_o_reg[11] → if_id/pred_target_o_reg[13]/CE`（11 级 / logic 3.183）顶上来。
  所以"验证复制发生了"（数副本、看 fo）与"验证复制有用"（看 WNS）是两件事，都要做。

- **一个副本都没生成，也是一条有效结论。** `sel_*` 四根网（fo 172/141/172/140）设
  `MAX_FANOUT 128` + `phys_opt_design -force_replication_on_nets` 后副本仍 51、FF 仍 17187 ——
  工具按**物理收益**决定是否复制，而不是按扇出阈值。只看 WNS 会把这次实验读成"复制有效/无效"，
  实际是"复制根本没发生"。

- **同目标两路独立实现给出逐位相同的结果，才敢下"有害"这种结论。**
  `pr_rep2_state`（本站，复制 1 个网名）与 `prod_rep`（协作方，复制 2 个别名）脚本与钩子写法都不同，
  却给出相同 WNS +0.039、相同失败端点、相同 `dp/logic/net/levels`。单臂永远不能证明"复制有害"，
  必须配**同流程对照臂**。

- **`TCL.POST` 钩子文件要整段写，别让花括号提前闭合。** 第一版 `run_prod_rep.tcl` 在第 66 行就闭合了
  `puts $fh {...}`，于是第 67~83 行在**父脚本**里执行，`prod_ctl` / `prod_rep` 两个臂在启动 1 秒内
  报 `can't read "cand": no such variable` 双退。改成「模板文件 + `string map` 实例化」最稳。

- **选点要匹配"网名"，不是"驱动单元名"。** 本项目那根网叫 `u_crypto_aead/state[3]`，驱动它的单元
  被综合重编码成 `u_crypto_aead/FSM_sequential_state_reg[3]`；只匹配单元名 → `candidates=0`，
  臂白跑而且结果看起来完全正常（+0.087、51 副本，与对照一字不差）。

- **给 `vivado.bat` 的路径一律用 `C:/…`，不要用 MSYS 的 `/c/…`。** 否则 `-log /c/...` 报
  `ERROR: [Common 17-1257] Failed to create directory 'C'`，日志与 journal 全丢，事后无法复盘。

- **`report_timing` 元素表里 net 行没有 edge 字母。** 格式是
  `net (fo=627, routed)   9.290   7.254   <name>`（cell 行才有 `r`/`f`）。要求 edge 必现的正则会
  把整条走线丢掉，只剩单元 —— 症状是"hops 全是 0~1"。

- **"单独都无效、组合才有效"必须靠 2×2 才能发现。** 时序优化的三个变体（设属性 / 多一次 `phys_opt_design` /
  两者叠加）：属性单独 **+0.087**（= 对照）、裸 pass 单独 **+0.087**（= 对照）、叠加 **+0.184**（两次逐位相同）。
  如果只跑其中一个，会分别得出"没用"和"是复制的功劳"两个错误结论 —— 而实际副本数为 0。
  凡是"某一步看起来有效"，先问"它的每一个组成部分单独做有没有效"。

- **`phys_opt_design` 不带参数时可能什么都不做。** 同一阶段裸跑 `phys_opt_design`，WNS 与对照逐位相同
  （+0.087），且 hook 里前后两次 `get_timing_paths` 都是 +0.247；而带上
  `-force_replication_on_nets <nets>` 就会真的跑一轮物理优化。判据：不要假设"调用一次 = 优化一轮"，
  要在 hook 里前后各打一次 WNS，并把副本数一起记下来。


## 2026-10-25 — 旧Cache TB与真实中断覆盖（V01，owner TBD）

- 固定“接受miss下一拍总线一定有效”的断言在MISS_CAPTURE拆拍后会误报。先用git历史证明miss流水前旧TB PASS、Store Buffer前后同4 FAIL，再用逐拍差分和独立CPU数据/事务scoreboard交叉确认；不能仅延后采样或删除断言就标功能通过。原失败证据保留。
- 差分相同仍可能两版共错，需独立内存reference；错误回填和丢写两类注入必须触发FAIL。本轮578次读/671次写、全部回填与最终内存均检查，并非只看仿真正常finish。
- CPU内部`id_pc`是ID阶段，EX实际PC为`ex_pc`。初稿中断触发误用ID PC造成DIV场景没触发；改测试观察点并对照ELF opcode，不能据此误判生产CPU坏了。
- mret在EX时，前面的handler写寄存器可能尚未退休；mret边沿检查CSR/PC，handler结果应在退休之后检查。初稿过早读count=0导致测试FAIL，修正检查边界后仍严格验证count=1与CSR读回。
- timer pending与branch flush重叠时，icache redirect可使inter_slow_ok_q=0，合法行为是延后到可重放指令。测试应严格检查pending/flush重叠、guard阻止非法接受以及最终真实handler/mret，而不是强求branch那一拍接受。调试日志留在build/local/preboard_followup_20261025_01，最终源码无DEBUG临时打印。
- 只驱动irq或看到程序继续不算中断验证。必须核对接受次数、实际被中断指令、mepc/mcause/mstatus、flush、mret恢复及返回后的架构结果；禁timer、坏mret、绕过guard反例均应红。
- 本轮所有负向RTL变体只存在build/local，生产cpu_core/dcache/SoC/PUF/Skill未改；不把六个RV32 BFM场景外推为SoC全总线或板级门禁完成。


## 2026-10-25 — 把TB_STALE真正收口为当前回归PASS（V01，owner TBD）

- 仅给旧FAIL分类不能代替修复测试入口。保留修改前日志/源码，把旧TB的固定拍数假设换为有界事务事件，仍检查全部原expected、次数、方向和数据；当前生产RTL的正常测试必须exit0。
- 固定多等一拍仍会固化微架构。独立预期队列配合8拍请求界限、原30拍完成界限，可以同时发现迟到、缺失、重复与错误请求；posedge NBA后采样、negedge驱动避免调度竞争。
- Reset只中止半条fill不够，还要证明复位前已有效的line失效，否则可能漏掉valid/tag残留；本轮两类reset场景均通过。
- 历史失败要冻结TB与RTL为同一版本；不能将旧固定时序断言长期绑定当前生产源，再把它的FAIL永久豁免。当前正常路径、历史复现和故障注入分别记录actual退出码与gate。
- 放宽时序检查后需用错回填/缺读/重复/错地址/错data/错mask/缺写实错证明仍会红；本轮7种修订TB反例全部exit1，独立reference/差分也PASS。全回归实际15 PASS后才收口，不用定向PASS代替未跑整套结果。
## 2026-10-26 — 首次上板踩坑（Vivado 2025.2 手工建工程）

- **2025.2 的 Add Sources 向导没有 IP 选项**（只剩 constraints/design/simulation）。“加现成 .xci”靠把文件拖进 Sources 面板，或用 Add or create design sources → Add Files 直接选 .xci；IP Catalog 里是**新建** IP，不是加现成的。
- **XCI 里的 Coe_File 是相对路径**（`../../imports/bin_file/xxx.coe`，相对 XCI 自身目录）。新建工程时必须把 xci 放到 `srcs/sources_1/ip/<ip>/` 并把 COE 放到 `srcs/sources_1/imports/bin_file/`，否则 IP 生成报 COE 找不到。别写绝对路径（会把本机路径写进被跟踪的 .xci）。
- **被 `include` 的文件不能单独改文件类型**：`ascon_word.v` 用了 SV 的 `i++`，但它被 `crypto_aead.v` `include`（后者又被 `ascon_aead_2.v` include），Vivado 用**包含者的类型**解析整段文本 → 只把 `ascon_word.v` 设成 SystemVerilog 无效。要么整链都设 SV，要么全工程 .v 统一按 SV 解析（`defines.v` 保持 Verilog Header）。
- **换 COE 会触发 blk_mem_gen 的 OOC 综合**，Sources 面板出现 “Waiting to update...” 属正常；此时**综合报告里 BRAM 显示 0 RAMB36 / 5 RAMB18**（IP 是黑盒），实现合并后才变成 32 RAMB36 + 5 RAMB18。别据此判断 BRAM 没进来。
- **Reports 面板里灰色的 Timing Summary 是“该步骤未生成”的占位**：`init_design`、`power_opt_design` 默认不产 timing summary，永远点不开；只有 opt/place/route 后的条目带日期和大小才可双击。
- **策略的不对称配置是有意的**：综合保持 `Vivado Synthesis Defaults`、实现用 `Performance_ExploreWithRemap` —— 所有历史时序数字都是这个组合测的，单独改综合策略就让 WNS 失去可比性。

## 2026-10-27 — PYNQ 通道：先查"能不能接到 CPU"，再谈接线（owner TBD）

- **"PS 直写共享 BRAM 当邮箱"在这套 SoC 上一定读到旧数据**：`dcache.v:52` 只把
  `addr[31:20]==0x100` 判为 cacheable，而全设计没有 d-cache 失效/清洗指令（只有 `fence.i`
  刷 icache）。所以共享 buffer 只要落在内存窗口内，PS 改了 BRAM、CPU 仍可能命中旧行；
  `volatile`/`fence` 都不能修。要么给 CPU 一条 uncached 的新 MMIO 窗口（改
  `bus_interconnect.v`），要么别用共享 BRAM。
- **RV32 的外设空间没有通向 PL 的出口**：`bus_interconnect` 把 clint/uart/gpio/cpi/ascon
  全部内部译码，外部只有一条 AXI 主口且只承载 `0x100x_xxxx` 内存路径。任何"新增 PS 可见
  寄存器窗口"的方案都得动那个文件 —— 先确认这点，再决定是加窗口还是复用已有外设。
- **复用已有 UART 当 PS↔PL 通道是被低估的选项**：它是 uncached MMIO、已在板上跑通、
  固件驱动不用改；代价只是带宽（6.25 Mbaud 下每字节 1.6 µs）。当"PS 端到端时间"和
  "CPU cycles"分开报时，带宽不污染加速比。
- **PUF 的 `key_hw_sel` 会静默改掉 HW 模式的密钥来源**：`soc_top.v` 里它只在
  `key_valid` 后置 1、无参数可关；一旦锁存，`ascon_mmio` 丢弃 CPU 写的 KEY。
  任何要"用调用方 key 复现官方 KAT"的工程必须钉住 keys 之前的源集，否则 KAT 会莫名失败。
  用 `git rev-parse <rev>:<file>` 对比 `git hash-object <file>` 可以精确证明"只有哪几个文件不同"
  （注意 `core.autocrlf=true` 时直接比 sha256 会全部假阳性）。
- **RTL 模块拖进 BD 不会自动变成 AXI 从口**：必须给 `s_axi_*` 端口加
  `(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)` 这类属性，
  否则 BD 里是一堆散线、Connection Automation 接不上 `M_AXI_GP0`。时钟/复位同理
  （`signal:clock` / `signal:reset` + `ASSOCIATED_BUSIF`）。
- **没跑 Vivado 也能抓接线错**：用 `iverilog -g2012 -t null` 加一份 Xilinx IP 空壳
  （`sim/pynq/ip_stubs.v`）可以把整棵树 elaborate 一遍，端口名/位宽错误当场暴露。
  它只能证明"接得上"，不能替代功能仿真，更不是综合证据 —— 写报告时必须这么界定。
- **证据索引里的合并哈希必须写清口径**：`docs/freeze_checkpoint_20261027.md` 的
  `a323df37…` 用 hex 串联/原始字节/sha256sum 行格式/文件名+哈希等 6 种常见口径都复现不出来。
  哈希没有口径等于没有证据；以后记录合并哈希时把"排序方式、是否含文件名、分隔符"一起写。

## 2026-10-27 — PUF 复用与"忙时丢请求"

- **上层软件无法区分"请求被丢弃"和"操作没做完"**：`if (start && !busy)` 这种写法在忙时静默丢请求，
  表现为上层超时，排查方向完全错。总线外设的 START 要么排队，要么给出 busy/ack 拒绝位，不能吞。
- **跨时钟域的 PUF 采样器必须有看门狗**：RO 计数器由各自的振荡器驱动，跨域快照/计数在真实器件上
  可能停滞；没有超时兜底时 `done` 永不到来，软件只能挂到自己的超时。看门狗要把"一定给出 done"
  当成接口契约，而不是等到有 bug 才补。
- **仿真连做 6 次不复现 ≠ 硬件没问题**：要把"忙时再来一个请求""窗口中途打断"这类时序组合写进 TB，
  并用 force 制造卡死来验证看门狗真的能救回来，否则测试只是覆盖了顺利路径。


## 2026-10-27 — done 必须确认归属；纯 BRAM 镜像不能热更新

- **抓 `done` 前必须确认它是"自己这一次"的**：器件忙时发 START（即使已排队），随后读到的
  `done=1` 可能是上一次操作的粘滞位，软件会把中途状态当结果——板上表现为
  `enrolled=0 quality=0` 同时 `busy=1 done=1`。正确写法是：先等 `busy=0`，再 CLEAR，
  再 START，并确认 `busy` 确实抬起后才等 `done`。
- **`busy=1 done=1` 同时出现是"读到别人家的 done"的指纹**，不是硬件坏了；看到这个组合先查软件时序。
- **`write_mem_info` 只支持带处理器或 XPM 的实现**：纯 `blk_mem_gen` 工程无法生成 `.mmi`，
  也就不能 `updatemem` 只换 BRAM 内容；改固件必须重跑完整实现流程，排期时要留出这 20+ 分钟。
- **打印中间状态要带时间锚点**：`STATUS pre-*` 这类"操作前"打印如果不先等 idle，
  读到的全是残值，日志看起来像失败，实际是测量方法错。

## 2026-10-28 — PYNQ骨架到真实链路，owner TBD

- 模型把服务帧SIMULATED与selftest位沿用错误，全部模型PASS仍不能证明真实标志语义；显式测试real service flags（bit0模拟，bit1自检）才发现错误。
- 固件UART RX非空实际是bit1，骨架误用bit3（满）。真实CPU联合仿真显示epoch发出20B后仍卡svc_getc；修bit1后36请求与半帧复位验证通过。不要仅凭注释实现寄存器。
- 空消息/整块后余数为0也必须padding；复制ISE时else if(len>0)漏掉0会破坏KAT。
- UART两线无远端反压；满RX不能留valid重复压入，必须置溢出并丢弃新字节，由主机判错和reset恢复。
- Windows checkout把新shell脚本变CRLF，WSL set -euo pipefail报错；新增eol=lf约束。默认Python采用GBK读UTF8文件会报错，脚本显式UTF8。
- Vivado module reference顶层不接受SystemVerilog类型；仅把含i++的辅助ascon_word.v标为SV。import_ip会把旧COE注册成工程依赖，即使CONFIG.Coe_File已更换也须移除旧依赖，再生成BRAM。
- 新main包含PUF，但旧CPU runner没列keys/primitive模型；原main回归编译失败，增加显式--pynq-p0源集，绝不默默替换main测试口径。初稿全局替换错误将此参数传给固件/targeted脚本，保留失败并修调用点后整套重跑PASS。
