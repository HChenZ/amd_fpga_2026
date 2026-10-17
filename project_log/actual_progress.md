# 实际进度

## 2026-10-17 — V06 阶段性收尾与证据复核

owner TBD；工作区 E:/amd_fpga_2026_key_lifecycle，分支 fix/ascon-key-lifecycle。
2026-10-16的两轮实现均完整结束；本日只读复核源码/日志/报告，不重开Vivado，不做第三轮优化。
117个源码hash、所有物理报告hash、六组CPU测试输入和实现RTL快照均匹配；XDC/COE及原baseline未改。
blk_mem_gen独立副本仅有工具元数据/checksum改写，功能参数不变，双侧hash已保存。

- 最终软件/MMIO/ISE原KAT均PASS；动态密钥安全检查132/123/402项全部PASS。
  Host Final 28661项、C失败输出23965项、MMIO/ISE RTL 13212/1500项、4个CPU单测、
  4个RTL故障注入门禁与867请求逐周期等价检查均PASS。复用哈希一致证据，未重跑长测试。
- 最终Vivado2025.2、xc7z020clg400-1、top_pl_bram：WNS=-0.177ns、TNS=-2.968ns，
  31个setup失败端点；WHS=0.015ns/THS=0、WPWS=3.750ns/TPWS=0。
  LUT11636/FF15949/BRAM38.5/DSP4；23917个net fully routed，routing errors=0。
- **100 MHz timing not met**。DRC已报告95 Warning/0 Critical Warning/0 Error（部分规则达到上限），
  Methodology另23 Warning。cache地址/hold控制剩余路径、LUT派生复位、BRAM异步控制、PS7与板级IO覆盖仍需处理。
- 安全修复与时序分析可作为阶段性成果提交；V06保留in_progress，上板门禁未过。
  官方固定KAT与运行时参数边界明确，新增3组公开Key/Nonce；没有真实秘密或生成缓存纳入提交。

完整证据：[最终汇总](../data/ascon/results/key_lifecycle/final_validation_summary.json)、
[时序审查](../docs/ascon_timing_review.md)、[密钥审查](../docs/ascon_key_management.md)。
下一接收 B02/B03/V01/I08/Y01；先保存Git检查点，再进行用户授权的Ross/Skills低风险评估。


## 2026-10-16 — V06 密钥生命周期与上板前审查

owner TBD；基于最新 origin/main `c37ecae`，独立 worktree / `fix/ascon-key-lifecycle`。
用户本轮明确授权检查通过后自动 commit/push，原工作区未提交改动全部保留。

- 三套实现均已存在，不能沿用下文早期“未实现 ISE”的结论。新增 [密钥生命周期审查](../docs/ascon_key_management.md)
  与 [板卡清单](../docs/ascon_board_checklist.md)，详细结果索引为 `data/ascon/results/key_lifecycle/validation_summary.json`。
- 修复：MMIO idle CTRL[2] ZEROIZE、BUSY/失败/越界读保护、旧输出清理和尾字屏蔽；
  ISE 失败输出擦除/长度、部分密文 Tag 指针、状态清理、非法索引、完成保持；
  CPU 提前译码遗漏的 custom 操作数旁路/load-use；软件 C 本地敏感对象擦除。
- 固定官方 KAT 不变；3组公开动态 Key/Nonce、27个长度组合由锁定 Final C/Python 交叉核对。
  MMIO 只跑其中21例（AD/消息各<=16字节），不宣称多块接口。
- Host Final 28,661 PASS/0 FAIL，production C raw failure 23,965 PASS/0 FAIL；
  独立 RTL 全源集 Final KAT/置换/认证与故障注入通过。MMIO 13,212、ISE 1,500项检查通过；
  baseline bypass/regfile/EX ALU 与新增 execute cancel/hold 单测通过。
- CPU 软件/MMIO/ISE 的最终 KAT、安全测试和周期结果由上述 JSON/原始日志定稿；
  明确使用 GCC13.2/仿真50MHz，不与队友 GCC15.2 的历史数值混算。
- Vivado2025.2可运行，原始三个IP未锁定且再生成成功。独立副本综合0 errors/0 critical warnings；
  实现结果、时序、资源、DRC在最终汇总中列明。原 baseline、XCI、XDC、COE不改，579项恢复资产hash通过。
- 真实板型未知、未烧录；FreeRTOS COE未换为Ascon固件，PS/PL/PYNQ尚未建立。
  ISE完整抢占上下文、全部ISA/异常/外设回归、板上测量仍未完成。清零不等于抗侧信道/物理提取。

