# Ascon RTL 解密整合与重新验证

> 2026-11-01：本页记录10-09独立RTL整合，接口合同与当时证据保留；“最新main/未CPU/未板测”按该日期解读。
> 当前PUF3系统层结果另列于 version_entrypoints.md，不能用独立RTL通过替代系统验收。

2026-10-09（Asia/Shanghai）；V05/C03；owner TBD。
新分支feat/ascon-decrypt-kat-integration基于重新fetch确认的
`0a425f9f0ed36e0c2666552b87a9173e79ffca0e`。2026-10-09验证结束时未commit/push/PR/merge。
本报告是整合后源码的验证；7139a80上的先前本地PASS不作为本次通过证据。

## 保护与整合

原工作区E:/amd_fpga_2026保持原分支、HEAD和全部28个未提交文件不动。
仓库外备份E:/amd_fpga_2026_backups/20261009_ascon_integration_eb072953保存
89文件、7,636,392 bytes、逐文件SHA-256、binary diff、index diff与状态快照，
全部核验。包括队友原有dirty的rtl_regression.json/.log，未带入新工作树。
新worktree为E:/amd_fpga_2026_integration；新分支未跟踪origin/main以免误推送。
绝对路径仅为本轮审计信息；脚本从__file__定位，没有硬编码运行路径。

13个非RTL文件以7139a80为共同基点三方整合，先规范化文本CRLF/LF；
新增独立TB/harness/接口文档导入后适配。生产AEAD从远端逐处修改，约40余行差异，
没有用旧本地整个RTL文件覆盖远端。CPU/Vivado/PYNQ/软件/参考/KAT/golden未改。
新worktree .git定位改为相对gitdir，兼容Windows/WSL；原worktree定位未改。

## 两版区别和保留内容

| 项 | 远端队友实现 | 此前本地实现 | 整合选择 |
|---|---|---|---|
| 解密接口 | tag_in、tag输出、correct/done/busy，15端口 | tag输入、mlen/result/error | 原15端口名字/方向/宽度/顺序完全不变 |
| 初始化/AD/域分离/P8/P12/finalization | 已有完整状态机 | 同类状态机 | 保留远端调度及连接 |
| 整块与尾块 | ciphertext替换rate；64-bit尾块mask/pad保留未消费state | 128-bit tail mask | 保留远端正确表达式及状态 |
| Tag认证 | diff=tag_in XOR {s4,s3}，输出计算tag | 内部完整比较 | 保留diff和计算tag；只有if比较通过才发布m |
| 候选/认证状态 | reset/start不初始化m/m_reg/correct | reset/start清除 | 移植初始化、撤销旧成功、完成清候选 |
| 超长拒绝 | 无 | 显式拒绝 | Encrypt追加error；Decrypt用correct=0拒绝 |
| 原TB include | include整个AEAD文件 | 旧本地TB无include | 原TB逐字节保留；整个AEAD加include guard |

解密不增加mlen/error/result或wrapper：done && correct才是成功，读取接受请求的
clen bytes；correct=0时有效明文长度为0。tag仍输出计算值，包括认证失败。
加密error末尾追加，现有具名调用兼容；caller需要检查done && !error。
key/nonce/tag_in保持至done；clen不含tag；成功输出无效位不强制为0。
完整契约见[RTL接口](../src/rtl/ascon/readme.md)。

## 真实失败与修复证据

- 环境首次setup失败：Windows绝对gitdir无法被WSL Git读取、三方文本换行适配。
  调整新worktree相对定位及合并输入换行后解决；rtl_integration_setup_failure.*保留。
- 远端修复前decrypt compile exit0，首个请求busy时m=X/correct=X，vvp exit1。
- 原TB include与显式AEAD源码同时编译exit6（三个重复module）；
  rtl_integration_before.json/.log记录远端source hash与失败命令。
- 首轮guard漏包get_bytes，peer compile exit2、overall exit1；扩大至整个文件修复，
  rtl_integration_guard_failure.json.gz/.log.gz无损保存。不排除生产模块掩盖错误。

## 重新运行命令与结果

在新worktree根目录执行：

