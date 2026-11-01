# 本轮交接：自动测试、COE、领航者 PYNQ 准备

> 2026-11-01：本页“本轮”是早期板前交接，不是当前 PUF3 工作区。镜像/物理服务未配置等按当时解读。
> 后续有旧v1与PUF3各自板测；当前入口见 docs/version_entrypoints.md，原FAIL/BLOCKED不回写。

2026-10-25 / owner **TBD**。任务映射：A=V01/C03/Y05 自动化子集；B=B04/C02 镜像子集；C=B03/Y01/Y03/Y04 无板准备。没有提升完整板级任务为done。

## Git 与范围

- 仓库 `E:\amd_fpga_2026`，origin `https://github.com/HChenZ/amd_fpga_2026.git`。
- 起始分支 `cleanup/remove-legacy-ascon-aead`，HEAD `7139a80e726df28dc672264014c36b0b55aa27ea`，存在未提交改动。用户明确回复“直接丢弃本地改动吧”后，先备份至 `build/local/preboard_safety_20261025_155143/`，再恢复/移出相应文件；未使用reset --hard、clean或stash，备份保留。
- `git fetch origin` exit0；main安全fast-forward至 `f88e178acb23e1a4cab2c6d8263349fdcb7bb85e`，创建用户指定 `feat/navigator_preboard`。本轮结束HEAD与origin/main左右差异0/0，工作区仅本轮新增文件。
- 未新clone、未新建worktree、未commit/push、未产生merge commit。原有另外两个worktree保持不动。
- 最新main同步包含正式提交，这是用户允许的同步；同步后本轮**没有主动修改** `skill/`、PUF/RO/key lifecycle、CPU/Cache/Ascon生产RTL、共享SoC、固件、baseline、data或原测试脚本/向量。protected_evidence前后SHA检查PASS。

新增文件（全部在用户允许目录）：

| 目录 | 文件 |
|---|---|
| sim/board | common.py、coe.py、build_firmware.py、legacy_runner.py、run_tests.py、uart_log.py、test_tools.py、verify_cpu_images.py、readme.md |
| src/pynq | navigator_backend.py、test_navigator.py、navigator_demo.ipynb |
| board/atk_navigator_7020 | backend_profile.json、navigator_uart.xdc、inspect_vendor.py、vendor_sources.json、vendor_findings.md、interface_plan.md、readme.md、handoff.md |

`build/local`包含隔离输出，不入Git。项目公共日志/任务板位于本轮允许目录之外，用户尚未批准其追加，故本轮不改 `actual_progress`/`development_log`/`lessons_learned`/任务板。供主线同步的事实、任务建议和失败经验集中在本文件；这不是声称已更新公共台账。

## 实际验证

| 命令 / 证据目录 | 结果 | exit / 耗时 |
|---|---|---|
| `python -B sim/board/run_tests.py --mode smoke --out build/local/preboard_smoke_final_02` | 6 PASS / 0 FAIL / 1 BLOCKED / 8 NOT_RUN；中断缺覆盖使聚合BLOCKED | Python exit2；详见summary.json |
| `python -B sim/board/run_tests.py --mode regression --out build/local/preboard_regression_01` | 12 PASS / 1 FAIL / 1 BLOCKED / 1 NOT_RUN | exit1；673.341s |
| 既有四backend `run_validation.py`，report在上述regression目录 | 完整1,089 KAT+补充/permutation/篡改，总28,661 PASS / 0 FAIL | exit0 |
| 原CPU runner SW/HW/ISE，通过legacy_runner隔离证据 | 三种均PASS；SW6组，HW/ISE4组代表KAT及原固件加解密/篡改检查 | 各exit0；282.618 / 213.163 / 161.323s |
| 原`golden_checker.py --backend mailbox --mode ise` | 1,089 PASS / 0 FAIL，4,290次篡改拒绝；simulated | exit0 |
| Host API / Mailbox / Navigator / 工具单测 | 最终17 / 24 / 8 / 8项均PASS；含Notebook顺序执行 | exit0，各原始日志在smoke目录 |
| `inspect_vendor.py`，`build/local/preboard_vendor_02/` | 文件/ZIP成员读取、8个唯一端口/管脚与厂家XDC对应PASS | exit0 |
| `verify_cpu_images.py`，`image_identity_final_02.json` | 最终三套COE对应BIN与实际CPU仿真BIN一致 | exit0 |
| `image_identity_negative_test.json` | 只篡改副本元数据SHA；检查器确实拒绝，未动原镜像/证据 | 子进程exit1为预期，负向门禁PASS |
| UART模拟fixture与三套实际RTL UART日志解析 | 模拟fixture明确simulated；RTL日志明确rtl_simulation；缺固件/bit身份保留null | fixture CLI exit0；JSON在build/local |

回归运行期间增加了适配器配置校验、ELF装载段检查、UART旧格式覆盖和镜像一致性门禁；这些最终新增/变更代码另由最终smoke、独立镜像检查和D-Cache局部复跑核验，没有重复耗时CPU仿真。CPU/固件/RTL生产输入完全不变。完整regression早于新增的cpu_image_match入口，其独立结果另存，不回写旧summary冒充同次执行。

