# 开发记录

## 2026-10-31 — PYNQ demo Notebook 全量 KAT 说明同步（owner TBD）

- 保留用户已设置的 `RUN_FULL_KAT = True` 和板端执行输出，将第 1 节由“6 组 smoke”
  更新为三模式各 289 组的容量内全量 KAT，并同步末尾的快速回归/超容量边界说明。
- 未改 `board_demo.run()`、benchmark、release、RTL、固件或接口；Notebook JSON、
  `test_board_benchmark` 5 项离线测试和 `git diff --check` 均通过。
## 2026-10-31 — gen 输出自包含（owner TBD）

- 修复独立下载复核中发现的生成骨架 ImportError；64 passed、16/16，仓库外复现通过。

## 2026-10-31 — D04 演示视频脚本（owner TBD）

- 读取当前状态、PYNQ validation、warm benchmark/error-gate JSON、项目简介与实现
  报告，新增 `report/demo_video_script.md`，将视频组织为“需求→架构→三实现→
  实板 KAT→性能→错误恢复→边界”的可录制时间轴。
- 脚本锁定最新 PYNQ run 的性能表和 `mcycle` 口径，排除历史 PL-only 数字；
  增加 3 分钟剪法、PUF 独立原型选段和录前/录后事实核验清单。
- 同步 D04 为 `in_progress`、`report/readme.md` 和 actual progress；尚未录制
  实机视频，未改 RTL/固件/release，未 commit/push。

## 2026-10-31 — S04 可配置报告与 S05 文档（owner TBD）

- report schema + 非 Ascon DMA 回环示例；63 单元测试、16/16 变异；skill/readme.md S05 内容补齐。未改 loader/regmap/DMA/golden、RTL 与 release。

- 2026-10-31：最新 L3 session `l3_20261031_063709` 四段与汇总 PASS。DMA 全部
  正常长度/奇长度/连续/超限/golden/recover 检查通过；59 PASS、1 N/A、0 FAIL。
  S01–S03 收口，S04/S05 仍待非 Ascon report 示例及证据/独立复现。
## 2026-10-31 — 协作记录入库与未跟踪文件清理（owner TBD）

- 核实 llm_collab 的统计（21/13/76/2635），省略 1 条与工程无关的提示后在本地 commit `cc39c9d`；报告 2.5.4 同步修改并重新构建，结果 PASS。
- 新增 Ross 使用心得文档；按引用扫描删除 95 个未跟踪的冗余路径（191.7 MB），误删的 puf_min OOC 证据已从 work 目录重新收集。

## 2026-10-31 — Skill L3 用 AXI DMA 回环 overlay（owner TBD）

- 新建独立 Vivado 工程：PS7 GP0 控制、HP0 内存、simple 模式 AXI DMA、MM2S→S2MM 回环含 TLAST、FCLK0 100 MHz（板卡 PLL 修正）、HP0 窗口 1 GiB；门禁通过并生成同名 bit/hwh 与同次实现的 manifest。
- 后续 L3 session `l3_20261031_063709` 已用该工件完成实板回环 PASS；DMA 吞吐和
  `short_output`/`missing_tlast` 故障场景仍未测。
- `l3_30` 默认指向该 candidate，并交叉核对 manifest/HWH/运行时基址、DMA 配置、
  manifest 哈希和 HP0 缓冲窗口；`l3_00` 纳入 DMA 工件指纹。离线 artifact/HWH/
  DMA-config 与 Notebook AST 通过，板上待新 session。

- 2026-10-31：最新 L3 session `l3_20261031_030131` 完成 preflight、Ascon A/B 和
  GPIO C，三段 PASS。all-output `leds_gpio` 的 DATA 0/7/5/2 写回与恢复通过。
  汇总仅因 DMA D 缺回环工件 `NOT_RUN` 而 FAIL。
- 2026-10-31：L3 新 session 的 preflight 与 Ascon A/B 实板 PASS。GPIO 首次失败后
  根据 `20_non_ascon_gpio.json` 确认 `leds_gpio` 为 `C_ALL_OUTPUTS=1`，TRI 不适用；
  已改为 all-output 直接验证 DATA、mixed/input-only 分别处理，待板上复测。DMA 仍
  `not_run`。

## 2026-10-30 ~ 10-31 — pynq-overlay-workflow Skill L2 实验 + 留出任务（owner TBD）

- L1 复核全绿（47 passed；变异 13/13 killed）；判分器 good/naive 区分度复核（T1/T3 6/6 vs 3/6、T2 6/6 vs 0/6、
  T4 8/8 vs 0/8）。
- 冒烟发现模型不主动加载 Skill，按用户决定给三组提示词追加同一句中性提示（`make_trials.py:PROMPT_SUFFIX`），
  并在 `skill/ab_eval_pynq/README.md` 记录该预注册修订；二次冒烟确认 canary 出现、判分 6/6。
- 两批共 60 次 `opencode run`（T1/T2/T3/T4 × 3 组 × 5 次，deepseek/deepseek-flash，seed 20261030，禁 shell），
  60/60 exit=0；另加 T1×placebo 复跑 5 次。`grade.py` 生成 `results*.csv`，`stats.py` 出置换检验与 Cliff's δ：
  主指标 T1–T3（n=15/组）`with` 1.000 vs `without` 0.833（p=0.0425，δ=+0.33），`with` vs `placebo` p=0.2248；
  T4 次指标 `with` 1.000 vs `placebo` 0.825（p=0.0079）；T1–T4 探索性合并 `with` vs `without` p=0.0014。
- 修复仪器并重判：`fake_pynq` 补 `Bitstream`（构造不下载、`download()` 计数）、`Overlay` 继承 `Bitstream`
  （`hash`/`timestamp`/`downloaded`）、`hierarchy_dict`（嵌套 `ip`/`hierarchies`）与 `device`；新增
  `harness/tests/test_fake_pynq_api.py`。重判旧批次仅 `t1_overlay/placebo/rep04` 0.000→1.000。
- 留出任务：`t5_gpio` 因与 Skill 自带 `examples/axi_gpio.contract.json` 撞车而作废，改用 `t5_bram`；
  假 PYNQ 新增 `Bram`（小端 32 位字、预填、`span` 路由），新增 2 个 BRAM API 用例，自检 good 7/7 / naive 3/7；
  正式 15 次（`run3`）`with` 1.000 vs `without`/`placebo` 0.800，p=1.0，**未复现差异**。
- 归档：`skill/ab_eval_pynq/results/l2_20261030_deepseek-flash/`（`results_all.csv`、`results_holdout_t5.csv`、
  `stats_*.txt`、三份 `design*.json`）、`skill/ab_eval_pynq/holdout/t5_bram_design.md`。

## 2026-10-31 — L3 Notebook 配置项注释（owner TBD）

- 将 L2 最终结果接入 L3：预检增加关键脚本/依赖/L2 归档逐文件哈希与 Skill 脚本树
  聚合哈希；DMA 增加 odd-length、back-to-back、over-max 门禁；汇总强制读取
  `l2_evidence`，并同步 L2 为 simulated、不可宣称因果/泛化的文档边界。验证为
  5 个 Notebook JSON/AST、Skill 工具 47 passed、假 PYNQ API 7 passed。