```powershell
wsl -d Ubuntu -- python3 sim/ascon/prepare_rtl_vectors.py
python sim/ascon/run_rtl_regression.py
python sim/ascon/test_rtl_harness.py
wsl -d Ubuntu -- python3 sim/ascon/run_validation.py --report data/ascon/results/host_integration_validation.json
```

最终入口均exit0。Windows Python3.14.3；WSL Python3.12.3/GCC13.3.0；Icarus/vvp
12.0(devel)(s20150603-1539-g2693dd32b)。编译-g2012 -Wall -I src/rtl/ascon，
全生产编译不限制top。实际命令/退出码/版本/HEAD与dirty源码、TB、脚本哈希见
data/ascon/results/rtl_integration_regression.json/.log。

锁定Final参考未改：ascon-c446347f...、pyascon ed24e54...；KAT SHA-256
bbbc34692fe05e5fda0a3b025585622ab3e3747495e5e3655b29aae8c2a4bd33。
本worktree重新准备向量，两个参考先过全部1,089 KAT及负向门禁12,936 PASS/0 FAIL；
独立Decrypt读取expected C||T，不以RTL Encrypt→Decrypt自证。

| 整合后的验证 | PASS / FAIL |
|---|---|
| 官方KAT | Encrypt289/289、Decrypt289/289，0失败；同一批289组，PT/AD各0..16 |
| 补充输入 | 11/11两方向；peer5、固定reference尾零6 |
| Encrypt有效与控制调用 | 311通过、0失败 |
| Decrypt有效与控制调用 | 310通过、0失败；计算tag逐位匹配黄金值 |
| 篡改拒绝 | 2,579通过、0失败；tag/CT/key/nonce/AD；逐个翻转128个tag和CT bit |
| 超长拒绝 | 每方向735组合通过、0失败；5-bit范围任一长度17..31 |
| Round / P8 / P12 | Round264；P8/P12各22基础+6控制比较通过；seed0x800232 |
| 全production编译/仿真 | 四个.v、10 module无重复；compile及加解密simulation exit0 |
| 原队友TB | 原文件未改，5组PASS、compile/run exit0 |
| Decrypt接口兼容 | 原15端口逐项相同；具名/位置调用全TB逐拍一致 |
| 故障注入 | 4 PASS/0 FAIL；错tag接受、错明文、提前输出分别vvp exit1；坏向量runner exit1 |
| 本worktree软件四backend | 28,661 PASS/0 FAIL/exit0；全1,089官方与补充/置换/负向 |

认证前逐拍m=0/correct=0；失败完成及下一拍仍m=0/correct=0。空、短、8/16边界、
尾零、连续调用、busy-start忽略、done pulse与reset后调用均覆盖；reset在
3/25/45/60/69 cycles且先断言busy，最后一点在认证发布前。请求timeout200cycles，
独立TB均watchdog/fatal；失败入口非零；完整性检查不用可被python -O禁用的assert。

新证据名称为rtl_integration_regression.*、rtl_integration_harness.json、
host_integration_validation.*；没有将旧报告改名为本次PASS。软件完整log无损gzip。
最终[审查清单](../data/ascon/results/integration_review.json)核对所有当前source/TB/
script哈希、原28dirty及89备份、原队友未改文件、远程main未前进、白空格与修改范围；
该2026-10-09审查快照的暂存、commit、push、PR均为0。
2026-10-10用户授权提交/推送功能分支并创建PR；当前源码与证据的发布前核验见
[发布审查](../data/ascon/results/publication_preflight.json)，最终合并由用户确认。

## 限制与交接

其余800官方KAT超出16-byte接口，未声称RTL通过；多块未实现。>=32长度须在
缩窄5-bit前拒绝。现有P8/P12 busy-start restart，AEAD ignore，契约已明确。
相同timescale继承提示不影响功能。Vivado综合/实现、CPU/板级、cycles/PPA/Fmax/
speedup仍not_measured。独立AEAD不是已验CPU ISE/SoC。
V05整合子项done，C03 target仍in_progress。下一接收B02/B04/V01/TBD，先CPU
baseline、target软件KAT/mcycle，再C04/I01/I02→ISE。当前可供人工审查后提交、
推送功能分支并申请PR；2026-10-09仅整合验证，2026-10-10按用户授权发布。
