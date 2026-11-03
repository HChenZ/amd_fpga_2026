# 高端功能实施计划与阶段验收

> 2026-11-01：独立DMA/PUF v2实验计划与阶段状态，不是当前PUF3的默认功能。
> CPU-DMA全量目标仿真不转记到PUF3；PUF v2旧SoC候选已INVALID，原离线PASS不等于可上板。
> 本轮只收口说明，不继续执行旧计划或改程序；当前入口见 docs/version_entrypoints.md。

## 2026-10-30 实际实施增量（取代下方初始planned状态）

用户已授权完成可离线执行项及高速路径。当前证据索引：`../docs/advanced_offline_status_20261030.md`。

| 任务 | 离线状态 | 仍待内容 |
|---|---|---|
| A00 | done：独立源集、ABI v2、回退边界已建立 | 现场确认新工件 |
| P10 | done（离线）：错误关闭/新鲜度/deadline/撤销，RTL与CPU测试通过 | 真实停钟/异常板测 |
| P11 | 数字逻辑复验PASS：CDC-1消失、定义路径WNS+0.054、内部hold+0.098 | 条件IO hold仍-0.502；RO实际频率/物理界限未测 |
| P12 | done（离线）：内部key加密/重建/解密/坏tag，真实固件执行 | 上板一致性演示 |
| P13 | done（诊断离线）：版本化helper、reset后加载不重注册测试 | 真正断电50次及温压 |
| P14 | gated：normal调试读口关闭；保密helper/熵/ECC未宣称完成 | 物理BER/熵与安全构造定案，不能用全REF持久化替代 |
| P15 | partial：1–16B元数据绑定IMAGE_VERIFY离线通过 | 可信boot、执行互锁、回滚根与完整镜像能力 |
| PUF-SOC-V2 | 实际SoC/固件/私有BRAM/PS邮箱集成完成；2 Icarus+4 XSim+6 CLI PASS；已生成bit/HWH | STRUCTURAL_DIAGNOSTIC_ONLY，RO未签核；上板NOT_RUN |
| D10 | done（IP仿真）：actual AXI DMA7.1/BFM验证 | PS DDR/HP/cache实板 |
| D11 | done（离线）：真实CPU/XSim7418+实际DMA联合95项PASS；80MHz bit/HWH候选实现通过 | 板测NOT_RUN；100MHz失败单列 |
| D12 | board NOT_RUN，脚本就绪 | 新板级KAT/恢复/性能 |
| D13 | done（真实CPU仿真）：SW/ISE各1089、HW289，共7401加解密/坏tag事务 | 对应板测 |
| D14 | done（离线）：1KiB多块核、认证前候选保护，3467包+201生命周期检查 | 新板级功能和吞吐 |
| D15 | direct最终实现PASS：100MHz WNS+0.345/WHS+0.031、DRC0/0、bit/HWH；最终IP仿真3465包PASS | 板测NOT_RUN |

以下为最初工作量估计与阶段定义，保留用于解释任务依赖，不替代上方实际结果。

更新2026-10-29；owner均TBD，由项目方分配。**本表为计划，新增项均未实施/未测。**
已提交简介固定不改；后续结果单列补充证据，不把新版本替换成历史简介的原始测试。
11-01提交冻结仍生效；已有PYNQ release随时可回退。

## 1. 优先顺序

推荐：**PUF错误关闭/真实使用证明 → DMA环回 → DMA接RV32短消息 → 有限板级验收 → 再考虑多块与保密重建。**
PUF与DMA可由两人并行；同一Vivado工程与同一块板的烧录/测量必须串行预约。
每项用新目录、新artifact identity和独立日志，避免对方以为仍在测原版。

## 2. 任务表

工时为单人专注工作量估计，不是完成保证，EDA运行/板卡等待另外计算。