- 按用户明确要求把五个 Notebook 的仓库定位改为固定路径
  `/home/xilinx/jupyter_notebooks/amd_fpga_2026`，删除 `ASCON_REPO`/cwd 搜索，
  并同步 README；换路径时必须统一修改五个文件中的 `repo` 常量。
- 修复从 `test_board/` 子目录启动时仓库探测只向上找两级的缺陷；改为遍历全部父目录，
  并在找不到时输出搜索清单。子目录解析测试、五项 Notebook JSON/AST 通过。
- 给五个上板 Notebook 的 `None`、空列表、缺失工件状态和可选环境变量增加行内说明，
  区分自动运行时字段、确需人工填写的路径与 UNSAFE/部分结果开关。
- 同步用户改名后的 `l3_20_gpio.ipynb`、`l3_30_dma.ipynb` 文档引用；JSON 证据文件名
  保持不变。JSON/AST 与 diff whitespace 检查通过，板级仍为 `not_run`。

## 2026-10-30 — PYNQ Skill L3 上板 Notebook（owner TBD）

- 按人工 L3、无 with/without 对照的边界新增五个 Notebook：预检、Ascon release、
  BaseOverlay LED GPIO、独立 AXI DMA 回环和汇总；结果直接写入 `data/skill/`。
- Notebook 对真实工件、manifest、Skill SHA、服务身份、`simulated=false` 和 claim level
  做机器断言；DMA 工件缺失时 fail closed，汇总不允许把只有部分阶段的运行写成完整 L3。
- 离线验证：5 个 Notebook JSON/AST 通过；既有 Skill 单测 47/47、变异 13/13。
  PYNQ、L2 和真实板级结果均未执行，状态保持 `not_run`。

## 2026-10-30 — pynq_puf3 完整容量内 KAT 实板复验（提交 7544921，owner TBD）

- Notebook 切换 `FULL_KAT=True` 并保存 `data/pynq_puf3/notebook_20261030_144328/`：
  PUF3 在真实板上 SW/HW/ISE 各 289/289 KAT 与坏 Tag 拒绝，30 次 mcycle benchmark，
  PUF enroll/reconstruct/HWKEY 流程通过，status PASS、exit code 0。
- 结果仍限定为单次上电功能证据；跨电源周期、温度/BER/熵/唯一性和 RO timing signoff
  未测。PYNQ 2.7 的 150 MHz 派生显示不作为频率证据，采用 SLCR 99.999999 MHz
  与 mcycle 99.9971 MHz。

## 2026-10-30 — pynq_puf3 板测协议问题修复（owner TBD）

- 板测时钟已正确（99.999999 MHz）；失败为固件 banner 文本 "Y01K" 被主机当作 PUF 帧。Notebook 解码器改为只在 PUF 命令待响应时、且帧头匹配时识别 Y01K；离线复现与修复验证 8/8，板上待复测。

## 2026-10-30 — pynq_puf3 FCLK0 修正（owner TBD）

- 板测显示 93.75 MHz；定位为 hwh 的 IO PLL 假设（1600 MHz）与启动镜像（1000 MHz）不符、PYNQ 读数又按 50 MHz 参考计算，真实 62.5 MHz。固定 IOPLL FBDIV 30 + 分频 10×1 重建；板测加入 SLCR 推算与 mcycle 实测双重时钟门禁。板测 NOT_RUN。

## 2026-10-30 — pynq_puf3 三模式 + PUF 单一 overlay（owner TBD）

- 分析得出 PUF overlay 无法运行三模式的根因是 RTL 自动锁定硬件密钥；在独立目录完成变体 RTL、pynq_svc_puf 固件、PS 驱动、Icarus cosim（含自动锁定反例）、模型测试、Vivado 实现与打包。第一次实现时序失败后改策略收敛到 +0.104 ns；板测 NOT_RUN。
- 同日按 5eb64a5 迁移时序签核（ro_clk 约束已在用，迁入 ro_corner_sta.tcl、打包检查与签核分块），bit 未变；RO 计数器仍未签核。

## 2026-10-18 — V10 授权清理与复验（owner TBD，数据已验、留存暂缓）

- 用户确认清除废弃文件/可再生缓存，并进一步选择最终双策略RPT保留、其他旧报告删除。
- 删除8个废弃根目录/状态文件、10个确认停止的缓存目录、9套旧报告与中间结果，合计564文件。
- 保留原始恢复归档、生产源/输入、最终RPT/DCP、当前JSON/TXT依赖；留逐文件hash清单。
- 增加3个历史汇总器缺报告时的防误覆盖提示与 verify_cleanup.py 真实复验器。
- 新label cleanup_v10 的8项CPU、生命周期、5单元和50项ISA已重跑：镜像/周期/源码及231文件hash一致，ISA既有ma_data失败不变。
- 复验exit 1仅因6个已删路径被并行会话恢复/重新导出；原FAIL证据保留。用户确认“暂时保留并行产物”，未再次删除。
- 清理manifest记录数据PASS/留存DEFERRED；V10标blocked等待并行工作完成，不重复已完成回归、不修改其他会话产物。

## 2026-10-18 — 并行任务卡 B：P0 收口文档（owner TBD）

- 交付 I08 收口 docs/ascon_ppa_comparison.md（资源演进/周期加速比/收敛历程三表，
  全部数字可追溯）；冻结检查点 docs/freeze_checkpoint_20261018.md（收敛版本构成、
  一键复验命令链、改动门禁、余量脆弱性声明）。
- 任务看板更新：I08 todo→done（证据指向 PPA 文档，标注芯片级/板上边界）、
  V02 todo→done（ACB 套件证据）；头部日期更新。
- 并行任务卡 A（src/pynq/ host 层代码）由另一 AI 执行，本卡未碰其目录。

## 2026-10-18 — V09 A→C→B（owner TBD，完成本轮范围）

- 按用户顺序修改 ascon_ise/mult/ex_stage/dcache；新增 RV32I/M SoC 适配器与乘法 hold/cancel 测试。
- Ross MCP 在独立目录打开 fix_r1 routed DCP 副本，导出 156 端点明细，核实 A=93、C=48。
- XSim 2025.2：multiplier 1259 例、ISE 1502 检查 PASS；Icarus A/C units 5/5 PASS。
- 50 项恢复 RV32I/M：控制、A+C、最终 A+C+B 均 49/50，通过同一适配器保留 ma_data 失败。
- 最终 8 项整机回归、MMIO/ISE 生命周期与 5 项单元均 PASS；mcycle 回到 HEAD 值，汇总脚本 exit 0。
- RTL lint：EX 4 条（其中 1 条既有 critical），dcache 2 条；额外乘法警告仅未使用扩展乘积最高位。
- 新双策略入口 build/build_timing_acb.tcl，fresh 副本/同综合快照、不覆盖旧报告；功能门禁后通过 Ross 启动。
- 双策略完成 exit 0：PostRoute +0.001/0/0、Remap +0.007/0/0（WNS/TNS/setup失败），
  hold/pulse/route error 均0。baseline 93/48/11/4 类别在最终全部归零。
