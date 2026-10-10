# Ascon 最新 main 只读审计与独立 RTL 回归

本文件保存2026-10-07历史审计；decrypt空壳、旧文件与integration FAIL描述不代表
2026-10-09的当前工作区。最新功能/接口/全源集门禁见
[解密整合验证](ascon_rtl_decrypt_validation.md)，基于最新main 0a425f9保留队友
接口并重新运行；历史失败证据继续保留。

2026-10-07（Asia/Shanghai）；C03/I04，owner TBD。
远端 main 为 `13d954f0755c2ec09290443e341cd5fb910fbf21`，包含
`f0e5b58941ab8eb01ab1d622607aa0aafc0104eb` 的新 AEAD/TB，以及 permutation 的 rst_n 改动。

## Git 与提交前审计

初始 feature branch 在 8c8634f，有本轮 C01/C03 未提交工作。按用户授权建立
checkpoint `cba792ce5f18acb915d459263882e17827c1294a`：
`test(ascon): add NIST final KAT validation baseline`，48 文件。
fetch 后 rebase 无冲突，checkpoint 改为
`a1d19dd7cd26da7d036d9b5612fb27f3cbf25680`。没有 push/merge main；本地 main 指针未改。

应提交的文件是标准文档、KAT/来源/hash/许可、验证脚本/结果、限定 attributes 与项目日志。
不能提交 build/local 构建物、复生成/审查临时文件、备份、ignored __pycache__/pyc。
待提交路径无 .o/.so/.dll/.exe/.vvp/pyc。原 4.60 MB 文件集合中无同 hash 副本；
最大的规范 PDF 为 1,194,488 bytes，完整 host 日志为 1,166,101 bytes，各有明确用途。
旧 race 日志从 899,834 bytes 无损压缩到 63,504 bytes，原文 hash 和本地原文备份保留。
整理后原工作约 3.76 MB；逐文件大小/哈希见 `data/ascon/results/precommit_audit.json`。

正式脚本用 __file__ 定位 ROOT，WSL 复现示例改为 wslpath 动态路径。历史报告/本机
实际命令中的 E:/、/mnt/e/ 是证据，不是运行依赖。18 个下载资产 hash 与双 CC0
许可证核验通过。初始 git diff --check 通过；checkpoint diff 默认诊断含 CRLF 和
锁定上游空 PT/AD 字段的尾空格；CRLF-aware 检查的剩余诊断只属于锁定 KAT/README，
不修改原件来消除这些诊断。编写内容无额外 whitespace 问题。

## 五组 expected 的独立核验

来源基准见 [ascon_standard_baseline](ascon_standard_baseline.md)。prepare_rtl_vectors.py
重新让锁定 ascon-c/pyascon 完整 KAT gate 通过（12,936 PASS / 0 FAIL），之后读取
队友 TB 的**输入与 expected 常量**，用锁定 C 算法重算 expected，并由锁定 Python
交叉检查。TB 里的 expected 不参与 reference 计算。

所有 byte 串为实际输出顺序，RTL 128-bit 打印整数相当于 byte 串反向显示。

| TB case / AD bytes / PT bytes | reference ciphertext | reference tag | 原 expected |
|---|---|---|---|
| V0 / 0 / 0 | 空 | `4f9c278211bec9316bf68f46ee8b2ec6` | PASS |
| V1 / 8 / 8 | `e8d7762ad728d554` | `d9864ed5ade9d7d0d2c6ee04d10c87a2` | PASS |
| V2 / 16 / 16 | `526a65fe4d8b60d095e5ddf0190c0252` | `1c7764985dc64b09af80183338db4928` | PASS |
| V3 / 15 / 15 | `7c426dea5e8078892a2cf2aa77695d` | `42b10ecf7972f13d14bafefd75b89e00` | PASS |
| V4 / 5 / 3 | `5565e8` | `5bdc7bb143acc7ec32b2a30fc4f98486` | PASS |

TB 源和 f0e5b58 commit message 没有标明向量生成器/URL/标准版本，所以**原始来源仍为
not_documented**；不能从 ALL PASS 反推来源。现在五组数学结果都有独立 Final reference
证据，原输入、原 expected、逐字段 diff、TB source hash 在 rtl_regression.json。

## 实际执行与覆盖

原队友 TB 保持原样。新增自己的 sim/ascon/tb_rtl_permutation.v 和 tb_rtl_aead.v。
准备命令在有 GCC 的 WSL 中，仿真使用 Windows PATH 中 Icarus/vvp 12.0：

