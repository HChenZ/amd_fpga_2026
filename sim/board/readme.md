# Navigator preboard 自动测试与镜像（V01/C03/B04/Y01/Y03/Y04，owner TBD）

2026-10-25。只新增独立工具，复用已有 firmware、KAT/reference、CPU runner 和 Host/Mailbox API；原生产源码、测试向量和历史证据不改。

从仓库根目录：

```powershell
python -B sim/board/run_tests.py --mode smoke
python -B sim/board/run_tests.py --mode regression
```

默认每次创建 `build/local/preboard/<UTC时间戳>_<模式>/`，已有输出目录拒绝覆盖。可用 `--out build/local/<新目录>` 固定本次路径；所有命令必须从仓库根运行。外部厂家资料不作为 smoke/regression 的依赖。

| 集合 | 覆盖 | 避免重复的原因 |
|---|---|---|
| smoke | 8项工具单测、既有17项Host API、24项Mailbox、8项Navigator适配器/Notebook、三套固件/COE构建检查 | 不跑完整1,089 KAT与耗时CPU仿真；通常数十秒，实际时间随工具/磁盘变化 |
| regression | smoke + 既有四backend Host全KAT/加解密/篡改/permutation；SW/HW/ISE真实RV32固件+生产RTL；Mailbox全KAT；既有D-Cache TB | 一次四backend Host验证已覆盖完整算法；MemoryTransport的三个mode共用reference，因此全Mailbox KAT只跑一次ise，三mode选择由Host/adapter单测覆盖 |

SW/ISE target固件当前为6组代表KAT加解密与篡改检查；MMIO以其固件支持的≤16B集合为准，不声称target全部1,089 KAT。CPU仿真由原 `run_cpu_regression.py` 完整编译当前生产RTL执行，不用Python密码函数替代RTL。`run_ascon_sw/hw/ise.sh` 是这同一runner的薄入口，因此不再重复运行shell包装。

CPU中断后续已增加独立定向验证，见下方2026-10-25补充；smoke中为NOT_RUN，regression调用实际测试。D-Cache回归实际运行修订后的原路径TB与独立事务TB；历史4个旧时序FAIL保存在冻结快照及旧日志，分类TB_STALE，当前两套TB均必须exit0。没有修改生产Cache。ISA全套不是本轮最小集合，已有文档记录ma_data对齐能力缺口，不把这次集合当完整CPU合规测试。板上UART/Overlay为NOT_RUN，FPGA cycles/加速比为NOT_MEASURED。

## 工具与报告

不安装工具。native Python≥3.11、Icarus/vvp≥12、RISC-V GCC≥13（还需实际RV32IM_Zicsr/ilp32 libgcc构建成功）。Windows默认调用现有WSL Ubuntu的 `riscv64-unknown-elf-`；`--cc-prefix C:/.../riscv-none-elf-` 可指定native工具。独立build包装器支持其他盘符，但既有CPU runner的native路径判定仅认C盘，其他盘符请使用默认WSL路径；本轮不修改该原runner。环境变量 `PREBOARD_WSL_DISTRO` 可改构建和Host验证的WSL发行版，但既有CPU runner固定Ubuntu，因此完整regression仍需Ubuntu。完整Host C验证还需WSL gcc≥13及python3；其实际版本另在Host验证JSON中。

每个子命令保存命令、cwd、exit_code、耗时和stdout/stderr；`summary.json`保存HEAD/分支/dirty状态、版本探测、来源SHA、状态计数；`summary.md`便于阅读。`PASS`只表示对应范围通过，`FAIL`表示执行或断言失败，`BLOCKED`表示缺工具/缺覆盖或依赖，`NOT_RUN`表示按模式省略/未上板。聚合优先FAIL，其次BLOCKED；退出0=PASS、1=FAIL、2=BLOCKED/NOT_RUN，**不能因其余测试通过而抹掉中断缺口**。

`legacy_runner.py` 在独立子进程运行原脚本，仅将 `Path.open` 对 `data/ascon/results/` 的写操作重定向到本次 `build/local` evidence子目录，并拒绝其他非local的Python写操作。原脚本仍按原逻辑编译/仿真，build目录使用唯一label；统一入口前后SHA核对data、reference、baseline，防止旧证据被修改。编译工具的输出参数均指向local；这不是操作系统sandbox，不应用来执行任意不可信脚本。

## 固件和COE

```powershell
python -B sim/board/build_firmware.py --out build/local/firmware_new
```

生成 `<out>/sw/ascon_sw.*`、`hw/ascon_hw.*`、`ise/ascon_ise.*`：ELF、BIN、HEX、COE，另有反汇编、readelf、nm、size、完整编译日志、`build.json`与`builds.json`。不调用写死旧工具路径/输出路径的build.sh，独立包装器复用相同编译选项及原crt0.S/main.c/uart.c/libc_min.c/riscv.ld/bin2vhex.py。原脚本和固件不改。