最终补记：三套CPU原KAT全部PASS；新增安全检查软件132/132、MMIO123/123、ISE402/402，
ISE含下游hold跨完成和计算中reset重启。16B warm加密仿真周期：软件18348、MMIO完整往返664
（START→轮询完成100）、ISE2559；软件32B enc22817，dec16B18886/32B23388。
六个最终源码loadable binary与已测镜像逐字节一致，ISE反汇编有实际custom-0编码。
Vivado布线完成exit0，但100MHz WNS=-1.641ns、TNS=-607.794ns（1971失败端点），
LUT11683/FF15960/BRAM38.5/DSP4；DRC已报告95项Warning、无Error（部分规则达到报告上限），
存在PS7缺失、BRAM/复位与IO delay覆盖告警。故V06保留in_progress，上板门禁未通过。
已完成的安全修复与仿真可审查，时序收敛/实板功能不可标完成。

下一接收 B02/B03/V01/I08/Y01，owner TBD。历史与中间失败保留，不把综合或仿真冒充上板。


## 2026-10-15 — Ascon-AEAD128 软件版在自研 RV32IM CPU 上运行并测得软件性能

owner TBD；用户授权"调用已有 C 代码库完成软件版、测试保证处理器可用、测软件性能"。
未改任何现有 RTL/TB/KAT/脚本；新增固件与仿真平台，全部落在约定目录。

- 新增 src/firmware/ascon_rv32/：crt0.S、riscv.ld（ORIGIN=0x10000000 对齐复位 PC）、
  main.c（`#include` 锁定生产 ascon/ascon_c/aead/aead.c）、uart.c/h、libc_min.c、
  bin2vhex.py、build.sh。工具链 riscv-none-elf-gcc 15.2.0，
  `-march=rv32im_zicsr -mabi=ilp32 -O2 -ffreestanding -nostdlib -lgcc`；
  64 位软件基线因此需要 libgcc(__udivdi3/__lshrdi3 等)。镜像 code=38852 B、data=0、bss=0。
- 新增 sim/ascon/axi_slave_bram.v（AXI4 行为 BRAM：4 拍 WRAP 读 + 单拍写 + $readmemh）
  与 tb_ascon_sw.v（soc_top @50MHz + BRAM + UART monitor 解码 txd、检测 DONE/FAIL 标记）。
  入口 sim/ascon/run_ascon_sw.sh 一次完成 交叉编译→iverilog 编译→vvp 运行。
- 实测（Icarus 14.0 devel / vvp，退出码 0）：6 组官方 KAT（empty/1B/16B/16B+AD/17B/32B）
  加解密全 PASS，tag 篡改拒绝 PASS；CPU RTL(soc_top) 确实执行 ISE 无关的纯软件 Ascon。
- 软件性能（warm，模拟实测，非上板）：enc 16B=16840 cyc(1052.5 cpb)、enc 32B=21018(656.8)、
  dec 16B=17226(1076.6)、dec 32B=21461(670.7)；CPI≈3.9~4.0。mcycle 用 CSR 0xB00/0xB80
  high-low-high 读取；指令数用 cpi_cnt MMIO(0x60000000/04)。UART@115200 主导 cycle 量
  （每字节 4340 clk），故加密/解密各运行两遍取第二遍作为 warm 测量。
- 未验证/未测：上板(B02/B03)、Vivado 综合/实现/PPA、CPU ISE、完整 1,089 KAT 的目标运行
  （仅 host 全量 + 目标 6 组代表向量 + 篡改）。cycle 为仿真实测，不是 board 实测；未改任何 RTL。

C02 目标编译/运行与 C04 CPU 级软件 benchmark 已在仿真层达成；C03 目标 KAT 为 6 组代表向量
（全量仍在 host）。板级与 ISE 仍依赖 B02/B03/V01 后续接收。

## 2026-10-15 — Ascon MMIO 加速器接入 CPU（第一次硬件优化）

owner TBD；用户授权"结合 IO 接口代码把已写好的硬件接入、做第一次优化并测试"。
复用队友 IO/ 的 ascon_mmio.v（寄存器文件+FSM+缓冲，基址 0x30000000）与已 KAT 验证的
crypto_aead.v，新写 ascon_aead_core.v（32-bit 流式接口 → 128-bit 并行 crypto_aead 的适配器）。
改了 bus_interconnect.v（新增 ascon MMIO 译码 + read_sel_q 扩 6 位）与 soc_top.v（实例化
ascon_mmio、ireq_external 并入 ascon_irq），均为 README 记录的增量接线；未动 crypto_aead.v。