```powershell
$asconWslRoot = (wsl -d Ubuntu -- wslpath -a $PWD.Path).Trim()
wsl -d Ubuntu -- python3 "$asconWslRoot/sim/ascon/prepare_rtl_vectors.py"
python sim/ascon/run_rtl_regression.py
```

准备 exit 0。runner 整体 exit **1**，因为它必须包含失败的 whole-source integration
gate，不能用 isolated PASS 代替完整源集成功。每个实际 iverilog/vvp 命令、版本、
退出码、编译输出、每项 PASS/FAIL 在
`data/ascon/results/rtl_regression.json` / `.log`。临时 memory/vvp 和 reference gate
详细 log 在 ignored build/local/ascon_rtl，可由上述命令复建。

| gate | 实测结果 | 退出码 |
|---|---|---|
| 独立 reference 证实 peer expected | 5/5 PASS | 准备 0 |
| round/P8/P12 | 264 round + 22 P8 + 22 P12 frozen cases PASS；重复调用、reset abort/restart、busy-start restart 观察通过 | compile 0 / vvp 0 |
| isolated ascon_aead_2 encryption | 60 组固定输入+9 次 control/restart 请求 PASS；69 次各比较有效 ciphertext 与完整 tag | compile 0 / vvp 0 |
| 原队友 TB（未改） | ALL PASS；结果已由上方独立检查，而非自证 | compile 0 / vvp 0 |
| 旧 ascon_aead interface | reset 不存在于新 p8/p12 端口 | compile/elaboration 2 |
| 完整生产 source-set | 重复三个 module，无法 compile | compile 6 |
| decryption | 两个版本皆只有空壳 | not_implemented，不运行解密并冒充 AEAD PASS |

AEAD 的 60 组 = peer 5 + `mlen/adlen={0,1,7,8,9,15,16}` 笛卡尔积 49 + 冻结尾零 6。
输入的未使用 bytes 加 a5 poison，验证长度确实控制吸收；ct 只比 mlen 有效 bytes，
tag 比全部 16 bytes。显式包括一字节 00、a500、8/15/16-byte 尾零。
只执行能力内的 <=16-byte 输入，**没有伪造 17-byte 通过结果**。

额外请求：非空→空→非空连续 start、busy 中注入新的 start/消息输入（被忽略）、
三个运行时刻 reset abort 后重启。P8/P12 同一实例无 reset 连续调用，运行时 reset
后重启。done pulse 和 busy 在接收/完成时的值也检查；watchdog/首不同 byte/
$fatal(1) 保证失败非零。实测接受请求到完成的 P8=9、P12=13 clocks；
AEAD 所测组合=34/46/58/70 clocks。这是仿真延迟，不是板上 mcycle benchmark。

完整生产 gate 将 ascon 目录**所有生产 .v**一起编译：ascon_aead.v、ascon_aead_2.v、
ascon_permutation.v、ascon_round.v、ascon_word.v；仅排除作为激励的 *_tb.v。
constants.vh 通过 include/-I 进入。使用 -g2012；已有 guards 使本轮 include 未产生
额外 round/pad 重定义。真正冲突是两个 AEAD 文件声明同名 modules；file 名不同
不能消除 module 冲突。旧 reset 问题另用 isolated legacy compile 证实，避免被
重复 module 错误掩盖。所有生产源与 origin/main 相同，未修改任何 RTL。

## 问题、行号与建议

行号基于上述 origin/main。确定的算法结果与接口观察分开：