工具：Windows Python3.14.3；Icarus/vvp12.0 devel(g2693dd32b)；WSL Ubuntu RISC-V GCC13.2.0、binutils2.42；Host gcc13.3.0 / python3.12.3。编译flags及每个子命令、退出码、源SHA、时间均见JSON/日志。Vivado仅-version：2025.2，Build6299465/IP6300035，本次退出1与HLS路径警告保留在厂家说明；没有工程构建/时序搜索。

## 镜像交付

最终目录 `build/local/preboard_smoke_final_02/firmware/`：

| mode | 相对子目录和文件stem（每个均有.elf/.bin/.hex/.coe） | BIN字节 | 静态栈余量 |
|---|---|---:|---:|
| SW | sw/ascon_sw | 40,888 | 90,168 |
| MMIO | hw/ascon_hw | 4,152 | 126,904 |
| ISE | ise/ascon_ise | 6,688 | 124,368 |

入口/_start=0x10000000、栈顶0x1001fff0，所有load/alloc段在128KiB内，同装载/运行地址，data/BSS不重叠栈；动态栈峰值NOT_MEASURED。原crt0清BSS，实际RV32仿真执行的BIN与这些构建相同。COE32×32768、radix16、little-endian字内字节、升地址字序、零填充；BIN/HEX/COE和ELF内容检查PASS，各产物SHA256在build.json中。**未重建BRAM IP、未证明正式bitstream或板上启动**，原freertos_demo.coe保留。

## 板卡/PYNQ结论与接口变化

来源：厂家PYNQ指南V3.2、核心板2V5/底板V3.9原理图、NAVIGATOR XDC与7020示例ZIP。指南描述PYNQ2.7.0/Ubuntu20.04/kernel5.4.0和SD启动镜像，但当前资料树/ZIP没有对应img，BLOCKED。完整Base为PS7 5.5、DDR3 32bit/533.333MHz、UART0 MIO14–15、SD0 MIO40–45/CD10、ENET0 MIO16–27/MDIO52–53、FCLK0 100MHz；简化GPIO Overlay关闭MIO并使用50MHz FCLK0。实物DDR/速度等级/启动软件与Python环境待核，不能照抄简化Overlay重建Linux启动平台。

独立XDC提取PL外50MHz/U18、reset N16、底板LED H15/L15、按键L14/K16、USB UART T19/J15；排除厂家模板里同名UART的RS232/485与ATK重复定义。P5 PS=1–3/2–4，PL=3–5/4–6；基于V3.9 p6目视核验，实物丝印需再确认。项目继续`xc7z020clg400-1`，厂家示例的-2不覆盖项目。

新增Python接口：`NavigatorTransport`（既有Transport实现的注入/验证接口）、`NotConfiguredError.status='NOT_CONFIGURED'`、`create_host`。现有AsconHost/MailboxBackend/MemoryTransport/黄金参考和生产接口均不变。默认profile空地址，真实路径要求已加载Overlay、相同basename的bit/hwh、firmware哈希/标识、设计与协议来源、HWH一致且不重叠的control/mailbox窗口。没有物理driver就报NOT_CONFIGURED，不返回模拟硬件成功。Mock强制simulated=True，cycles=None。Notebook默认模拟，支持三mode、输入、加解密、密文/tag、官方KAT样本/坏tag、cycles/加速比区分；无硬件时speedup为NOT_MEASURED。

接口建议A：AXI-Lite控制+独立共享BRAM，复用逻辑Mailbox v1；CPU复位/启动、PS/RV32地址、cache可见性、时钟/复位、原子完成/ACK/epoch/timeout需团队冻结。方案B直接写执行BRAM风险更高；不声称当前SoC已具备PS访问通道。PUF仅记录将来版本化key_handle协商需求，不开发/改动任何模块。完整方案见interface_plan.md。

## 失败、返工与剩余阻塞

- **D-Cache FAIL**：旧TB在第一个miss接受后36ns检查bus_mem_re/load_miss/address，但波形显示MISS_CAPTURE在35ns进入，45ns才发布这组输出；另一个miss有同类早一拍断言。4个失败不隐藏，也不能仅凭这个现象断言Cache功能全面正确。需V01维护者修订/确认时序契约后验证，当前回归不能标全绿。
- **中断 BLOCKED**：缺可复用定向测试，现有程序中断关闭，不能以三套Ascon PASS代替中断覆盖。
- 首轮smoke因新Notebook使用错误KAT字段大小写而FAIL；第二轮因配置缺失异常分类与测试预期不一致FAIL；修正后最终smoke零FAIL。早期日志在preboard_smoke_01/02，保留。
- 旧D-Cache TB默认在cwd写VCD；首次生成的本轮波形已保存在regression目录dcache_first_run.vcd。统一入口改为在本次local目录运行vvp，再复跑得到相同4个FAIL，dcache_local_cwd.json/log/vcd保留；未修改TB。
- BLOCKED/NOT_RUN：厂家镜像取得/启动、实物速度等级和DDR、PYNQ/Python版本适配、2020.2→2025.2工程/IP兼容性、真实物理driver/服务固件、缓存/CDC/复位/超时恢复、正式bit/hwh、真实板卡KAT与UART。FPGA cycles/加速比/PPA均NOT_MEASURED。

下一接收：V01/TBD（D-Cache时序测试、中断门禁）；B03/TBD（实物/image/runtime）；Y01/TBD（审查物理接口）；Y02/TBD（经确认后独立Overlay），再Y03/Y04/V03真实联调。本轮代码/生成工具已交付，不自动集成受保护RTL，不自动commit/push。
