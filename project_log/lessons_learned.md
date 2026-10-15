# 经验与踩坑

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
