# Ascon 密钥生命周期审查

> V10 留存更新：本文的安全契约保留；早期 Vivado RPT 曾被清理，随后并行会话恢复了部分报告，
> 用户确认暂时保留。具体存在/删除范围及数据复验结论见 [清理说明](workspace_cleanup.md)。

2026-10-16（Asia/Shanghai）；V06 / C03 / I04 / I05 / B02；owner **TBD**。
审查基线 `c37ecae4bba050d833079d56f8aec05365637aad`，分支 `fix/ascon-key-lifecycle`。
原工作区及其未提交改动保留；本轮在独立 worktree 工作。用户明确授权检查通过后 commit/push，禁止合并 main。

## 标准及测试边界

规范为 [NIST SP 800-232 Final](https://csrc.nist.gov/pubs/sp/800/232/final)，
2025-08-13 发布，2026-10-16 重新核读。正文 §4.1 与 §4.3 R2/R3：本项目使用
128-bit Key、128-bit Nonce、完整 128-bit Tag；同一 Key 的每次加密必须使用不同 Nonce。
规范 [PDF](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-232.pdf) 与
仓库锁定参考的来源/hash 见 `data/ascon/provenance.json`。

三份 main.c 的固定 key/npub 数组仅用于官方 KAT/公开性能测试，**不是安全部署密钥**。
算法与 MMIO 驱动均接收运行时 Key/Nonce 指针，不依赖这些全局测试数组。
本次不更改官方 KAT、固定预期、参考算法或许可；新增普通测试逐次传入参数。
`prepare_key_vectors.py` 先使锁定 C/Python 参考通过全部 1,089 官方 KAT，再交叉核对
3 组不同公开 Key、不同 Nonce、9 组长度（共 27 例）；MMIO 使用其中 21 例。
这些额外向量是独立参考派生数据，不能称作 NIST 发布向量或认证。

禁止把真实密钥放入源码、日志、Git、COE 或 bitstream；当前全部测试输入均公开且无保密价值。
生产 C 的 `ASCON_PRINT_STATE` 调试宏会输出密钥/内部状态，真实使用时必须关闭。
运行时传参能力不等于已有上位机或 PS/PL 输送链路；当前仅有裸机函数与仿真自测入口。
未来请求应显式携带模式、16-byte Key/Nonce、输入/AD 长度、输出容量、请求标识和完成码。
板型、传输与所有权协议须在 Y01 冻结，不假设 PS/PL 已可用。

Nonce 由调用者管理。软件易失计数器不能保证跨重启唯一；持久化、掉电原子分配、
同一 Key 的多设备域划分、回滚处理都需要额外设计。本轮不实现计数器、TRNG、PUF、
KDF、安全启动或密钥保险库。

## 已确认问题与处理

| 路径 | 源码/测试发现 | 最小修复 |
|---|---|---|
| 软件 C | 返回失败时已有候选擦除，但成功/失败后的本地 state、K/N 副本和计算 Tag 未主动擦除 | 增加 volatile 字节擦除；不改变 AEAD 数学或原失败契约 |
| MMIO | KEY0..3 小端更新及 START 锁存正确；Key 不可通过原 KEY read case 读出 | 保留映射与 KEY 写序，不把测试固定值当漏洞 |
| MMIO | BUSY 可改写输入缓冲；OUT 无 busy/fail/长度门禁，能读旧结果/尾字，指针可越界 | BUSY 忽略写；按成功完成和有效字数发布；尾字无效字节置零；指针有界；START/失败撤销历史输出 |
| MMIO | DONE 后 key_r/run_key、适配器/置换状态和缓冲仍在；reset 未初始化所有缓冲 | 空闲 ZEROIZE 清除所有相关副本；复位同时清除；保留显式重用直到 ZEROIZE 的语义 |
| MMIO | 错 Tag 时 TAGOUT 返回新计算 Tag，给调用者不必要的认证信息 | 失败 TAGOUT=0；OUT=0，无历史明文或计算 Tag 发布 |
| MMIO 固件 | le32 读取部分尾字时会越过调用者字节长度；32-bit 超长可能被寄存器截断 | 按剩余字节装载；超长在缩窄前编码为拒绝请求，跳过数据读取 |
| ISE C | 候选明文先写入应用缓冲，验 Tag 失败仅返回 1；无输出长度 | 失败返回 -1，mlen=0，volatile 擦除已知候选区域；成功才设置长度 |
| ISE C | 非整块解密未将 c 移过最后的部分密文到 Tag 起点 | 增加 c += clen；1/7/8/9/15/17-byte 独立黄金测试覆盖 |
| ISE RTL | 10..15 index 读为 X，CPU 高位索引会别名到低4位；运行中可覆盖 state，模式未锁存 | 非法完整索引读0/写忽略；运行时写忽略，锁存模式 |
| ISE/CPU | 完成脉冲遇下游 hold 可能丢失并重入；提前译码未包括 custom 操作数，旁路/load-use 失效 | done 保持到 EX 真正推进的 ack；补齐 if_id 的 rs1/rs2 enable |
| ISE 清理 | state 和 P8/P12 内部副本残留 | 软件用现有 ascon.w 写零10字；置换私有副本空闲自动复位；trap/interrupt cancel 清除且不发布迟到结果 |

修复前本机 GCC 13.2 构建的 ISE 官方自测和新增动态测试确实失败，不能沿用队友 GCC 15.2
记录的成功。旁路遗漏导致不同编译布局触发不同表现；不是换编译器绕过缺陷。

## MMIO 现行接口

基址仍为 `0x30000000`，32-bit 字访问，低地址为低有效字节；KEY0=bytes[0..3]，
KEY1=bytes[4..7]，KEY2=bytes[8..11]，KEY3=bytes[12..15]，Nonce/Tag 相同。
ADLEN/MLEN、KEY/NONCE/TAGIN、AD_WDATA/MSG_WDATA、OUT_RDATA/TAGOUT 地址不变。

| 寄存器 | 语义 |
|---|---|
| CTRL bit0 | START，仅空闲接受；锁存方向、长度、Key/Nonce/Tag；清除旧输出/完成位，复位缓冲指针 |
| CTRL bit1 | ENCRYPT=1，加密；=0，解密，保持已有定义 |
| CTRL bit2 | 新增 ZEROIZE，仅空闲接受，同一写中优先于 START；写 4 即可 |
| STATUS bit0/1/2 | BUSY/DONE/FAIL 保持原定义；DONE/FAIL 保持至下次 START/ZEROIZE/reset；正常完成 IRQ 一拍 |
| KEY/NONCE/TAGIN 读 | 返回0；未定义地址读0 |
| OUT_RDATA 读 | 仅 DONE && !BUSY && !FAIL 且未超出有效字数时返回并推进；其余返回0，不推进 |
| TAGOUT | 成功完成结果；START/失败/ZEROIZE/reset 清零 |

BUSY 时包括 ZEROIZE、START、Key/Nonce、长度、输入缓冲在内的所有写均忽略。
不会提前删除当前运算仍需要的 key。写完 ZEROIZE 后读 STATUS，应得到0；注册化 core_clear
在随后时钟清除子模块，顺序 MMIO 读提供同步点；清零期间须保持时钟运行。无异步取消命令；超时应复位外设/系统。

ZEROIZE 清除 key_r/nonce_r/tagin_r、run_*、长度/计数/状态/读寄存器、全部 AD/MSG/OUT
数组，并通过子核心复位清除适配器 key/state/缓冲、AEAD s0..s4、候选明文、p12_in/p8_in
和 P8/P12 s_reg/s_out。DONE 本身不等于 ZEROIZE：应用取完结果后须执行清理。
Key/输入在没有重新写或 ZEROIZE 时允许显式重用，兼容原 START-only benchmark；
它不提供“每请求新密钥”或 Nonce 唯一性保障。

硬件实际只支持消息和 AD **各 0..16 bytes**。256-byte 参数/数组不是多块能力；
超长显式 FAIL。软件/ISE 可处理多块，本轮测试到32 bytes，不宣称无限长度或指针安全。

## ISE 现行约定与生命周期

RV32，custom-0 opcode 0x0b，funct7=0：f3=0 ascon.w（rs1数据、rs2索引），
f3=1 ascon.rd（rs1索引、rd结果），f3=2 P12，f3=3 P8。10个32-bit字按 s0低/高、
s1低/高……s4低/高排列。没有新增 opcode。软件 inline asm 保持 volatile，不修改 GCC。
非法 word index（完整输入寄存器不在0..9）读0/写忽略；这不是非法指令异常。
保留的其他 opcode/funct 编码与 CPU 全局非法指令陷阱审计尚未完成。

复位 state=0。写字在 EX 未 hold 且未被 trap/interrupt 杀死时提交；P8/P12 锁存选择，
运行期间禁止写入和重入，done 保持直到指令推进，CPU stall 跨过完成不会再次执行。
普通 branch flush 清除较年轻的流水指令；被取消的置换不会在后来覆盖新状态。
trap/interrupt 取消会丢弃并清零 ISE state，**没有任务上下文保存/恢复 ABI**。
当前 bare-metal 自测不启用抢占；真实中断、多任务、嵌套调用的完整算法恢复尚未验证，
调用者须串行独占/禁止抢占或在 abort 后重启整个 AEAD，不能直接从中间一轮续算。

每次 ISE AEAD 返回前写零10个状态字并擦除本地 state、K/N、计算 Tag；
P8/P12 私有副本在 idle 清零。CPU寄存器、编译器额外副本、栈历史、cache、
调试/JTAG、DMA/其他总线主机、物理探测和侧信道不在本清零证明范围内。
不宣称抗侧信道、故障攻击或 FPGA 物理防提取。

## 软件失败输出契约

纯 C：clen 含16-byte Tag，成功返回0/mlen=clen-16，失败-1/mlen=0。
ISE 内部 helper：clen **不含**紧随其后的16-byte Tag，新增最后一个 uint32_t *mlen；
成功0/mlen=clen，失败-1/mlen=0。它是当前裸机文件内 helper，不是安全的网络解析 API。
调用者必须保证 Tag 存在、有效指针、充足容量、无重叠，并先检查返回值。

两种软件实现允许在函数执行中暂写候选明文，失败返回前清除整个已知候选区域。
这与项目 C 参考失败契约一致；应用不得并发读该缓冲，异步共享/DMA 场景需另设私有暂存。
容量未知，因此不会越过本次候选长度擦除历史尾部；返回长度0时应用不得消费旧尾部，
需要擦除整个复用对象的调用者应按自己的 capacity 清零。短输入 C 不产生候选，保留原契约。
MMIO 则在 START/失败清除整个 OUT 数组，且认证前硬件读门禁禁止发布。

## 自动验证入口及证据

所有原始结果/工具版本/命令/退出码见 `data/ascon/results/key_lifecycle/`，大日志可 gzip。
其中 before/中间 FAIL 不被删除；优化前结果见 `validation_summary.json`，续接最终结果见
`final_validation_summary.json` 与 [100 MHz时序审查](ascon_timing_review.md)。
Windows native Python + Icarus，C/GCC 使用 WSL Ubuntu；Linux 可直接运行 Python。

```text
python3 sim/ascon/run_validation.py --report data/ascon/results/key_lifecycle/host_after.json
python3 sim/ascon/check_failure_contract.py --report data/ascon/results/key_lifecycle/c_failure_after.json
python3 sim/ascon/prepare_rtl_vectors.py
python3 sim/ascon/prepare_key_vectors.py
python sim/ascon/run_rtl_regression.py --report data/ascon/results/key_lifecycle/rtl_final.json
python sim/ascon/test_rtl_harness.py --report data/ascon/results/key_lifecycle/rtl_harness_after.json
python sim/ascon/run_key_rtl.py
python sim/ascon/run_cpu_units.py
python sim/ascon/run_cpu_regression.py --mode sw --label final
python sim/ascon/run_cpu_regression.py --mode hw --label final
python sim/ascon/run_cpu_regression.py --mode ise --label final
python sim/ascon/run_cpu_regression.py --mode sw --security --label final
python sim/ascon/run_cpu_regression.py --mode hw --security --label final
python sim/ascon/run_cpu_regression.py --mode ise --security --stall --reset --label final_verified
```

`run_ascon_sw/hw/ise.sh` 保留为上述完整源集 runner 的入口，--cc-prefix/--iverilog/--vvp 可配置。
与队友历史结果使用不同 GCC 和清理代码，周期不能混算成新的纯算法加速比。
所有 CPU cycle 属 RTL **simulation**，频率模型50 MHz；没有本轮硬件实测。
原始 CICC baseline、官方 KAT、锁定参考逐字节保护；见最终源哈希与资产校验。

## Vivado 与接收门禁

使用 `build/build_ascon_review.tcl`，在 `build/local/` 复制真实恢复工程和当前开发 RTL，
保留 XCI/COE/XDC，防止覆写或自动升级原工程。顶层 top_pl_bram、part xc7z020clg400-1、
Vivado 2025.2；三个 IP 版本和编译源集在 `build/reports/ascon_key_lifecycle/build_context.txt`。
将开发 .v 显式按 SystemVerilog 解析。原 COE 仍是 FreeRTOS，不是当前 Ascon 固件映像。
优化前综合和布局布线均完成（命令exit0），但100 MHz不通过：布线后WNS=-1.641 ns、
TNS=-607.794 ns、LUT11683/FF15960/BRAM38.5/DSP4。原始报告仍保留在
`build/reports/ascon_key_lifecycle/`，它们对应优化前源码。

续接按用户授权消除尾块宽移位/减一进位链，保留FSM和延迟；第一轮功能回归全部通过。
随后针对CPU/cache路由主导路径进行第二轮物理实现优化，保持RTL和约束不变。
**两轮精确结果、100 MHz是否收敛及剩余路径以 [时序审查](ascon_timing_review.md) 为准**，
最终源码、报告和CPU测试哈希见 `final_validation_summary.json`，不得沿用旧RTL的时序数字。

DRC含PS7缺失、BRAM异步控制、DSP寄存和规则报告数量上限，Methodology另有LUT派生复位告警；
这些问题不能由RTL仿真或单纯正WNS豁免。3个输入/3个输出缺少IO delay，既有reset_btn
false path保持原样，板级约束覆盖仍不完整。上板门禁未通过，未生成bitstream；
没有单独软件/MMIO/ISE三套等条件PPA比较，也不从WNS直接声称Fmax。
生成缓存、DCP、bitstream不提交。

借板后的检查顺序见 [上板清单](ascon_board_checklist.md)。下一接收 B02/B03/V01/I08/Y01，owner TBD。
任何芯片级实现通过都不等于实际板级验证；不得在板型未知时套用 PYNQ-Z2 引脚或烧录。