- 新增 src/rtl/ascon/ascon_mmio.v（队友 IO 原件字节一致复制）、ascon_aead_core.v
  （streaming 适配器，≤16B AD/msg，超长立即 done+success=0 拒绝）。
- 新增 src/firmware/ascon_hw_rv32/（MMIO 驱动固件，code=3936 B）与 sim/ascon/run_ascon_hw.sh。
- 关键 bug：crypto_aead 的 mode=0 加密/1 解密，而 ascon_aead_core 的 encrypt=1 加密/0 解密，
  初版直连导致所有加密请求按解密执行（空消息 tag 恰好仍对，非空全错）。修 .mode(!encrypt_r)。
- 实测（Icarus 14.0/vvp，exit 0）：4 组官方 KAT(empty/1B/16B/16B+AD) 加解密 PASS、
  解密往返 PASS、tag 篡改拒绝 PASS、17B 超长拒绝 PASS——CPU 通过 MMIO 驱动硬件 Ascon 正确。
- 性能（warm，仿真实测，非上板）：16B 加密 纯 crypto 延迟 99 cycles、完整 MMIO 往返 544 cycles；
  对比纯软件 16840 cycles → crypto 核心 ~170×、端到端(含寄存器读写+轮询) ~31×。这是 ISE 前
  的第一级硬件加速，MMIO 开销(寄存器写+轮询+读回)是下一步 ISE 要压缩的部分。
- 未验证/未测：上板、Vivado 综合/PPA、>16 字节消息、真正的 CPU ISE(I02~I07)。未改 crypto_aead.v。

## 2026-10-15 — Ascon 置换 custom instruction (ISE) 完成（最后的优化）

owner TBD；用户授权"继续完成 ISE 优化并测试，这是最后的优化"。在 RV32IM 软核里加入
Ascon 置换 custom instruction（custom-0 opcode 0x0B），复用已 KAT 验证的 p12/p8 模块，
CPU 用 inline asm 跑置换、其余 AEAD 逻辑仍用 C。改了 defines.v / id_stage.v / ex_stage.v
（新增 opcode/func_sel、译码、执行与多周期 stall，仿 divider 的 ex_stall_req 机制），
未动 crypto_aead.v/p12/p8。

- 新增 src/rtl/ascon/ascon_ise.v：CPU 内 320-bit 状态寄存器 + p12/p8 握手。
  4 条指令（.insn r 0x0B, funct3, funct7=0, rd, rs1, rs2）：
  `ascon.w`(f3=0, rs1=data, rs2=word idx) 写状态字；`ascon.rd`(f3=1, rs1=idx, rd=dest) 读状态字；
  `ascon.p12`(f3=2)、`ascon.p8`(f3=3) 跑置换（多周期，perm_start 电平 + ex_stall_req=~perm_done）。
  状态字 0..9 对应 s.x[0..4] 的 32-bit 小端切片。
- 新增 src/firmware/ascon_ise_rv32/（inline asm + 完整 AEAD，code=6216 B）与 run_ascon_ise.sh。
- 关键坑：GAS `.insn r` 格式是 `opcode,funct3,funct7,rd,rs1,rs2`（funct7 在 rd 之前），
  不是 `opcode,funct3,rd,rs1,rs2`；写错会报 "bad value for funct7 field"。
- 实测（Icarus/vvp exit 0）：4 组官方 KAT(empty/1B/16B/16B+AD) 加解密 PASS、解密往返 PASS、
  tag 篡改拒绝 PASS。反汇编确认 142 条 opcode 0x0B 的 custom 指令，非静默 fallback。
- 性能（warm，仿真实测）：16B 加密 **1880 cycles**（vs 纯软件 16840 → ~9.0×，~117.5 cpb）。
  剩余开销来自状态字 load/store（每置换 20 条）与 LOADBYTES/STOREBYTES 字节搬运（未加速）。
- 未验证/未测：随机/边界/复位/连续请求的定向单元测试（I04 仅跑了 KAT 定向）；baseline 回归
  重跑（I05 只跑了 ISE 回归，未重跑软件/MMIO 全回归）；ISE-disabled 模式、中断/异常/flush
  与 ISE 交互；Vivado 综合/PPA（I08，需上板前补）。这些是 I04/I05 验收的剩余项，未标完全达标。

