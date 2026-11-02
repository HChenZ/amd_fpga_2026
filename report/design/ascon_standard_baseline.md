# NIST Final Ascon-AEAD128 标准基准与验证审计

本文件是 `feat/ascon-kat-validation` 的历史标准审计，软件/RTL 问题与测试数字
固定到下面注明的审计 HEAD，不代表本分支的当前失败状态。C02 production C 的
认证失败修复及最新实测见 [软件 API 与修复记录](../../ascon/ascon_c/aead/readme.md)。

日期：2026-10-07（Asia/Shanghai）。任务 C01/C03，owner TBD。
HEAD：`8c8634f80f55cff50ae1ffcaf6fb79d67e5a7a93`；分支 `feat/ascon-kat-validation`。
现有软件、Ascon/CPU RTL、Vivado 工程、tasks/task_board.md 均未修改；未 commit/push。

## 1. 规范、参考来源、版本与许可

唯一目标为 **NIST SP 800-232 Final / Ascon-AEAD128**，August 2025。
[NIST Final 发布页](https://csrc.nist.gov/pubs/sp/800/232/final) 的发布历史为
2025-08-13；[规范 DOI](https://doi.org/10.6028/NIST.SP.800-232)。
本地 [Final PDF](../../data/ascon/sources/nist_sp_800_232.pdf) 的 §3、§4.1 算法 3/4、
附录 A（整数/字节与 padding）、附录 B 表 14 为本轮算法依据。
采用 byte 输入、完整 128-bit tag；不采用 truncation 或 nonce masking。

主参考为设计者维护的
[ascon/ascon-c 固定版本](https://github.com/ascon/ascon-c/tree/446347f21b209f3921c65ece70027c366cbe1693)，
commit `446347f21b209f3921c65ece70027c366cbe1693`，上游路径
`crypto_aead/asconaead128/ref/`。锁定 README 明确对应 NIST SP 800-232 并链接 Final。
最小可编译原件放在 `sim/ascon/reference/ascon_c/`，额外
`tests/crypto_aead.h` 映射到该目录，LICENSE 映射到 `license.txt`，所有原始字节保留。

独立下载的固定 KAT 为同一提交的
[LWC_AEAD_KAT_128_128.txt](https://github.com/ascon/ascon-c/blob/446347f21b209f3921c65ece70027c366cbe1693/crypto_aead/asconaead128/LWC_AEAD_KAT_128_128.txt)，
保存为 `data/ascon/kat/asconaead128.txt`。这是 **Ascon 官方上游 Final 算法 KAT**，
不是 NIST 认证结果。全部 1,089 组：PT/AD 长度 0..32 的笛卡尔积。
key、nonce、PT、AD、expected CT 全部来自原文件；没有用仓库 genkat.py 自证。

第二参考为设计者维护的
[meichlseder/pyascon 固定版本](https://github.com/meichlseder/pyascon/tree/ed24e54abf9507d26fa49b46a56091570c7e743e)，
commit `ed24e54abf9507d26fa49b46a56091570c7e743e`，`ascon.py`。
其 README **仍写 initial public draft**，所以不凭文案认定 Final。
核对 AEAD 参数并通过完整锁定 Final KAT 后才作为第二参考。
本轮不为其 Hash/XOF/MAC 或其他历史 variant 作合规结论。

下载日期 2026-10-07。[provenance.json](../../data/ascon/provenance.json) 记录
18 个文件的精确 raw URL、commit、原路径、本地路径、字节数与 SHA-256。
两个上游许可均为 **CC0-1.0**，原文分别保存在
`sim/ascon/reference/ascon_c/license.txt` 和 `sim/ascon/reference/pyascon/license.txt`。
NIST PDF Authority 声明在美国不受版权保护并请求署名。不将这些许可扩展为
整个仓库的许可，也不凭相似代码认定历史本地文件最初来源已证明。

| 关键资产 | SHA-256（原始文件字节） |
|---|---|
| NIST Final PDF | `1be9bb9a5fef3665ee8b258babe54b8e500d667fcfbbcc99710fe6077c6bad27` |
| 完整上游 KAT | `bbbc34692fe05e5fda0a3b025585622ab3e3747495e5e3655b29aae8c2a4bd33` |
| 固定 AEAD JSON | `a059447af720e6ac38811e4b7be0f4163e57aa9cd2dda1e7005367a055d703e8` |
| permutation JSON | `9ec18891c762be1f55611430a0b3d2f66221c058d761f33e13e79a41aa2f594e` |
| RTL golden memory | `5f3c8321daa298cbd8ca0632ce6d34a52360ba9e5309a64456fc61b26d0ed30f` |

参考源/header/许可证逐文件哈希见 provenance；派生数据哈希见
[derived_integrity.json](../../data/ascon/derived_integrity.json)。`.gitattributes` 仅新增
data/ascon、sim/ascon/reference 的字节保留规则和新测试脚本 LF 规则，防止 checkout
换行转换破坏哈希；已有工程与 RTL 规则不变。

旧 Ascon v1.2 Ascon-128/128a 的端序、IV 与 Final 不同，不能移用旧 KAT。
本地 C 的 `1.3.0`、`ASCON_128A_*` 命名和 Python draft README 仅提供线索，判定
以 Final 参数和独立 KAT 为准。`ascon/ascon_c/xof/` 实为 CXOF 路径，已读但未测。

## 2. 参数与逐项对照

“静态匹配”只表示源码表达式一致，不能替代 RTL 功能验证。

| 项 | NIST Final byte 配置 | 本地 C (`ascon/ascon_c/aead/`) | 本地 Python (`ascon/pyascon/ascon.py`) | 当前 RTL (`src/rtl/ascon/`) |
|---|---|---|---|---|
| Key | 16 bytes / 128 bits | api.h=16；K0/K1 little-endian | encrypt/decrypt 要求 16 | k[127:0]；低 64 bits=K0，静态匹配 |
| Nonce | 16 bytes / 128 bits | api.h=16 | 要求 16 | npub[127:0]；低 64 bits=N0，静态匹配 |
| Tag | 完整 16 bytes / 128 bits | CRYPTO_ABYTES=16 | finalize 输出 16 | 宏 16；实际输出不足，R03 |
| rate/capacity | 128/192 bits；rate=16 bytes | ASCON_128A_RATE=16 | rate=16 | 宏 16；输入只容纳一个块 |
| IV | integer `0x00001000808c0001`；bytes `01008c8000100000` | constants 位移式相同 | initialize byte 串相同 | constants 位移式静态相同 |
| Ordering | little-endian；第一 byte 在 word[7:0]；无 bit reversal | LOADBYTES/STOREBYTES | bytes_to_int/int_to_bytes 为 little | load/store 低 byte 映射匹配，消息推进 R04 |
| Padding | 追加 byte `01` 后填 `00`；word 为 `1 << (8*n)`，n<8 | PAD(i)=SETBYTE(0x01,i) | AD/PT 的 01；解密 mask 保留未消费 state bytes | word.v:10 已为 01；AEAD 尾块错误 R05 |
| 完整块边界 | 非空 AD 整块后仍需空 padded block+P8；PT 整块后仍需空 padded tail | 循环/尾块匹配 | 显式 padded tail 匹配 | FSM/握手尚未功能验证 |
| 空 AD | 不 absorb/pad AD；仍执行 domain separation | if(adlen)+DSEP | if len(AD)>0+DSEP | 跳转意图相同，但长度推断 R01 |
| Domain separation | `s4 ^= 0x8000000000000000` | DSEP() 同值 | S[4]^=1<<63 | DSEP 宏静态相同 |
| P12 | 初始化/结束 12 rounds；`f0 e1 d2 c3 b4 a5 96 87 78 69 5a 4b` | P12/ROUND 相同 | permutation 最后 12 RC 相同 | p12 RC 静态相同；start 未连接 R02 |
| P8 | 数据块 8 rounds；`b4 a5 96 87 78 69 5a 4b` | P8 相同 | permutation 最后 8 RC 相同 | p8 RC 静态相同；接口 R02/R07 |
| Round | RC XOR s2 低 byte；S-box；ROR 对 `(19,28),(61,39),(1,6),(10,17),(7,41)` | ROUND 匹配；golden 比对通过 | permutation 匹配；golden 比对通过 | 已有完整 S-box/diffusion，静态匹配；本轮未仿真 |
| Key injection | 初始后 s3^K0/s4^K1；final P12 前 s2^K0/s3^K1，后 s3^K0/s4^K1 | 匹配 | 匹配 | 表达式意图匹配；时序未验 |
| 输出 | C 与 P 等长；T=LE64(s3)\|\|LE64(s4) | C\|\|T 拼接 | C\|\|T 拼接 | c[63:0] 截断、GET_TAG 覆盖 R03 |
| 解密失败 | fail；应用不得使用未认证明文 | -1；但 buffer/mlen 保留候选明文 S01 | bad tag 返回 None；短 tag assertion | decrypt 空壳 R06 |
| 长度 | AD/PT 显式长度；允许尾零、多块 | unsigned long long 显式长度 | bytes 长度 | get_bytes(value) 推导长度 R01 |

Final §3 定义最多 16 rounds：表 5 的前四个 RC 为 `3c 2d 1e 0f`，之后为上述
P12 序列。本次只验证 AEAD 需要的单 round/P8/P12，不声称支持任意 round 数。
Python rounds<=12 不阻止本轮 AEAD 验证。

## 3. 固定数据、自动入口与 golden 接口

采用用户指定 data/ascon（数据/证据）、sim/ascon（验证/隔离参考），符合仓库约定。
没有向既有软件或 RTL 目录插入适配代码。完整上游 1,089 组 KAT 逐字节检查。
额外 aead_cases.json 共 64 组：54 组上游矩阵选择（PT=0/1/7/8/9/15/16/17/32，
AD=0/1/15/16/17/32），10 组锁定 C ref 扩展，包括 `00` 与空串、`a5` 与 `a500`、
15/16/17-byte 尾零、33/64/129-byte PT 和最长 81-byte AD。
每组保存显式 byte 长度、ciphertext、16-byte tag 和首/尾 CT/tag 翻转输入。
CT 为空时仅翻转 tag；单 byte 的首/尾 CT 翻转相同但分别记录。

freeze_vectors.py 先让两个锁定参考通过完整独立下载 KAT 的 encryption、decryption、
negative gate，再由锁定 C 产生扩展、Python 交叉检查。只写新的空输出目录，
不会覆写上游 KAT。普通 run_validation.py 不调用生成器、不更新 expected。
两次重生成三个数据文件及 integrity 文件字节完全一致。

permutation 数据为 22 个输入状态：zero/ones/byte ramp/首末 bit/交替位，以及
固定 seed `0x800232` 的 16 个随机状态。各有 12 个单 round RC、P8、P12，共
308 组，源自锁定 C helper，Python 二次检查。不是自写算法自证。
`c_bridge.c` 只导出所选 C helper，不实现密码运算。
JSON 与 656-bit `$readmemh` 数据、任意 state 的 `GoldenModel().permutation()`、
round/P8/P12/AEAD CLI 的契约见 [sim/ascon/readme.md](../../sim/ascon/readme.md)。
RTL bus 为 `{s4,s3,s2,s1,s0}`，expected byte 串为 LE64(s0)..LE64(s4)，不要混淆。
AEAD golden 读取固定 case 的独立 expected C||T；不生成未冻结的任意 AEAD 输出。

## 4. 实际验证、命令与局限

环境：WSL Ubuntu Python 3.12.3、GCC `13.3.0 (Ubuntu 13.3.0-6ubuntu2~24.04.1)`；
Windows Python 3.14.3 用于下载/哈希/Git 审计。C 编译 flags：
`-std=c99 -O2 -Wall -Wextra -Werror -shared -fPIC`，两套 C 编译 exit 0，无警告。
完整编译命令及源/header/bridge/binary SHA-256 见结果 JSON。

以下为本机历史实际命令（证据，不是写死路径的复现要求）；可移植入口及动态
WSL 路径转换见 sim/ascon/readme.md。脚本从 __file__ 计算仓库根目录：

```powershell
wsl -d Ubuntu -- python3 /mnt/e/amd_fpga_2026/sim/ascon/run_validation.py
wsl -d Ubuntu -- python3 /mnt/e/amd_fpga_2026/sim/ascon/test_harness.py
wsl -d Ubuntu -- python3 /mnt/e/amd_fpga_2026/sim/ascon/check_failure_contract.py
wsl -d Ubuntu -- python3 /mnt/e/amd_fpga_2026/sim/ascon/freeze_vectors.py --output /mnt/e/amd_fpga_2026/build/local/ascon_frozen
wsl -d Ubuntu -- python3 /mnt/e/amd_fpga_2026/sim/ascon/freeze_vectors.py --output /mnt/e/amd_fpga_2026/build/local/ascon_frozen_recheck2
```

| 验证 | 实际 PASS/FAIL / exit | 证据 (`data/ascon/results/`) |
|---|---|---|
| 两个锁定参考的完整 KAT gate | 12,936 PASS / 0 FAIL / exit 0 | reference_gate.json/.log |
| 四 backend 全套 | 各 7,165 PASS；加完整性检查合计 28,661 PASS / 0 FAIL / exit 0 | host_validation.json/.log |
| harness/golden 接口 | 5 tests PASS / exit 0 | harness.log |
| C raw failed-decrypt API | 1 PASS / 1 FAIL / exit 1 | failure_contract.json/.log |
| 冻结数据重生成 | 4 文件 byte-identical / exit 0 | audit_snapshot.json |

每个 backend 检查 1,089 官方+64 补充 AEAD case、首/尾 CT/tag 篡改、16 种短 tag
长度 0..15、308 个 permutation case。加密与解密分别比较；解密读取固定 expected
C||T，而非刚产生的 actual ciphertext。首个不同 byte 显示 0-based offset、expected/
actual；长度差异显示 `<end>`。失败、缺编译器、hash 不符、异常均非零退出。
harness 注入错 byte、假接受 bad tag、hash 故障，实际检查非零退出，另外验证
4 种 golden CLI 和 memory mapping。故障只在子进程内注入，不改锁定文件。

C test adapter 丢弃失败候选 plaintext，但不修复生产 API。因此另外测试 raw C
输出并保留真实 FAIL：bad tag 返回 -1、mlen=17、buffer 等于原明文。
短 tag 的 Python assertion 在测试 adapter 中算拒绝；不是生产输入校验 wrapper。
没有测 timing resistance、buffer aliasing/超大长度、目标固件、RTL/板级/周期/PPA。

一次并行 reference gate/validation 共享临时 `.so` 导致 upstream-c setup FAIL，
不是算法 mismatch；原日志 runner_race_before_fix.* 保留。已改每调用独立临时
目录，相同并行场景与完整 suite 复验通过。NIST PDF 初次 urllib HTTP 403，浏览器
可读，增加 User-Agent 后实际取得 PDF/hash；没有伪造缺失来源。

## 5. 只读问题与建议

行号固定到本轮 HEAD。R01-R07 为静态观察，未声称产生失败波形；S01 为软件实测。
后续队友改 RTL 后须重新定位并做功能验证。所有 RTL 均保持原样。

| ID | 文件/行号 | 原因与建议 |
|---|---|---|
| R01 | src/rtl/ascon/ascon_aead.v:27-28,263-278 | get_bytes 用最高非零 bit 推导长度；00 被认为空，a500 被认为 1 byte；16-byte 输入不支持多块。建议显式长度/分块，用 extended_00/01/02 和尾零/多块用例 |
| R02 | ascon_aead.v:44-45；ascon_permutation.v:11,77 | p12/p8 需要 start，AEAD 实例未连接；无法启动 busy 路径。建议请求/接收/完成握手与 busy 时 start 规则 |
| R03 | ascon_aead.v:13,225-237 | c 只有 64 bits，GET_TAG 两次赋值覆盖，无独立 tag/长度/done；不能返回完整 C\|\|16-byte T。建议输出/流接口及有效时序 |
| R04 | ascon_aead.v:135,171,176 | packed 数据加 rate/8 不等同 C 指针推进；s1_load_in 用 m_reg+8，不是第二 64-bit slice。建议明确 block/byte 索引，测 full/multi-block |
| R05 | ascon_aead.v:147-156,205-211 | AD=8 走 s0 pad 分支，shift 64 丢 pad，应填 s1；短 PT 设置 s1_pad_in 却读 s0_pad_out；新 load 参数同拍读取旧输出。建议 >=8 分支、正确 pad 输入与时序，测 7/8/9/每个尾长 |
| R06 | ascon_aead.v:241-261 | decrypt 仅声明，无 tag verify/输出驱动。建议实现并测篡改拒绝、失败明文发布规则后才宣称 AEAD RTL 完成 |
| R07 | ascon_permutation.v:54-57,116-119 | start 在 busy 时覆盖状态；这是现有行为，规范未冻结，不能直接判为算法错误。建议 I02/I04 明确 restart/ignore/error、连续请求/reset/latency |
| S01 | ascon/ascon_c/aead/aead.c:141,207,222,232,255-266 | bad tag 实测 -1 但 mlen=17、buffer=明文。建议 C02 调用层丢弃/擦除失败输出、有效长度归零，或经另行授权修 API |
| S02 | ascon/pyascon/README.md:5,25；锁定上游同样 | 仍写 draft；不能凭文案证明 Final。AEAD 已有完整 KAT 证据，后续文档引用本锁定结果，不扩展到其他 variants |

## 6. 看板建议、接收任务与未测项

任务看板按用户要求不改；owner 均 TBD。

| 任务 | 建议 / 前置 |
|---|---|
| C01 | 可审查后标 done：Final、C/Python commit、许可/18 文件 hash、独立完整 KAT、逐项对照齐全 |
| C02 | 保持 in_progress：host 编译与 KAT 通过；raw failure-output 契约未收口，target/RISC-V 构建/运行与 B04 未验证 |
| C03 | 验证框架与 host 子项完成；整体建议 in_progress，暂不 done：C02 前置未验收、失败不得返回可用明文的项目契约仍 FAIL |
| I01 | 看板 prerequisite C04：同平台软件 KAT、真实 mcycle、反汇编与热点周期证据，不能以 host KAT 代替；cycles=not_measured |
| I02 | C01 输入已可用；仍需 I01。明确 opcode/spec/semantics、RV32/64 state/端序、latency/stall/flush/reset/异常/中断、寄存器约束与测试矩阵 |

下一接收 C02/C03/TBD：先收口 authenticated-decrypt API 与 target build，再 C04→I01/I02。
RTL 队友可立即消费 golden，但 I04/CPU 集成仍需完整功能和流水回归。
本轮没有 Vivado、RTL/CPU 仿真、目标固件、板级 benchmark、PPA、PYNQ、PUF 结果。
这些是 not_measured。host KAT 通过不是 NIST 认证或整个 SoC 已合规的证明。