- Remap DCP 只读核实 4 个乘法 DSP 均 AREG/BREG=1，1个PREG=1；没有泛称所有DSP输出都注册打包。
- build/summarize_timing_acb.py 交叉核对最终报告/CSV/XDC/40源hash，exit 0；总结及接口/看板已同步。
- 仅既有100MHz约束通过、余量1–7ps；IO delay/电气/DRC/实板未验收。未commit/push。

## 2026-10-18 — V08 dcache fix_r1（owner TBD）

- Ross vivado-mcp-server 2026.9.1 登记到 OpenCode 全局配置（stdio，Vivado 2025.2），实测可用。
- 修改 src/rtl/dcache.v（MMIO 固定延迟、MISS_CAPTURE 用寄存标志、单拍请求选通）；
  build/screen_dcache_donttouch.sh 增加 `wt`；build/build_dcache_pipe.tcl 增加可选 tag 参数，
  旧 MISS_CAPTURE 报告保留不删。
- 功能门禁全 PASS；HEAD 周期对照在临时 detached worktree 中运行后已移除。
- 时序 fix_r1：-0.128/-11.213/156，未达 4.4 门禁；报告 build/reports/dcache_pipe_20261018_fix_r1/。
- 未 commit/push。

## 2026-10-18 — V08 全量扫掠收尾（owner TBD）

- 四批扫掠全部 exit 0：33 个标准流程策略全量完成，另 2 个高级流程回退重复已剔除；
  最优 Performance_ExploreWithRemap -0.118/-1.008/22 端点。分析与排名已写入
  docs/ascon_strategy_sweep.md、actual_progress、lessons（L76-L80）、skill。
- dcache 两版独立评估完成（时序 -0.055/-0.078，功能均死锁），修复方案与英文清单
  交付另一个 AI；同名 module 实验文件已归位 dcache_experiments/。
- 未 commit/push；工作区含 dcache.v 修改、实验文件目录、文档与脚本，待审查。

## 2026-10-18 — dcache 流水线版（另一个 AI）独立评估

- 背景：另一个 AI 修改 dcache.v（MISS_CAPTURE 态流水化 miss→bus 请求路径）并遗留两个
  同名实验文件在 src/rtl（dcache_timing_optimized.v / dcache_aggressive_fsm.v 均声明
  module dcache）。已移入 src/rtl/dcache_experiments/（保留不删）。
- 首测误用：Vivado 静默选用后序文件 dcache_timing_optimized.v 综合（同名模块不报错），
  第一次"新 RTL"时序 -0.078 实为 DONT_TOUCH 版。清理重测后 dcache.v 真实值
  WNS=-0.055/TNS=-1.122/40 端点（策略 Performance_ExplorePostRoutePhysOpt，报告
  build/reports/dcache_pipe_20261018/）。最差路径=rs1_o_reg→captured_addr_reg/CE。
- 功能回归（原生 xpack 工具链，runner 增加 Windows 原生前缀分支）：HEAD 原版 PASS；
  dcache.v 与 DONT_TOUCH 版均 TIMEOUT（8M 拍无 DONE、0 UART 字符）。
- 调试 TB（build/local/strategy_sweep_log/tb_ascon_sw_dbg.v）定位死锁：t=275 起
  pc=100083f0、state=IDLE、stall=1 恒高、无总线活动。根因：MMIO 读等待改写为
  bus_rdata_valid_i 清除，而 bus_mmio_re_r 仅 1 拍脉冲，AXI 握手不完成→rdata_valid
  永不到来→mmio_read_wait_r 永 1→CPU 无限 stall。两版同病（均重写了 mmio 等待逻辑）。
- 结论：两版时序有改善（-0.055/-0.078 vs -0.177）但功能不可用；修复方向=MMIO 读
  请求保持到握手完成或恢复固定延迟等待。证据：data/ascon/results/key_lifecycle/
  sw_dcache_pipe2.json（FAIL）、dcache_dt_screen.log、dcache_head_screen.log（PASS 对照）。

## 2026-10-18 — V08 策略扫掠暂停（用户占用 Vivado）

- 首轮 10 策略全部完成留档（最优 Performance_ExplorePostRoutePhysOpt -0.177）。
- 补充扫掠（17 个 + 10 个 = 全部剩余内置策略）进行中与用户自己的 Ross/Vivado 会话
  在同一隔离工程上发生双主进程冲突：波 1 三个 SSI 策略布线完成但报告丢失（需重跑），
  其余待跑。用户要求暂停，待其用完 Vivado 后继续。
- 续跑命令：build/sweep_strategy_timing.tcl -tclargs "resume jobs 6 extra build/strategies_extra.txt"
  及第二批 "extra build/strategies_extra2.txt"（含 6 个标准流程 + 4 个高级流程策略）。
- 2025.2 内置策略全集已从 Vivado/strategies/VDI2025.psg + VDAI2025.psg 核对：33 + 4 = 37 个。
- 02:22 续跑再次被顶死：另一个 AI 的 Vivado 会话仍在打开本隔离工程（02:21-02:26 新会话启动、
  工程 run 目录 impl_1/synth_1/explore_postroute 被外部改动、vivado-proxy 新握手）。用户未响应
  协调询问；暂停等待用户处理，不再自动重试。TSV 仍 10 行、首轮数据完好。

## 2026-10-18 — V08 实现策略扫掠（owner TBD）

- 用户授权全量 10 策略扫掠、提速并行与数据记录分析；未改 RTL/XDC/XCI/COE，未 commit/push。
- 诊断并解决本机 Vivado 缺 Zynq-7000 器件库（用户补装）；写 sweep/aggregate 脚本，
  多次中断续跑（缺器件、API 误用、波次 to_step 冲突、双主进程），最终 10/10 完成。
- 结果最优 Performance_ExplorePostRoutePhysOpt -0.177/-2.968/31，与本机 Default 重跑
  及 xyq 机 V06 逐位一致；结论见 docs/ascon_strategy_sweep.md，数据见
  data/ascon/results/strategy_sweep_20261017/。
- 沉淀 skill vivado-strategy-sweep；更新实际进度与经验（L70-L75）。

## 2026-10-17 — V07 工具评估（owner TBD）

- V06检查点2b48a8a已commit/push，PR4为draft；未合并main。
- 读取AMD Ross官方文档与固定提交；本机原生Windows/Codex CLI/Vivado2025.2核验，下载会话阻塞留证。
- 通过OpenAI Skill Installer仅安装四个Matt Pocock Skills；逐文件核hash，Codex本地stdio发现检查通过。
- code-review规范/需求两路只读审查；修复证据快照完整性门禁，保留3个red失败及5个green通过日志。
- 以pr Skill模板整理PR证据/合并风险；无第三轮实现、Strategy Sweep、原工程改写或真实烧录。


## 2026-10-17 — V06 收尾（owner TBD）

- 恢复现有worktree及staged/unstaged成果；原队友dirty工作区保留，未启动第三轮实现。
- 对最终源码、六组CPU输入、所有报告和XDC/XCI/COE逐项核hash，复用一致的PASS证据。
- 完整记录第二轮WNS=-0.177ns/TNS=-2.968ns及31个setup失败端点，保持100 MHz timing not met。
- 更新最终时序/密钥文档、实际进度、看板和经验；按用户授权准备功能分支commit/push，不合并main。


## 2026-10-10 — V05/C03 发布审查与用户授权