三级加速对比（16B 加密，均为 warm 仿真实测）：纯软件 16840 → MMIO 全卸载 544(~31×) →
ISE 置换 1880(~9×)。ISE 是 custom instruction 路径（CPU 编排、置换硬件化），MMIO 是全卸载
协处理器路径；两者互补。ISE 的编码/semantics/stall/inline-asm 落位；I03/I06/I07 已达标，
I01/I02/I04/I05 主体完成、上述未测项待补。

## 2026-10-10 — Ascon 加解密合并为统一 crypto_aead 模块

owner TBD；用户授权新建独立文件，未改现有 RTL/TB/脚本/KAT。将原独立
crypto_aead_encrypt / crypto_aead_decrypt 合并为单一 crypto_aead 模块，
用 mode(0=encrypt/1=decrypt) 选方向、共用一条状态机。关键洞察：Ascon 加
解密吸收的是同一份"明文 pad 版本"——加密直接喂输入明文，解密由 s^c 恢复
明文后吸收，故尾块 mask+0x01 逻辑可完全统一，输出恒为 s^data_in。

- 新增 src/rtl/ascon/crypto_aead.v：统一接口 clk/rst_n/start/mode/data_in/
  ad/npub/k/adlen/datalen/tag_in → data_out/tag/correct/done/busy/error。
  encrypt 输出密文+tag；decrypt 输出明文，仅 tag_in 匹配才置 correct 发布。
  17..31 长度两方向均 error 拒绝，decrypt 另保持 correct=0。
- 新增 sim/ascon/tb_crypto_aead.v：同一冻结向量同时测加解密，含逐拍
  data_out=0/correct=0 隐藏检查、tag 篡改拒绝、长度拒绝、连续调用。
- 新增 sim/ascon/prepare_crypto_vectors.py：无需 C 编译器（WSL 不可用），
  直接从锁定官方 KAT 取 289 组(PT/AD 0..16)生成 784-bit aead.mem，布局与
  既有 aead.mem 一致。
- 实测 iverilog 编译 exit0、vvp 运行 errors=0：加密 289、解密 289、篡改
  拒绝 289、长度拒绝 1470(735×2) 全 PASS；latency 空消息 34 cyc、16B 58~70
  cyc。全源集(新旧模块共存)编译 exit0、无重复 module。
- 未动 ascon_aead_2.v 及原 encrypt/decrypt，旧接口回归不受影响。合并模块
  尚未接入 CPU/ISE；Vivado/PPA/hardware cycles 仍 not_measured。

随后按用户方案 B，把 ascon_aead_2.v 的 crypto_aead_encrypt / crypto_aead_decrypt
改为实例化 crypto_aead 的薄 wrapper：端口名/方向/宽度/顺序不变，两条重复
状态机移除，底层逻辑单一来源（get_bytes 保留）。资源上，SoC 只实例化一个
crypto_aead 即可加解密复用一份，wrapper 为纯连线、综合可优化。

- 回归复验（wrapper 后）：队友 peer TB ALL PASS；加密 300 组+735 长度、解密
  310 有效+2,579 篡改+735 长度均 errors=0，数字与原 V05 一致；全源集编译
  exit0、12 模块无重复。tb_rtl_aead/decrypt 用 peer(5)+官方KAT(289)+tails(6)
  共 300 组向量（build/local/ascon_crypto/aead_full.mem）；WSL 不可用，故 peer
  ct/tag 取队友 TB 字面量、matrix 取官方 KAT 自带 expected，不重算。

下一接收：SoC 集成(I03/I05)时顶层直接实例化 crypto_aead（一个实例、mode
切换，加解密复用一份资源）；B02/B03/B04/V01 仍为在自研 CPU 运行 Ascon 前置。

## 2026-10-10 — V05/C03 功能分支提交前审查

owner TBD；用户授权在E:/amd_fpga_2026_integration将已验整合成果commit/push并创建
PR，base main；最终合并由用户确认。fetch确认main仍为0a425f9，整合分支正确。
本条记录提交前审查，不把尚未执行的push/PR写成完成；实际SHA与PR见Git历史及交付。
本轮仅更新发布审查文档/日志，RTL、TB、脚本及KAT均未改；已有PASS的源码哈希
重新核验。Encrypt所有现有实例均具名连接，无现有位置调用受追加error端口影响。
原工作区及外部备份只读核验，队友两份dirty结果不纳入；无CPU/Vivado/PYNQ改动。
提交消息feat(ascon): integrate RTL decryption and KAT validation；明确文件列表暂存，
不用git add .，不force、不推送main、不合并PR。V05/C03任务状态沿用前次实测边界。

