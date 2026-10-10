# 实际进度

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