- 在隔离worktree核分支/HEAD/status，fetch确认origin/main仍0a425f9；索引初始为空，
  远程功能分支尚未建立；采用已有Git author/committer配置，不猜身份。
- 检查30个已验成果文件与证据/source hashes、完整Encrypt实例连接、文件大小、
  生成缓存/临时物/敏感信息、diff --check；补充publication_preflight.json及审查记录。
- 用户授权按指定消息commit并push功能分支、创建中文PR；合并main仍须用户确认。
  发布完成状态/commit SHA/PR URL以Git历史和本次交付为准，本段为提交前记录。

## 2026-10-09 — 最新main上的Ascon整合（V05/C03，owner TBD）

- fetch确认0a425f9；仓库外备份全部28dirty与相关资产，共89文件，逐项核验。
  从origin/main新建feat/ascon-decrypt-kat-integration隔离worktree，不触碰旧工作区。
- 比较两版RTL/接口/调用及三处remote变化；非RTL文件以7139a80三方整合，
  生产AEAD只移植必要修复，保留远端decrypt全部算法路径与15端口。
- Decrypt初始化/撤销候选和correct、失败不发布、超长拒绝；Encrypt新增error；
  guard完整覆盖AEAD/get_bytes，保留队友原TB include；P8/P12原样保留。
- TB改用tag_in/correct并验证computed tag，加位置连接逐拍兼容检查；runner增加
  原接口逐项门禁；保留全部独立KAT/负向/reset/超长/fault测试，重新准备与执行。
- 环境gitdir/换行setup、远端X状态/重复module、首轮guard漏包的失败各自留证，
  不伪装PASS。source最终回归/故障/软件全部exit0，0功能FAIL；计数见actual_progress。
- 更新README/接口/RTL与sim/data说明、看板、最新报告和三日志；原28dirty/备份
  全部哈希复核，CPU/Vivado/PYNQ未改。未暂存/commit/push/PR/merge。

## 2026-10-09 — V05/C03/I04 standalone RTL 功能验证（owner TBD）

- 检查git status/log与实际生产源码；当前branch cleanup/remove-legacy-ascon-aead，
  HEAD7139a80。保留初始两份dirty回归报告，不新建/切换分支，不commit/push。
- 读入口/标准/接口/构建规范及生产AEAD/置换、独立TB和锁定reference。
  核实decrypt空壳与C修复提交范围，先保留当前回归的stale-source FAIL。
- 补齐现有AEAD文件内decrypt，只有认证成功发布明文；补加解密容量拒绝。
  新独立decrypt TB复用原784-bit数据布局；prepare扩展289官方+11补充输入；
  runner枚举完整当前源码，全root编译并执行全源加解密，不编译已删除旧文件。
- 实测复现原17-byte请求被当成功处理；保存before source/probe hashes与命令。
  新测试覆盖735超长组合、每拍认证输出保护、首末及逐bit篡改、重复/reset。
  修正一次复位覆盖点：73cycles已完成，改69cycles并断言复位前仍busy。
- WSL Python3.12.3/GCC13.3准备：reference gate12,936/0；native Python3.14.3/
  Icarus12.0 RTL门禁exit0。host全套重跑28,661/0，host harness5/5。
  RTL四个故障注入实际触发非零退出，harness4/4通过。
- 更新README、接口、sim/data/RTL说明、看板、actual_progress/lessons；新增当前
  验证审计，历史审计注明时间边界。最终工作区供用户审查；接收B02/B04/V01→C04/I01/I02。

## 2026-10-07 — independent RTL regression 提交收口

- 用户授权提交现有回归，分支 feat/ascon-kat-validation，不 push/merge。
- 核对全部 11 个待提交文件：原集合 190,057 bytes，最大文件约86 KB，无重复大文件；
  pycache 与本地 vvp/so 均 ignored，无编译物待提交。
- 正式脚本/复现说明无机器路径依赖，报告的绝对路径属于实际执行证据。
  当前源码与结果记录 hash、reference/license lock、生产路径未改检查均通过。
- 按指定消息 `test(ascon): add independent RTL regression` 创建提交；不把当前
  full-source FAIL 或 decrypt 未实现改写为成功。提交后检查 git status 与最近5 commit。
- 暂存后 whitespace 检查发现 Windows 默认报告 CRLF/日志重复 CR；修 runner 源配置
  为显式 LF，重新运行同一 RTL regression，生成新证据，不手改生成日志来掩盖失败。

## 2026-10-07 — checkpoint、rebase 与最新 Ascon RTL regression

- 按用户授权审计大小/缓存/可移植性/许可。正式 WSL 示例动态定位路径；race 原日志
  无损 gzip，保留 hash 和 ignored 本地备份。构建库、vvp、pycache 未提交。
- checkpoint cba792c；fetch 确认 origin/main 13d954f；无冲突 rebase 后 a1d19dd。
  未 push/merge main；未改生产 RTL、CPU、Vivado、队友 TB。
- 新 prepare_rtl_vectors.py 用锁定 C/Python gate 后独立核验5 peer expected；新增
  自己的 round/P8/P12 与 AEAD TB、run_rtl_regression.py，全源集也实际编译。
- reference gate 12,936 PASS；permutation 与 isolated encryption PASS；旧 reset
  接口 compile exit 2、full duplicate module compile exit 6，runner exit 1，完整日志保留。
- 接口观察：AEAD busy-start ignore；permutation busy-start restart；busy 改 key 会改 tag；
  <=16-byte 接口无17-byte支持、decrypt空壳、输出无效位/空数据陈旧值不屏蔽。
- 更新独立 RTL 审计、sim readme、actual_progress/lessons。接收 RTL owner/TBD→I04。
  新工作停在可审查未提交状态，C02/C03 全项目门槛仍未关闭。

## 2026-10-07 — C01/C03 Final 基准、固定 KAT 与独立验证入口

- owner TBD；用户授权同步 clean main、审计及新增 KAT；禁止改现有 RTL、CPU/Vivado、
  看板，不 commit/push。初始无分叉，ff-only 同步 13 commits，HEAD 8c8634f，
  分支 feat/ascon-kat-validation。
- 读取 AGENTS/README/overview/rules/看板/接口/工作流程/日志、C AEAD/XOF、Python
  AEAD/生成器、五个 Ascon RTL，以及 NIST Final 与设计者维护的锁定参考。
- 独立下载标准/参考源/许可/完整上游 KAT；新增 data/ascon、sim/ascon。扩展输出
  来自经过完整 KAT gate 的锁定 C，Python 第二检查；限定 .gitattributes 防换行转换。
- WSL Python 3.12.3/GCC 13.3：gate 12,936 PASS；全套 28,661 PASS；harness 5 PASS；
  冻结数据重生成 byte-identical。C failure-output 实际 FAIL exit 1、一次 runner race
  原日志保留，race 已修复复验。
- 文档记录参数/来源/许可/hash/RTL 只读问题/实际命令/局限；更新 actual_progress、
  lessons，看板按用户要求仅给建议。现有生产接口不变。
- 接收 C02/C03/TBD 先收口失败明文发布与 target 构建，再 C04→I01/I02。未做现有
  RTL/CPU/板级/Vivado/PYNQ/PUF 验证；最终 git diff HEAD 自审，不提交。