## 2026-10-09 — V05/C03 最新main隔离整合与重新验证

owner TBD；重新fetch确认origin/main=0a425f9，独立worktree
E:/amd_fpga_2026_integration，分支feat/ascon-decrypt-kat-integration。
原E:/amd_fpga_2026保持7139a80/cleanup/remove-legacy-ascon-aead及全部28个未提交
文件。仓库外备份89文件7,636,392 bytes逐一SHA-256核验；包含队友原dirty结果。
未commit/push/创建PR/合并main；新分支不跟踪origin/main。

- 以remote为基础逐处修复，没有整文件覆盖旧本地RTL。保留队友初始化/AD、
  整块ciphertext吸收、尾块64-bit state masking/padding、P8/P12/finalization、
  full tag diff与计算tag输出；P8/P12和原队友TB逐字节未改。
- Decrypt原15端口名字/方向/宽度/顺序保持不变，无mlen/error/result新端口。
  done && correct读取接受请求的clen；认证前/失败m=0、correct=0。
  修reset/start未撤销旧认证/候选、完成后清候选；超长用correct=0拒绝。
  Encrypt追加error，所有现有具名调用兼容；整个AEAD加include guard。
- 原remote首请求busy时m/correct为X实测vvp exit1；原TBinclude+显式source编译
  exit6。首轮guard漏get_bytes编译exit2，失败全部保留，修源后重新完整回归。
- 新worktree新vector/新source：官方KAT289/289加密和解密，补充11/11；
  Encrypt311有效/控制调用、Decrypt310、篡改拒绝2,579、每方向超长拒绝735，
  全部0 FAIL；round264、P8/P12各28state比较PASS。接口具名/位置调用逐拍一致。
- 所有四个production.v编译exit0，10module无重复，全源加解密仿真exit0，
  原队友TB5组PASS。故障注入4/4，三个功能故障vvp exit1、坏向量runner exit1。
  参考全1,089 KAT gate12,936/0；软件四backend本worktree重跑28,661/0。
- 新证据rtl_integration_regression.*、rtl_integration_harness.json、
  host_integration_validation.*，记录0a425f9+实际dirty source/TB/scripts hashes，
  不是旧7139a80结果复用。工具版本/命令/退出码及保护说明见最新解密整合报告。
- 最终integration_review.json核验当前源码/验证源哈希、原28dirty和89备份未变，
  远程main仍0a425f9、diff --check exit0；暂存/提交/推送/PR为0。

V05整合子项done；C03 target仍in_progress，I03/I04/I05不因独立AEAD提升验收。
当前可供用户审查后commit/push功能分支并申请PR。本轮无Ascon仿真功能阻塞；
多块RTL、CPU/板级、Vivado、cycles/PPA仍未验证或not_measured。
下一接收B02/B04/V01/TBD→target KAT/mcycle→C04/I01/I02。下节保留先前本地历史。

## 2026-10-09 — V05/C03 standalone Ascon RTL 解密与生产全源集收口

owner TBD；基点7139a80，复用cleanup/remove-legacy-ascon-aead分支。
初始未提交rtl_regression.json/.log保留，新增rtl_decrypt_regression.*作为默认输出。
未commit/push/merge；CPU/Vivado/PYNQ/软件/锁定参考均未修改。

- 源码事实：crypto_aead_decrypt仍为空壳；35acd6a是C软件修复。
  本轮补齐RTL独立解密、完整tag认证与失败输出保护。encrypt新增error，
  加解密均拒绝物理总线不能承载的17..31-byte长度。
- before：permutation/encrypt/full-source compile PASS；runner因已删除legacy
  源路径exit1，保存rtl_decrypt_before.*。原encrypt实测17-byte请求正常done，
  长度probe simulation exit1，rtl_length_before.json保留真实失败。
- Icarus/vvp12.0：round264基础state比较PASS；P8/P12各22基础+6控制比较PASS；
  四个production.v全root编译exit0，10个module无重复；全源加解密仿真exit0。
- 官方RTL KAT：PT/AD各0..16的全部289组加密/解密均PASS，0失败；11组peer/尾零
  补充输入亦PASS。独立decrypt使用锁定expected C||T，不以encrypt反向自证。
  其余800官方组超出接口未运行RTL；完整1,089组C/Python reference gate
  12,936 PASS，软件四backend重跑28,661 PASS / 0 FAIL，均exit0。