固定 `-march=rv32im_zicsr -mabi=ilp32 -O2 -ffreestanding -nostdlib -fno-builtin -fno-stack-protector -msmall-data-limit=0`，链接libgcc，无LTO。检查ELF32/little-endian/RISC-V/ABI flags、入口与_start=0x10000000、PT_LOAD同装载/运行地址、所有alloc段在128KiB内，_sdata/_edata/_sbss/_ebss和_stack_top=0x1001fff0有序，至少4KiB静态栈余量；运行时最大栈使用NOT_MEASURED。原crt0负责BSS清零，单纯镜像检查不冒充启动验证。

COE radix16、32-bit×32768完整字。BIN地址最低byte是字内最低8bit；`78 56 34 12`对应COE `12345678`，第i字映射`0x10000000+4*i`，末尾补零。重新解析HEX/COE并与ELF alloc内容及完整补零BIN比较；空镜像/溢出/错误字序/非法COE拒绝。四种产物都记录SHA256。`verify_cpu_images.py`及regression中的cpu_image_match检查三套COE构建BIN与原CPU runner实际使用的BIN逐字节SHA一致，避免只验证另一个镜像。原baseline的freertos_demo.coe完全不改；后续独立Vivado工程需要自行指定新COE并重建IP，**本轮没有证明BRAM硬件加载或上板启动**。

## UART文件解析

```powershell
python -B sim/board/uart_log.py build/local/uart_simulated.txt --out build/local/uart_simulated.json
python -B sim/board/uart_log.py path/to/captured.log --evidence-kind hardware_uart_capture --out build/local/uart_capture.json
```

默认simulated；RTL日志应选rtl_simulation；hardware_uart_capture只表示用户声明的采集来源，不构成板卡身份或哈希认证。解析legacy `KAT name : PASS/FAIL`、`tamper reject`和enc/dec cycles；也支持未来结构化行：

```text
[ASCON] mode=SW firmware_version=simulated-v1
[ASCON] test=empty status=PASS mcycle=123
```

可加 `rtl_sha=<40或64hex>`、`bitstream_sha=<64hex>`；无字段保留null。测试值明确simulated，不能当benchmark。也解析现有MMIO/ISE的dec round/tamper/len reject、full MMIO、ISE cycles；crypto latency保存在独立crypto_core_cycles字段，不冒充CSR mcycle。benchmark行没有独立正确性结果时status=NOT_RUN；缺mcycle为NOT_MEASURED。FAIL/FATAL/TIMEOUT、重复字段、非法状态/u64/身份格式导致失败，不能让固定的`KAT: n/n PASS`覆盖前面的真实失败。当前固件尚不输出版本/RTL/bitstream身份，不替它补造字段。

板级资料和交接见 [board/atk_navigator_7020](../../board/atk_navigator_7020/readme.md)，真实配置入口仍NOT_CONFIGURED。初次上板准备的目录限制与旧事实保存在`handoff.md`；后续提交/定向验证见`validation_followup.md`及项目日志。

## 2026-10-25 后续：D-Cache与CPU中断

```powershell
python -B sim/board/run_targeted_validation.py --out build/local/targeted_new
```

可用`--mode dcache|interrupt`单独运行。前者比较引入miss流水前、Store Buffer前和当前源码，保留原4项FAIL证据，并用独立scoreboard/4种子逐拍差分及错误回填/丢写门禁诊断。后者运行生产CPU+真实CLINT，6场景均必须实际接受中断、检查架构CSR、执行handler和mret、恢复循环；禁timer、无mret固件与临时副本绕过guard都必须失败。生产RTL不修改，临时负向副本只在build/local。

新入口gate PASS表示当前事务/架构契约通过且负向门禁有效。旧固定时序TB及其对应生产RTL按已发布68fafc8冻结，仅作历史复现，原始FAIL/exit1仍明确保存；当前生产RTL运行修订版TB，必须PASS/exit0。统一regression直接运行原路径的修订TB，并调用定向入口执行事务TB、故障注入和六场景中断。历史失败与预期故障注入的FAIL不能改写为原始PASS，当前正常测试的真实FAIL也不能豁免。smoke不运行这组RTL测试，状态为NOT_RUN而非“缺测试”BLOCKED。

旧TB修订采用独立预期事务队列、请求事件与有界等待，完整检查地址/方向/数据/字节掩码/请求次数/回填；保持30拍完成上限，新增8拍请求上限与总watchdog。刺激下降沿驱动、输出上升沿NBA之后采样；保留原所有场景/expected，增加连续store、额外byte mask、跨时钟stall与半条line填充时reset。除事务TB原有坏回填/丢写门禁外，修订TB也必须拒绝坏回填、缺读/重复读/错地址/错写数据/错掩码/缺写。详见 [D-Cache测试契约修订](dcache_tb_revision.md)。