## 2026-09-21 — 第一阶段仓库审计与协作骨架

- 范围：按用户要求完成仓库组织、审计、协作规则、任务和时间计划；原工程保持原位；不开展大规模 Ascon 实现，不 commit/push。
- 初始状态：main，HEAD `e35d42f9638e9f56e7af6df492f424173922fac1`，工作区干净，62 个跟踪文件，README 空，无 AGENTS/.gitignore。
- 工作分支：`docs/repository-foundation`，仅创建分支指针，未创建提交。
- 调研：公共网页/API 未能访问参考仓库，现有 Git 权限可只读获取；参考提交 `9c34288aa040fb926eefa8603c85f0d19522e849`。采用协作结构，未复制小车内容/人员/规则/脚本。
- 审计：记录 Kintex/目标 Zynq 差异，IP/TB/固件/脚本缺口；明确 mcycle 与 CPI 事件的不同；标记已有 Ascon 的来源/KAT 未验证及 RTL 辅助模块现状。
- 实施：新增 docs/tasks/project_log 及 sim/build/data/skill/report；复用 src/board/ascon；补 README、AGENTS 和忽略策略；所有任务 owner TBD，P2 gated。
- 验证：Icarus `top` exit=0；`top_pl_bram` exit=4（3 个 IP 缺失）。文档链接、任务字段/依赖、日期、ignore 保留/排除样例、原文件哈希核对见 repository_audit。
- 输出：用户可审查的未提交工作区；当前事实见 actual_progress，遇到的限制见 lessons_learned。

后续记录格式：日期、任务号、授权范围、有效方案、改动、验证证据、接收任务、未完成项。不要用开发计划替代实际结果。

## 2026-09-21 — CICC1000023 原始 XC7Z020 baseline 恢复

- 授权：选择审计/恢复用户给定 ZIP；不整包覆盖、不 commit/push，保留既有工作区。归档脚本只作资料，不自动执行指令。
- 审计：2855 文件 CRC/哈希，真实 XPR/.srcs/3 XCI/XDC/COE、RTL、bitstream/报告、全部 ELF 头部；区分源码/输入/编译产物/生成结果。
- 比较：31 共有 RTL 中 14 字节同、17 只换行；2 repo-only Ascon helper。Git 后续 Part-only 提交不代表 ZIP→初始 Git 也只有 Part 差异；XDC 解码后的非空行一致。
- 恢复：579 个精选资产约 2.43 MB；独立真实 baseline、legacy 副本、固件/验证源、小输入和历史报告。XPR 仅去生成 DCP 引用并关闭自动增量；原 src/rtl、ascon、板级工程不改。
- 验证：579 哈希、XPR/COE 相对路径；原名工作副本 564 文件；Icarus top 与 bypass/regfile 两模块 PASS，原始日志在 build/metadata。
- 更正：Git HEAD 缺失 not_in_current_repo，ZIP 已有 available_in_archive；不能再写资料不存在。FreeRTOS kernel/bootloader 源与旧 harness 不匹配明确记录。
- 交接：B02 Vivado 2025.2 重建真实 baseline，B03 实物核板，B04 依赖与加载、V01 完整回归；本轮无 Vivado/固件/板级验收。

- 收尾补充：恢复资产使用限定路径 `.gitattributes -text` 保持 checkout 字节；原 61 文件保护、路径/哈希/文档链接、脚本拒绝覆盖检查通过，Git 索引为空。

## 2026-09-21 — repository foundation 收口

- 用户授权：不新增功能、不跑 Ascon、不改 RTL；比较 Kintex 副本，执行 git mv 归并，核对资产/引用与 Git 状态，不 commit/push。
- 比较：共同 XPR/XDC 哈希完全一致；原目录独有两个生成元数据，副本独有说明文档。没有共同工程文件内容冲突。
- 操作：自动审批拦截最初的组合清理命令且未执行；改为先备份未跟踪副本到仓库外，再单独 git mv。Git rm 因刚暂存 rename 拒绝直接删除元数据，改用 git rm --cached 并精确删除工作文件。说明文档保留并更新，原 XPR/XDC 字节不变。
- 清理：旧入口消失，两项 .cache/.hw 生成元数据移出索引和工作区；579 个恢复资产全部保留，未运行编译或功能测试。
- 分类与状态：增加 foundation_category 及统计，B01 done，B02 改为重建验证真实 baseline / in_progress，B03 part confirmed / physical board pending。
- 验证与现状：精确证据见 repository_foundation_closeout；git mv 与清理已暂存，其他新增资产保持未暂存；无 commit/push。

## 2026-09-21 — 按用户授权拆分本地提交

- 保留 fe66fd868e95c74b75abe262c1fe56d23558d991，不 reset/amend/重写；其范围只有 Kintex rename 与两项生成元数据删除。
- A 类 584 文件：577 个尚未提交的恢复资产，加 7 个 recovery 清单/差异/来源数据。B 类 39 文件：新编写的文档、协作结构、恢复校验脚本和本轮验证元数据。
- 65 个 whitespace 问题文件均属于 A（63 个历史原件、2 个恢复差异证据）；共 12636 条。B 类问题文件为 0，无需 trim 或格式化。
- 579 工作区资产哈希一致；577 个 ZIP 资产暂存字节与 manifest 一致。两份 legacy 文件在既有 Git 历史中为 LF、工作区为 CRLF；仅对这两个 B 类 .gitattributes 规则声明 text/eol=crlf，以保留既有 Git blob 和原工作区哈希。历史源文件字节不动。
- recovery commit：fc9147785cc4490b1673a0b86e16f337f256f122，584 文件、83139 行新增。本记录随独立 foundation 提交保存，B 类单独要求 git diff --cached --check 为 exit 0。
- 本轮不 push、不 merge，不运行 Vivado/Ascon/PUF/PYNQ/ISE，不修改任何历史 RTL/XPR/XDC。

## 2026-10-07 — C02 authentication-failure software repair

- owner TBD；分支 `fix/ascon-c-auth-failure`，直接基线为已推送的验证分支
  `c34728558469f0d4e4068730801dea59e0ca2100`。开始时误从 main 13d954f 建分支，
  完成测试后用可恢复 stash 保存全部工作，将分支基线调整到 c347285，再只恢复
  C02 增量；没有复制提交上一分支资产，没有改写远端。
- 审计 NIST Final §4.1.2 Algorithm 4 与 SUPERCOP API 2020.08.01：算法输出 fail，
  C API 无效 ciphertext 返回 -1；项目额外要求失败不得返回可使用明文。
- 原复现 exit 1：rc=-1、mlen=17、buffer=原明文。扩展 raw 测试覆盖完整固定
  AEAD corpus、PT=0/1/8/16/17、tag/CT 首尾翻转、短输入与 canary；修复前
  15,039 PASS / 8,926 FAIL / exit 1。失败记录保留，未调整 golden。
- 唯一 production 修改：aead.c decrypt 保存输出起点和已知明文长度，初始化 mlen=0，
  完整 tag 比较后失败用 volatile byte stores 清除候选区域、mlen=0、return -1。
  不改 encryption/成功路径算法，不改 reference/Python/RTL/Vivado。