- encrypt311有效调用；decrypt310有效调用、2,579篡改拒绝；加解密各735超长
  参数组合拒绝。每拍检查解密认证前m/mlen/result为0，失败当拍及之后仍为0。
  空/短/8与16边界/尾零、连续调用、busy-start忽略、reset中断/重新调用通过。
- RTL故障注入4/4：错误tag接受、错误明文、提前发布分别触发vvp exit1；
  损坏向量触发runner exit1。host harness 5/5通过。最终各入口exit0。
- 接口：rst_n同步低有效；start一拍；key/nonce/tag保持至done；显式length。
  decrypt新增c/tag/ad/clen/adlen与128-bit m/mlen/result/done/busy/error。
  完整契约、命令/版本/退出码/哈希与未测边界见
  docs/ascon_rtl_decrypt_validation.md、src/rtl/ascon/readme.md与results JSON/log。

看板：C01 done，C03 in_progress（target待验），新增V05 done；I03/I04真正ISE
保持todo。独立AEAD可以交付算法验证基础，但I05前置B02/V01和I02/I03仍未满足。
下一接收B02/B04/V01/TBD：CPU baseline与目标软件KAT/mcycle sanity，再C04/I01/I02。
阻塞：baseline/Vivado/固件依赖/板卡核验与CPU ISE未完成；当前Ascon仿真无功能阻塞。
Vivado综合/实现、CPU/板上、硬件cycles/speedup/PPA仍not_measured，多块RTL不支持。

## 2026-10-07 — 独立 RTL regression 提交收口

owner TBD；用户授权在 feat/ascon-kat-validation 创建
`test(ascon): add independent RTL regression`，不 push/merge。
审计原待提交 11 文件合计 190,057 bytes，最大 85,773 bytes；无重复大文件、缓存、
编译物或硬编码运行路径。结果中的绝对路径仅为实际命令证据，正式入口动态定位。
生产源/验证源与结果 hash 匹配，锁定来源/许可证完整；ignored pycache/vvp/so 不纳入。
暂存检查发现 Windows 报告换行问题，已修 runner 源输出为 LF 并重新生成/复验，
生产 RTL 不变。isolated PASS、旧接口 exit 2/full source exit 6 的 FAIL 原样保留，
整体 gate 未关闭；下一接收 RTL owner/TBD。

## 2026-10-07 — 同步最新 RTL 与独立回归追加

- owner TBD；用户授权 checkpoint/rebase。原 cba792c checkpoint 已无冲突 rebase 到
  origin/main `13d954f0755c2ec09290443e341cd5fb910fbf21`，新 checkpoint 为
  `a1d19dd7cd26da7d036d9b5612fb27f3cbf25680`。未 push/merge main；本地 main 未移动。
- 独立 C/Python 完整 KAT gate 重跑 12,936 PASS，队友五组 expected CT/tag 5/5
  与锁定 Final reference 一致；原始向量出处未记录，不能从 TB PASS 推断来源。
- Icarus/vvp 12.0：round/P8/P12 PASS，308 冻结基础用例及连续调用/reset/restart；
  新 isolated encryption 60 固定输入+9 控制请求 PASS（69 次 CT/tag 比较）。
  覆盖 mlen/adlen={0,1,7,8,9,15,16} 矩阵与尾零，没有伪造17-byte运行。
- 旧 AEAD isolated compile FAIL exit 2（reset/rst_n）；全部生产 .v compile FAIL
  exit 6（三个重复 module）。runner 整体 exit 1；isolated PASS 不等于可集成。
- decrypt=not_implemented。新 m/ad 各128 bits，目前能力上限各16 bytes。
  key 未锁存，须稳定到完成；busy-start 策略不一致、无效 c 位/empty 旧数据等
  观察与建议见 docs/ascon_rtl_regression_audit.md。

证据 `data/ascon/results/rtl_regression.json/.log`；新增入口及自己的 TB 在 sim/ascon。
生产 RTL 与 origin/main 相同，队友 TB 未修改。新回归/日志保留未提交，除授权
checkpoint 无新增 commit。看板仍不改；交接 RTL owner/TBD 修重复/接口后 I04 复验。
未做 Vivado/CPU/板级/PUF/PYNQ；硬件 cycles/PPA not_measured。

## 2026-10-07 — C01/C03 Final 标准与 host KAT 证据追加

本段为当前证据；下方 2026-09-21 表格保留历史快照。owner TBD。
初始 clean，main 从 ab458e5 fast-forward 到
`8c8634f80f55cff50ae1ffcaf6fb79d67e5a7a93`，含当天 `01 << (8*n)` padding 恢复。
创建 `feat/ascon-kat-validation`，本轮未 commit/push。