| ID | 路径/行号 | 问题 / 实际观察 | 建议（只报告） |
|---|---|---|---|
| R20 | src/rtl/ascon/ascon_aead.v:7,241,263；ascon_aead_2.v:7,303,325 | crypto_aead_encrypt、crypto_aead_decrypt、get_bytes 重复；full compile exit 6 | RTL owner/TBD 明确唯一生产实现、旧实现隔离入口或 module 命名策略，附 full source regression |
| R21 | ascon_aead.v:44-45；ascon_permutation.v:10,76 | 旧 .reset 不存在，新 rst_n/start 未连接；legacy compile exit 2 | RTL owner 统一旧/新 source-set 与端口契约，不靠排除旧文件声称全源集通过 |
| R22 | ascon_aead_2.v:11-16,206,256,267 | m/ad 各128 bits，无数据流/块推进。5-bit length 可编码17..31，但没有相应数据容量/拒绝错误 | 当前范围明定 PT/AD<=16；加输入校验或多块接口，之后才测17及更长数据 |
| R23 | ascon_aead_2.v:303-323；ascon_aead.v:241-261 | decrypt 无功能/验证/输出驱动，reset 仍为旧命名 | not_implemented；实现完整解密/拒绝/不发布失败明文后验收 AEAD |
| R24 | ascon_aead_2.v:32-33,177-178,273,280 | key 未锁存，初始化后与 final 继续使用 live K0/K1；busy 中换 key 实测 tag 不再等于 start 时请求 | 规定 key 必须保持到 done，或锁存 key；当前 stable-key encryption PASS 不覆盖输入捕获契约 |
| R25 | ascon_permutation.v:54-57,116-119；ascon_aead_2.v:162-173 | p8/p12 busy-start 会 restart；AEAD busy-start 被忽略。仿真证实两种政策不同。start 持续高时 permutation 会持续重新加载 | I02/接口文档明确 pulse/start 接收条件、busy 请求政策、reset/取消与中断语义 |
| R26 | ascon_aead_2.v:267,285-290 | partial c 输出全128-bit状态，超出 mlen 位未屏蔽；empty after nonempty 时 c_reg 未清，bus 保留上一结果。mlen=0 无有效 ciphertext，本轮未把无效位计为算法 mismatch | consumer 只读取 mlen bytes；建议 mask/清零无效输出以免误序列化或暴露无效状态 |
| R27 | ascon_aead_2.v:142-157；ascon_permutation.v:44-51,106-113 | rst_n 是同步低有效 reset；AEAD c 输出未在 reset 中赋值，只有 c_reg/tag/busy/done 等 reset | 写明同步 reset 和输出有效条件；若要求 reset 后 c 已知/为零，需要独立修正与验证 |
| R28 | src/rtl/ascon/ascon_aead_2_tb.v:29,66-68 | wait(done) 无 timeout；errors 非零也只打印并 $finish，可能进程 exit 0 | 队友 TB 后续加 watchdog/$fatal；本轮独立 wrapper 另解析失败标记并限时，自己的 TB 已严格非零 |
| R29 | ascon_aead_2_tb.v:55-63；f0e5b58 commit message | 没有 expected 来源/标准/reference commit/hash | 引用本锁定 provenance 与 peer case 审计，保留 independent reference 证据 |
| R31 | src/rtl/ascon/ascon_aead.v:13,27-28,135,147-156,171,176,205-211,225-237,263-278 | 旧版仍按非零数据推导长度、packed 数据用加法推进、AD=8 pad 分支不对、短 PT 驱动错误 pad 输入、同拍旧值依赖、64-bit c/tag覆盖等；先前只读发现仍存在，但最新旧入口无法 elaboration，所以没有声称功能仿真证实 | 对照标准基准文档 R01/R03/R04/R05；明确 legacy 保留/隔离策略后由 RTL owner 单独处理 |

key probe 为 **接口行为观察**：改变忙期间输入并非已冻结合法协议，不把它计为 stable-key
算法 FAIL，也不假装已实现 start-sampled key。reference tag 为
a2870cd104eec6d2d0d7e9add54e86d9，改变 key 后为 1f4d8d6cd7faa1be816012747f799998。
短3-byte ciphertext 物理 bus=43d4ff632e0f3e61db97dac50de86555，只 5565e8 三 bytes 有效；
下一 empty 请求 bus 保留同值，但有效长度0。这些观察在原始日志保留。

## 结论与交接

encryption 在 stable key、<=16-byte、单拍 start、同步 rst_n 的**所测集合**通过独立
Final reference。decrypt=not_implemented；full production integration=FAIL，不能标可集成。
此前 C raw failure-output 问题仍未修复；C02/C03 全项目状态建议不变，看板未编辑。
接收 RTL owner/TBD 处理 R20/R21 与协议/能力定义，再交 I04 重跑同入口。
上述回归阶段结束时，新验证及审计保留为未提交 workspace 改动；随后用户明确授权
以 `test(ascon): add independent RTL regression` 提交这些文件。提交前审计原11文件
约190 KB、最大约86 KB，无编译物/缓存/重复大文件；正式入口无机器路径依赖。
原验证结果/source hash 与来源许可核对通过，FAIL 原样保留，不 push/merge。
提交收尾检查发现 Windows 报告换行诊断；修 runner 源输出为 LF，重新生成同一
regression 证据并复验，未修改生产 RTL、用例或 expected。暂存 whitespace 检查须通过。
无 Vivado/CPU 接入/板级/PUF/PYNQ 工作；硬件 cycles/PPA 仍 not_measured。