- 修复后 raw 23,965 PASS、完整四 backend host 28,661 PASS、harness 5 tests PASS，
  均 exit 0；修改前 full host 同样 28,661 PASS；加密输出 aggregate SHA256 一致。
  GCC 13.3.0 -O2 objdump 实际确认完整 16-byte comparison 和 wipe stores 留存。
- 报告及完整日志在 data/ascon/results；重复长日志/大 before-fix JSON lossless gzip。
  首次 wslpath 传参丢反斜杠，exit 2、未执行测试；改用 WSL 当前目录相对路径成功。
- C02 host 安全子项完成，target build/B04 未验仍 in_progress；C03 软件 PASS，
  不自动 done、不改任务看板；下一接收 target port/KAT/C04。RTL blocker 留给 TBD owner。

## 2026-10-16 — V06 key lifecycle review (owner TBD)

- 检查原dirty worktree，fetch origin --prune，从c37ecae创建E:/amd_fpga_2026_key_lifecycle / fix/ascon-key-lifecycle；未触碰队友文件。
- 阅读现行实现、标准和历史记录，保存before测试，修复证实的MMIO/ISE/CPU生命周期与认证问题；补齐独立黄金、CPU/RTL/故障注入测试。
- Vivado2025.2独立复制真实baseline，生成三个IP，综合及实现尝试；源配置修复与失败均保留。无板级引脚修改或烧录。
- 更新实际进度、接口、任务状态、上板清单；最终检查、commit/push结果见本轮validation_summary及交付报告。

## 2026-10-18 — 并行任务卡 A：PYNQ host 无板子集（owner TBD）

- 仅新增 src/pynq/ascon_host_api.py、golden_checker.py、jupyter_demo.ipynb、readme.md、test_host_api.py；
  本条为共享开发日志末尾追加，保留已有未提交改动；未改 RTL/固件/reference/docs/tasks，未启动 Vivado、未 commit/push。
- Y03/Y04 无板子集交付：可替换 Backend、锁定 Python reference 模拟加解密、具体长度/认证/超时/总线异常、
  官方 KAT 逐字节校验、篡改拒绝与故障注入、notebook 顺序展示；不伪造 PynqBackend 或 Y01 寄存器。
- CPython 3.11.16 实跑：python src/pynq/golden_checker.py → PASS 1089 / FAIL 0、篡改拒绝4290、exit 0；
  python src/pynq/test_host_api.py → 17 tests OK、exit 0，含六类向量×三mode、notebook全部代码单元顺序执行。
  测试实际启动 --inject tag/ciphertext 两子进程，各 PASS1088/FAIL1、byte=0、exit1（预期故障被捕获）。
- 核实任务卡 ascon/python 实为 ascon/pyascon；锁定上游参考位于 sim/ascon/reference/pyascon。
  周期 JSON 仅有元数据，实际17353/670/2496在同名.log；仅16B无AD加密返回 historical simulated样本，其他未测返回None。
- 未测：C重新编译、Jupyter前端、真实总线/PYNQ/板卡/overlay/板级cycles；同步模拟不能抢占，超时仅丢弃迟到结果。
  下一接收Y01/Y02→Y03/Y04板级部分，owner TBD；按任务卡唯一共享文件限制，主线维护者后续同步实际进度/看板。

## 2026-10-18 — Y01 板型无关协议草案与模拟通信（owner TBD）

- 用户授权先完成不绑定板型部分；沿用并行边界，只改src/pynq并在本日志末尾追加。
  新增mailbox_protocol.md/.py、mailbox_backend.py、test_mailbox.py；扩展golden_checker CLI及readme，既有Host API不变。
- draft v1定义逻辑能力握手、48-byte小端请求/响应、epoch/request_id、单槽busy/complete/ACK、长度/认证错误、
  64-bit周期有效标记、deadline及显式reset恢复。消息内偏移不是MMIO地址；未创建寄存器映射/假PynqBackend。
- MemoryTransport使用锁定Python reference，正常cycles=None；sw/hw/ise均仅模拟，不宣称硬件多块、真实总线或cache验证。
- CPython3.11.16实跑：test_mailbox.py 24/24、test_host_api.py 17/17（含notebook）均exit0；
  golden_checker.py --backend mailbox --mode sw/hw/ise三条各PASS1089/FAIL0、篡改拒绝4290、exit0。
  mailbox --inject tag/ciphertext各PASS1088/FAIL1、首差byte0、exit1（预期）；包导入与无板加解密示例exit0。
- 覆盖旧/错响应、重复ID、busy覆盖拒绝、ACK匹配/失败、tag失败无明文、版本/容量协商、
  超时隔离与显式恢复、reset失败/epoch不变、总线故障、64-bit codec；异常后不自动重试crypto。
- 未测：真实AXI/PS/PL、cache/屏障、固件加载/物理清零/复位、overlay及实板周期；同步reference不能抢占。
  协议未冻结、Y01整项/Y02未验收；未启动Vivado、未改RTL/固件/docs/tasks，未commit/push。
  下一接收：草案审查→B03板型/image→Y01物理映射/固件/cache冻结→Y02，owner TBD；主线维护者同步实际进度/看板。

## 2026-10-21 — 后端放置/复制战役（夜间自动化，33→35 臂）

- 新增 `build/backend_opt_20261021/`：`run_variant.tcl`（单臂全流程：属性→opt→pblock→place→
  定向复制→phys_opt→route→phys_opt→报告）、`run_wave.sh`（并行波次，每臂独占 cwd 与报告目录，
  已有 result.txt 的臂拒绝重跑）、`floorplan.py`（依赖驱动 pblock）、`dep_analysis.py`、
  `summarize.py`、`fanout_compare.py`、`probe_levers/probe_layout/probe_pblock/probe_pblock_hold/
  probe_variant_layout/probe_wall/probe_dcp.tcl`。
- 起点 `acb_remap/top_pl_bram_opt.dcp`（生产 +0.007 的 post-opt 快照，带 clk/clk_out1、零黑盒）；
  `synth_1/*.dcp` 不可用（无约束 + 三个 IP 是黑盒，opt 会 DRC INBB-3 失败）。
- 8 个波次共 35 臂：全局复制（128/256/512/1024、nofrn/noeq 对照）、定向 CE 复制（20/60/120/200/300）、
  三套 floorplan（fp2/fp3/fpc）、疏松（AltSpreadLogic medium/low）、放置与布线 cost model
  （ExtraNetDelay_high、HigherDelayCost、NoTimingRelaxation）、生产指令锚点 prod_place、重复对照 ctl_dup。
- 最好一档 `pl_ndh_crit200_ntr`：WNS +0.138 / TNS 0 / 失败 0 / WHS +0.017 / LUT 13468 / 0 布线错误，
  重复臂逐位相同；时序墙分布 <0.2 ns 从锚点 127 条降到 7 条、<0.3 ns 从 278 降到 44。
- 证据：`build/reports/backend_opt_20261021/`（每臂 result.txt、route_timing/paths/utilization/
  route_status/high_fanout、summary.md、wall_distribution.txt）、`build/local/backend_opt_20261021/`
  （各臂 routed DCP + 日志，git 忽略）。文档 `docs/backend_placement_campaign.md`。
- 未改 `src/rtl`/`board/`/baseline 工程；未 commit。未跑功能回归与上板（not_measured）。