- C01：Final PDF、C/Python 固定 commit、许可与 18 文件哈希、独立完整上游 KAT
  已锁定；对照见 `docs/ascon_standard_baseline.md`。建议 done，待用户确认；看板未改。
- C02：现有 host C/Python AEAD 与 Final KAT 一致，WSL GCC 13.3 编译 C 通过。
  仍 in_progress：目标固件未编译/运行；C bad-tag 返回 -1 但留下明文和 mlen，
  failure contract 实测 exit 1。测试 adapter 丢弃输出不等于生产 API 已修复。
- C03：1,089 完整上游 KAT、64 补充 AEAD、308 permutation golden、16 短 tag 长度。
  四 backend 共 28,661 PASS / 0 FAIL，exit 0；harness 5 tests PASS。
  框架/host 子项完成，整体建议 in_progress，待 C02 前置与失败输出契约收口。
- reference gate 12,936 PASS；冻结数据重生成 byte-identical。真实 FAIL 与一次
  runner 共享库冲突原日志保存 `data/ascon/results/`；冲突已隔离构建并复验通过。
- 当前 RTL 已含完整 round、P8/P12 和 AEAD 草稿，09-21 的“只有 ror”是历史状态。
  本轮只记录长度推断/start 未接/输出截断/packed 数据推进/decrypt 空壳等问题，
  没有修改或仿真现有软件/RTL/CPU/Vivado；不能据此提升 Ixx 完成度。

证据：`data/ascon/provenance.json`、`results/host_validation.*`、
`results/failure_contract.*`、`results/audit_snapshot.json`；入口 `sim/ascon/readme.md`。
新增接口仅为独立 golden JSON/656-bit memory/CLI，生产接口未改。
硬件 cycles/PPA/RTL 功能 not_measured；接收 C02/C03/TBD，再 C04→I01/I02。

截至：2026-09-21，含 ZIP 恢复及 repository foundation 收口。owner 全 TBD；原 rename/生成元数据清理已在 fe66fd8；恢复资产已在 fc9147785cc4490b1673a0b86e16f337f256f122 本地提交。本文件随独立 foundation 文档提交保存；本轮未 push、未 merge main。初始审计基点仍为 e35d42f，不能将其误作当前开发分支 HEAD。

| 任务 / 范围 | 实际结果 | 证据 | 状态 / 局限 |
|---|---|---|---|
| B01 / D00 | 初始仓库审计、协作骨架已完成；现补充归档审计与结论更正 | docs/repository_audit.md、docs/cicc1000023_recovery_audit.md | done；审计不是功能验收 |
| B02 | Rebuild and verify recovered XC7Z020 CICC baseline；原始 XC7Z020 XPR、31 RTL/header、3 XCI、XDC/COE 恢复；活动文件引用闭合；Kintex 保留 | board/vivado_zynq7000_xc7z020_baseline；manifest 双哈希 | in_progress；未运行 Vivado/IP 再生成/综合/实现 |
| B03 | 原始 target xc7z020clg400-1、PLL 50→100 MHz、128 KiB BRAM 配置已知 | 原 XPR/XCI/XDC 与恢复审计 | blocked；target part 已确认，physical board model pending；revision/引脚适用性/PYNQ image 未核验 |
| B04 | CoreMark RV32/RV64、FreeRTOS 应用、RISC-V tests 源与构建输入共 465 文件恢复 | src/firmware/cicc1000023；原名还原脚本 | blocked；准确 kernel/bootloader 源不在所供 ZIP；未编译/加载 |
| V01 | 原始 RTL top elaboration、tb_bypass 7 项与 tb_regfile 15 项通过 | build/metadata/cicc1000023_recovery_verification.json | in_progress；ISA/Cache/AXI/中断/counter 完整回归待做 |
| 历史硬件输出 | ZIP 有 bitstream、综合/实现成功日志；100 MHz 下 WNS 0.056 ns；placed LUT 4806 / FF 3129 / BRAM 38.5 / DSP 4 | 精选 6 个报告/日志与 archive_inventory | historical_archive_evidence；有未设 IO delay，非本轮重建或实测 |
| RTL 比较 | 31 共有文件：14 字节同、17 仅换行差异；repo-only 两个 Ascon helper | docs/cicc1000023_rtl_diff.md | 没有选择哪个更新；当前 src/rtl 未改 |
| C02 | 既有 Ascon C/Python 保留 | ascon/ | in_progress；未移植或运行最终标准 KAT |
| C01/C03/C04 | 无锁定的最终标准 KAT 及板上 benchmark | 尚无相关结果 | todo；Ascon cycles/code size 均 not_measured |
| Ixx | Ascon RTL 仍只有 ror/load_bytes/store_bytes | src/rtl/ascon/ | I01-I08 todo |
| D01 / Yxx / Sxx | 当前/目标架构与待定接口已记录；PS/PYNQ/Skill 实现未开始 | docs/architecture.md、docs/interfaces.md | D01 in_progress，其余按任务表 |
| Pxx | 未开展 PUF/启动认证 | tasks/task_board.md | gated |