| ID | 工作 | 前置 | 交付/验收 | 估计 | 优先级/状态 |
|---|---|---|---|---|---|
| A00 | 固定两个实验入口、当前release与地址/协议草案 | 现有发布证据 | 原版hash可恢复；接口草案与版本号 | 2–3h | 必先做 / ready |
| P10 | PUF采样错误、新鲜度、核心域deadline、失败清旧key | A00 | stop-clock/watchdog/reset/旧结果注入均显式失败 | 4–8h | 最高 / planned |
| P11 | RO健康/CDC/时钟与布局排查 | A00，实施P10可并行 | 查常量折叠、计数差/相等/饱和、同步与例外清单 | 1–3天 | 最高 / planned |
| P12 | 内部key驱动AEAD的板级一致性演示 | P10；新构建风险已说明 | enroll→AEAD→reconstruct→AEAD一致，错误情况拒绝 | 4–8h+构建 | 提交前优先 / planned |
| D10 | AXI DMA simple mode环回 | A00 | 长度/尾字节/背压/缓存/超时测试，逐字节与canary通过 | 4–8h+构建 | 高 / planned |
| D11 | DMA packet端点接RV32 uncached MMIO | D10 | 新RTL/固件transport，单槽/epoch/reset契约成立 | 1–2天 | 高 / planned |
| D12 | 16B三模式DMA板测与同输入性能 | D11 | 各289 KAT、坏tag、恢复；30样本墙钟与mcycle分列 | 3–6h+板测 | 条件争取 / planned |
| D13 | SW/ISE扩到32B，按模式能力握手 | D12 | SW/ISE各1089官方KAT；HW仍限16B | 4–8h+回归 | 后续 / planned |
| P13 | 诊断helper持久化与有限断电重建 | P10/P11可用 | 不重enroll、固定helper，50次真实断电记录 | 1–2天+板测 | 后续 / planned |
| P14 | 保密helper/纠错/提取与禁止debug回读 | P13实际BER、威胁模型 | helper泄漏分析、码参数、误纠正拒绝、生命周期 | 3–7天以上 | 后续 / planned |
| D14 | 真正多块AEAD核+认证前候选BRAM | D13，算法契约 | 1089+随机/边界/背压，认证前无PT流出 | 3–5天以上 | 后续 / planned |
| D15 | DMA直连多块核与独立计时 | D14 | HW_DIRECT真实运行；不称ISE加速；新的资源/时序 | 1–2天+构建 | 后续 / planned |
| P15 | PUF镜像认证原型 | P14、可信boot与元数据策略 | 正确镜像可执行、篡改/回放按策略拒绝 | 2–4天以上 | 最后 / planned |

DMA若仅完成D10，可展示“DMA传输环回”，不能称Ascon已通过DMA。
PUF若完成P12但P11仍有未解释时钟问题，可展示限定条件功能结果，不称全域签核或可靠密钥系统。
未完成的项不把预计日期换成done。

## 3. 提交前按天安排

| 日期 | DMA线 | PUF线 | 材料/Skill线 |
|---|---|---|---|
| 10-30上午 | A00、D10最小BD与环回 | A00、P10错误契约与故障TB | 先按既有Skill指导表测试，避免所有人改RTL |
| 10-30下午 | D10板测，若通过再D11 | P10验证，P11结构/时钟排查 | 记录新实验commit/hash，已提交简介保持不变 |
| 10-30晚 | 依据实际D11进展决定是否值得集成 | 有条件准备P12新固件与镜像 | 形成当天真实结果，不写预测性能 |
| 10-31上午 | 仅D11通过才做D12 | P12有限板级验证，失败先留证 | 视频、PPT、当前/原型版本索引 |
| 10-31下午 | 若板测不稳，停止新增，保留原PYNQ主线 | 未闭环写边界，不强行标安全/可靠 | 人工审查与提交包hash；留出恢复原镜像时间 |
| 11-01 | 不临时替换未验收新bit | 不临时扩充未测功能 | 提交确认与冻结，保存回执 |

若仅一人/一块板：优先P10/P12的实质功能证明，其次D10；不要承诺在两天内把D14/P14/P15一起做完。
已有CPU+ISE主线不会因为高级实验尚未通过而失去当前演示入口。

## 4. 每项交接最小字段

`task_id, owner=TBD, source_commit, dirty_patch, source_hashes, tool_versions, part, top,
protocol_version, firmware/bit/hwh hashes, commands, exit_codes, raw_results, failure_samples,
measurement_scope, implemented/not_measured, rollback_artifacts`。

实验输出建议 `data/advanced/{dma,puf}/<run_id>/`，保留逐次JSON/CSV、原始log与报告，不只截图。
实施细节与测试矩阵见 `../docs/dma_puf_implementation_plan.md`。