## 2026-10-24 — next.html 路线实测（F / R）

- 新目录 `build/local/tests_20261024/`：`run_variantF.tcl`（一次跑完 synth→impl→reports→dcp，
  参数 = tag/rtl_tree/输入时钟周期/策略）、`check_F.sh`（6 场景 iverilog 等价）、
  `probe_classes.tcl`（DCP → slack<2.0 路径 CSV）、`classify.py`（按"起点寄存器 + 终点模块"配对）。
- 关键教训 1：**降频不能靠"改约束重跑实现"**。12.5 ns 重跑给 +0.483，而同一网表 12.5 ns 重算是
  +2.34；差 1.9 ns 是 P&R 按松约束松手的物理质量差。过度约束（实现 10 ns + MMCM 80 MHz）才拿得到。
- 关键教训 2：**RTL 改动的收益要用"路径族条数"验收，不能只看 WNS**。F 把目标族从 8858 条压到 60 条，
  但 WNS 反而 −0.079，因为 A 族顶上来；只看 WNS 会误判 F 无效。
- 关键教训 3：Vivado 的 `-tclargs` 在本机 MSYS bash 下必须传 `C:/...` 原生路径，
  `/c/...` 会被 Tcl 的 `file exists` 判为不存在（第一次 ctl_80 就是这样空跑的）。
- 未改 `src/rtl`/`board/`/XDC；未 commit。

## 2026-10-24 晚 — F+A 复核与 F×后端配方

- 关键教训 4：**先核对 RTL 再排期**。计划文档里的"路线 A"（旁路决策提前到 ID 段末寄存）
  在 `cpu_core.v:373-386` 已经是这么写的；照计划再做一遍等于空跑。方案文档要带
  "当前 RTL 是否已是该形态"这一列。
- 关键教训 5：**后端配方不可迁移**。campaign 的 +0.138 靠复制最差端点的 CE 锥，
  F 之后墙移到 D 端（valid_way/lru），同一配方在 F 网表上只剩 −0.226。
  配方必须跟着"当前最差端点类型（CE/D/WE）"一起重选。
- 关键教训 6：`MAX_FANOUT` 只会被 `opt_design`/综合阶段利用；在 post-opt checkpoint 上
  设属性不会复制寄存器，必须 `phys_opt_design -force_replication_on_nets $nets`。
  否则会得到"两条臂逐位相同"的假结果。
- 关键教训 7：脚本 root 的相对层数按脚本自身位置算；复用别的目录里的 tcl 时先改 `../..`
  层数，否则会在仓库里生成 `build/build/`。

## 2026-10-24 夜 — 路线 C（dcache store buffer）

- 关键教训 8：**改 BRAM 写地址一定会打碎 RAM 推断**。原设计读/写同址（`rd_addr`）才能推成单口模板；
  一旦写地址改成 buffer 的地址，Vivado 报 `Synth 8-2914 Unsupported RAM template`。
  正确形态是把读口独立（Port A 只读）+ 写口与 fill 共用（Port B），即 SDP；
  顺手把 BRAM 从 38.5 降到 34.5 tile。
- 关键教训 9：**"0 周期"的验收要连硬件 MMIO 路径一起看**。F 的 MMIO 全卸载 670→675 拍，
  C 仍是 670 拍——同为"写路径打一拍"，差别在 F 把 MMIO 写延迟放进了软件可见的回合，C 只挡在
  BRAM 提交这一层并由转发兜住。
- 关键教训 10：dcache 这种模块最划算的回归是**逐拍差分激励**（同一份确定性激励 + 逐拍信号 dump +
  diff + 末尾存储器校验和），比写定向断言省一半时间，且能抓到"看起来对但时序变了"的差异。


## 2026-10-25 — V01 / Navigator提交与验证收口（owner TBD）

1. fetch后核对main=f88e178、分支feat/navigator_preboard；白名单20文件审查与git diff --cached --check通过，按用户授权commit/push为68fafc8，远程main/Skill/PUF保持不变。
2. 原D-Cache失败重现；git历史文件独立提取到build/local，三版本旧TB比较、四种子逐拍差分、独立事务scoreboard和回填/丢写负向门禁完成，分类TB_STALE。
3. 新增RV32汇编与CPU+CLINT TB，真实CSR设置、timer比较、6个trap/handler/mret场景和3个反例门禁实跑通过；未修改生产RTL。
4. 定向入口实跑PASS/exit0，完整日志/波形/镜像/命令/版本/SHA在build/local/preboard_targeted_final_03；smoke重跑PASS/exit0，新的中断入口接入regression，但旧D-Cache FAIL不隐藏。
5. 独立板级下一步清单、可移植小证据摘要与交接完成。用户另行授权追加公共日志和V01说明；后续测试/文档均留本地未提交，未再次push。


## 2026-10-25 — V01 修订旧D-Cache TB并实跑完整回归（owner TBD）

- 检查branch/HEAD/status与协作树，快照保留13项原有未提交工作；未clone/worktree/reset/clean/stash。原TB两次稳定四FAIL，日志保留。
- 原路径TB改为事件+事务队列检查，保持原expected与30拍完成界限，补请求上限/无竞争采样、mask/连续store/stall/reset覆盖。更新现有定向runner冻结历史TB+RTL并加入当前修订TB及7种故障注入，无生产RTL修改。
- 完整smoke实际exit0（6 PASS）；完整regression实际exit0（15 PASS，实板1 NOT_RUN）；内含Ascon三套CPU执行、Host/Mailbox、镜像/COE、Cache交叉验证和6个真实中断场景。Icarus/vvp12 devel、RISC-V GCC13.2、host GCC13.3、Python3.14.3。
- 正常测试零FAIL；历史/负向子进程exit1原样保存，独立gate验证对应原因。新证据与说明就绪，公共记录/V01同步，本轮未commit/push/merge。


## 2026-10-25 — 用户批准提交并合并main（owner TBD）

用户明确授权发布已验证的preboard成果。fetch/分支/待提交15文件/完整验证源SHA/敏感信息/受保护路径已复核通过；origin/main=f88e178未前进、可快进。仅作发布和Git验收，不重复执行输入未变的耗时CPU回归；保留smoke6 PASS与完整regression15 PASS证据。按白名单暂存并检查，提交后快进合并main并核验远程，不使用force push或丢弃工作区。
## 2026-10-26 — CPU 流水线底图（只读分析，未改 RTL）

- 新增 `docs/cpu_pipeline_flow.md`：模块层级、逐级职责、5 拍逐拍表、stall/flush 优先级、冒险/旁路矩阵、
  存储通路在流水线中的位置、多周期单元时序、可改点清单（F/B/H/E/M/S 六组）、测量方法。
- 纠正性发现：`if_id` **不寄存指令**（`if_id.v:50-70`，指令组合透传、与寄存后的 `if_pc_o` 同拍对齐），
  因此 icache 的 `stall = !(hit && hit_r)` 是「本次交付命中 + 下一个地址命中」的双守卫；
  `flush[2]` 在该拍丢弃 ID 指令是这套设计成立的前提，不是多余逻辑。