## 验证边界与当前阻塞

579 个恢复资产的 SHA-256 核验通过；两套 XPR/XDC、当前 RTL 与 Ascon 保持原字节。Kintex 经 git mv 归并，旧生成元数据两项已清理。文件名还原脚本成功在 ignored build/local 生成隔离工作副本；不执行原包中的安装或清理脚本。

没有运行 Vivado/Vitis、固件编译、完整 ISA、JasperGold、软件 KAT、板上测试或 PYNQ。两个模块仿真与历史 Vivado 报告分开记录。PATH 未发现相关构建工具不等于全盘无安装。

下一步：B02 重建真实 baseline；B03 核板；B04 取得准确 kernel/bootloader 来源、核验入口并适配旧测试层次；C01 锁定标准 reference/KAT。Git HEAD 缺资料用 not_in_current_repo；ZIP 已提供的资料用 available_in_archive / recovered_uncommitted，不再写成 not_available。

首次审计曾复现 top_pl_bram 缺三个 IP module 的 Icarus 报错；该历史结果保留在 repository_audit。如今 XCI 已恢复，但 XCI 不是 Icarus 可直接编译的 Verilog 模型，仍需 Vivado 生成对应产物。

foundation 收口的 579 资产分类：A source 485、B build/config input 85、C test/reference data 3、D historical evidence 6。最终 board 仅两个工程，未改 RTL、未跑 Ascon。提交准备与 Git 检查见 [收口检查](../docs/repository_foundation_closeout.md)。

## 2026-10-07 — C02 production C 认证失败输出收口

owner TBD；基线 `origin/feat/ascon-kat-validation` 的
`c34728558469f0d4e4068730801dea59e0ca2100`；分支
`fix/ascon-c-auth-failure`。本节不修改任务看板。

| 项 | 本轮真实结果 | 状态建议 |
|---|---|---|
| 原问题 | bad tag 返回 -1，但 mlen=17、buffer=原明文；原门禁 1 PASS/1 FAIL/exit 1 | 失败证据保留 |
| 扩展 raw 门禁修复前 | 15,039 PASS / 8,926 FAIL / exit 1；包括短输入保留 stale mlen | 失败证据保留 |
| production C 最小修复 | 仅 decrypt：失败清零已知候选区域并设 mlen=0；短输入仅设 mlen=0；完整 tag XOR/OR 比较保留 | host 子项关闭 |
| 修复后 raw 门禁 | 23,965 PASS / 0 FAIL / exit 0；直接读完整 buffer，检查两侧 canary | C03 软件失败输出子项 PASS |
| 四 backend host validation | 修改前后均 28,661 PASS / 0 FAIL / exit 0 | Final 固定 KAT 无回归 |
| harness/golden | 5 tests PASS / exit 0 | 错输出/假接受/hash 故障确实非零退出 |
| 加密不变 | 1,153 固定 AEAD 输入输出拼接 SHA256 修改前后一致 | encryption 无改动 |
| C01 | 锁定来源、标准、许可、KAT/hash 与软件证据已可用 | 可评审 done |
| C02 | host API 安全契约已收口；target build/port 与 B04 仍未验 | 保持 in_progress，不能 done |
| C03 | 软件验证全部 PASS；target/整体前置未验收 | 不自行 done |

实际命令、编译器/源文件哈希、前后 raw 示例、原始日志与限制见
[C API 与修复记录](../ascon/ascon_c/aead/readme.md) 和 `data/ascon/results/`。
锁定 reference、固定 expected、Python、生产 RTL/CPU/Vivado 均未修改。
目标固件、上板、cycles/PPA、buffer overlap/异常指针/超大长度与全面 timing proof
未验证或 not_measured。下一接收：C02 target/B04 → C03 target KAT → C04 real
mcycle，owner TBD；RTL integration/decrypt blocker 仍由 RTL owner 处理。