- `dcache.v` 已从 512 行旧版演进到 611 行（含 TIMING C 的 1 项 store buffer + 元数据寄存化），
  此前文档/答复里引用的 480~502 行区间已失效，新行号见 `docs/cpu_pipeline_flow.md` §6.2。
- `ctrl.v:62-63` 的 `rs1_hit_2st/rs2_hit_2st` 仍是死逻辑（只消费 `_1st`）。
- 未验证：多周期延迟（mul 2~3 / div ~33 / p12 ~13 / p8 ~9 拍）为代码推导，未逐拍仿真；
  可改点收益均为方向性估计。owner TBD。

## 2026-10-27 — C 线 PYNQ overlay：通道决策、RTL/固件/驱动骨架（未上板）

- 新建分支 `feat/pynq-overlay`，未 commit/push。
- 读 `board/atk_navigator_7020/interface_plan.md`、`src/pynq/{navigator_backend,mailbox_backend,mailbox_protocol}.py`、
  `docs/freeze_checkpoint_20261027.md`、`vendor_findings.md` 后，先做**可行性排查**而不是直接接线：
  RV32 外设全内部译码（无 PL 出口）+ dcache 只把 `0x100x_xxxx` 当 cacheable + 无 dcache 失效指令
  ⇒ 共享 BRAM 邮箱不可行（详见 lessons_learned 同日条目）。改采"复用 UART MMIO 当通道"。
- 产出（全为新增文件）：`src/rtl/pynq/{pynq_ctl,pynq_mbox,pynq_soc,top_pynq}.v`；
  `src/firmware/pynq_svc/*`（单槽邮箱服务，三模式，开机自检）；
  `src/pynq/{pynq_transport,test_pynq_transport,make_pynq_profile}.py`；
  `sim/pynq/{tb_pynq_bridge.v,ip_stubs.v,elab_check.sh}`；
  `board/vivado_zynq7000_xc7z020_pynq/{readme.md,rtl_p0/*.v}`；`docs/pynq_bringup_m1.md`。
- 验证：桥 TB PASS、42 文件整树 elaborate PASS、固件编译 exit0（text 46104 B，含 0x200b×1/0x300b×4）、
  Python 驱动 13/13 PASS、profile 生成器 self-test PASS；既有 mailbox/navigator/golden 无回归。
- 未做：Vivado 综合/实现/bit/hwh（另一个 Vivado 在跑，未并发）、上板、任何实测时间/周期。
- 下一步：M1（用户按 GUI 文档起板交证据）→ M2（建 BD、出 bit+hwh、`make_pynq_profile.py` 过
  `validate_overlay`）→ M3（邮箱跑通、三模式 KAT、端到端时间单列）。owner TBD。

## 2026-10-28 — Y01/Y02/Y03/Y04 最终集成，owner TBD

完成工作区/远端审查、安全快进与开发分支；审查P0/PUF源差异；实现Tcl自动BD、固件/驱动/桥修复、真实CPU+服务+AXI-Lite/UART联合验证、离线回归、SHA发布与中文上板手册。实际命令/退出码/工具/失败原件位于build/reports/pynq_final_20261028，最终状态见PYNQ validation文档。按本轮用户授权执行中文提交及main交付；不改历史板级证据。

构建/发布收口：build.tcl创建BD，rebuild_firmware.tcl修旧COE依赖后完成综合/实现/bitstream；verify.tcl重开routed设计实际运行setup/hold/DRC门禁PASS，发布sha256sum -c全部PASS。后续源码空白检查发现TB两行尾空格，单独清除，不改变仿真语义。

## 2026-10-29 — PYNQ benchmark 与 Notebook 测试入口

- 将临时 benchmark 逻辑转为 `src/pynq/board_benchmark.py` 永久入口，复用
  `board_demo.prepare_hardware()` 的 release 校验、Overlay/profile 和 boot 握手。
- Notebook 从仓库路径顺序运行 6-KAT smoke 与 KAT #529 的 5 次 warmup、30 次加解密采样，
  按时间创建 `data/pynq/notebook_<时间>/` 并保存 identity、JSON 和日志。
- 新增离线单测并完成 Python 3.8 AST、Notebook JSON/代码解析和 CLI help 检查；
  既有 transport 14/14、mailbox 24/24、navigator 8/8、host 17/17 回归通过。
  未加载 PYNQ、未改 RTL/固件/release，实板结果等待下一次板端执行。
- 修复 root Jupyter 下 `Path.home()` 指向 `/root` 导致仓库路径断言失败：
  Notebook 默认使用 `/home/xilinx/jupyter_notebooks/amd_fpga_2026`，并保留
  `ASCON_REPO` 显式覆盖，新增离线断言防止回退。
- 用户随后完成板端 Notebook `Run All` 并下载证据；独立校验 smoke 与 30 次加解密
  benchmark 原始数组通过。新增 `validation_20261029.md` 固化环境、release 身份、
  结果表、scope、文件 SHA 与未验项；Y04 done，Y05 等待 V03。

## 2026-10-29 — V03 板级错误门禁实现

- 新增永久 board harness/Notebook/离线测试，覆盖长度、半帧、deadline、重复 ID、
  stale epoch、RX overflow、恢复后三模式 KAT 和连续请求压力。
- 超长请求只发送 header，避免未消费 body 阻塞；故障后统一 reset、epoch 校验并重跑 KAT。
- 完成 Python 3.8 AST、Notebook 解析、CLI failure exit1/JSON 落盘与 6 项离线测试；
  未加载 PYNQ，未产生板级结果。
- 板端发现 error-gate 成功日志为 0 字节：原 harness 只写 JSON，stdout 为空。补每个
  check 的 START/PASS/FAIL 和 run 起止摘要，使 Notebook 捕获的日志可独立审计。
- 用户重新执行后 9/9 checks PASS、7 次恢复和每模式 50 次压力全部通过。归档 JSON/log/
  identity 及 SHA，更新 validation、任务板和 actual progress；Y03/Y05/V03 收口。

## 2026-10-29 — Markdown 状态同步

- 新增 `docs/current_status_20261029.md`，按实板证据区分核心完成项、未完成项和材料优先级。
- 同步 README、项目概览、架构、接口、PYNQ 协议/说明、任务板、里程碑、风险、交接、
  上板计划、报告目录与 Skill 目录；旧计划保留历史边界。
- 未修改 RTL、固件、测试结果或 release 产物。


## 2026-11-01 — D03 模板海报制作与核验

owner TBD。用户授权拉取、制作、提交和推送。main 干净，fast-forward 到 c05782d。
读取 AMD_poster_template.pptx 并在 PowerPoint 16.0 渲染；源文件只作为设计参考，
其示例信息与黄色提示不视为用户任务指令或本项目事实。用户确认学校及三名成员。
从锁定板测 JSON 自动取周期/加速比，使用仓库实物照片、架构、Skill 与实现报告证据。
输出 report/poster 的可编辑 PPTX、预览、构建/核验脚本、来源说明和验证 JSON。
修复 PowerShell 数组算术参数、COM 字号类型与文本框默认高度问题，重建后31项核验、
结构/布局检查和PowerPoint文字边界检查均通过；复查整页渲染，移开页脚说明与AMD标识重叠。
同步 report/readme、task_board 和 actual_progress。接口无变化，不重新上板、不更新测量结论。
