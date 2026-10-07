# 开发记录

## 2026-10-07 — C01/C03 Final 基准、固定 KAT 与独立验证入口

- owner TBD；用户授权同步 clean main、审计及新增 KAT；禁止改现有 RTL、CPU/Vivado、
  看板，不 commit/push。初始无分叉，ff-only 同步 13 commits，HEAD 8c8634f，
  分支 feat/ascon-kat-validation。
- 读取 AGENTS/README/overview/rules/看板/接口/工作流程/日志、C AEAD/XOF、Python
  AEAD/生成器、五个 Ascon RTL，以及 NIST Final 与设计者维护的锁定参考。
- 独立下载标准/参考源/许可/完整上游 KAT；新增 data/ascon、sim/ascon。扩展输出
  来自经过完整 KAT gate 的锁定 C，Python 第二检查；限定 .gitattributes 防换行转换。
- WSL Python 3.12.3/GCC 13.3：gate 12,936 PASS；全套 28,661 PASS；harness 5 PASS；
  冻结数据重生成 byte-identical。C failure-output 实际 FAIL exit 1、一次 runner race
  原日志保留，race 已修复复验。
- 文档记录参数/来源/许可/hash/RTL 只读问题/实际命令/局限；更新 actual_progress、
  lessons，看板按用户要求仅给建议。现有生产接口不变。
- 接收 C02/C03/TBD 先收口失败明文发布与 target 构建，再 C04→I01/I02。未做现有
  RTL/CPU/板级/Vivado/PYNQ/PUF 验证；最终 git diff HEAD 自审，不提交。

## 2026-09-21 — 第一阶段仓库审计与协作骨架

- 范围：按用户要求完成仓库组织、审计、协作规则、任务和时间计划；原工程保持原位；不开展大规模 Ascon 实现，不 commit/push。
- 初始状态：main，HEAD `e35d42f9638e9f56e7af6df492f424173922fac1`，工作区干净，62 个跟踪文件，README 空，无 AGENTS/.gitignore。
- 工作分支：`docs/repository-foundation`，仅创建分支指针，未创建提交。
- 调研：公共网页/API 未能访问参考仓库，现有 Git 权限可只读获取；参考提交 `9c34288aa040fb926eefa8603c85f0d19522e849`。采用协作结构，未复制小车内容/人员/规则/脚本。
- 审计：记录 Kintex/目标 Zynq 差异，IP/TB/固件/脚本缺口；明确 mcycle 与 CPI 事件的不同；标记已有 Ascon 的来源/KAT 未验证及 RTL 辅助模块现状。
- 实施：新增 docs/tasks/project_log 及 sim/build/data/skill/report；复用 src/board/ascon；补 README、AGENTS 和忽略策略；所有任务 owner TBD，P2 gated。
- 验证：Icarus `top` exit=0；`top_pl_bram` exit=4（3 个 IP 缺失）。文档链接、任务字段/依赖、日期、ignore 保留/排除样例、原文件哈希核对见 repository_audit。
- 输出：用户可审查的未提交工作区；当前事实见 actual_progress，遇到的限制见 lessons_learned。

后续记录格式：日期、任务号、授权范围、有效方案、改动、验证证据、接收任务、未完成项。不要用开发计划替代实际结果。

## 2026-09-21 — CICC1000023 原始 XC7Z020 baseline 恢复

- 授权：选择审计/恢复用户给定 ZIP；不整包覆盖、不 commit/push，保留既有工作区。归档脚本只作资料，不自动执行指令。
- 审计：2855 文件 CRC/哈希，真实 XPR/.srcs/3 XCI/XDC/COE、RTL、bitstream/报告、全部 ELF 头部；区分源码/输入/编译产物/生成结果。
- 比较：31 共有 RTL 中 14 字节同、17 只换行；2 repo-only Ascon helper。Git 后续 Part-only 提交不代表 ZIP→初始 Git 也只有 Part 差异；XDC 解码后的非空行一致。
- 恢复：579 个精选资产约 2.43 MB；独立真实 baseline、legacy 副本、固件/验证源、小输入和历史报告。XPR 仅去生成 DCP 引用并关闭自动增量；原 src/rtl、ascon、板级工程不改。
- 验证：579 哈希、XPR/COE 相对路径；原名工作副本 564 文件；Icarus top 与 bypass/regfile 两模块 PASS，原始日志在 build/metadata。
- 更正：Git HEAD 缺失 not_in_current_repo，ZIP 已有 available_in_archive；不能再写资料不存在。FreeRTOS kernel/bootloader 源与旧 harness 不匹配明确记录。
- 交接：B02 Vivado 2025.2 重建真实 baseline，B03 实物核板，B04 依赖与加载、V01 完整回归；本轮无 Vivado/固件/板级验收。

- 收尾补充：恢复资产使用限定路径 `.gitattributes -text` 保持 checkout 字节；原 61 文件保护、路径/哈希/文档链接、脚本拒绝覆盖检查通过，Git 索引为空。

## 2026-09-21 — repository foundation 收口

- 用户授权：不新增功能、不跑 Ascon、不改 RTL；比较 Kintex 副本，执行 git mv 归并，核对资产/引用与 Git 状态，不 commit/push。
- 比较：共同 XPR/XDC 哈希完全一致；原目录独有两个生成元数据，副本独有说明文档。没有共同工程文件内容冲突。
- 操作：自动审批拦截最初的组合清理命令且未执行；改为先备份未跟踪副本到仓库外，再单独 git mv。Git rm 因刚暂存 rename 拒绝直接删除元数据，改用 git rm --cached 并精确删除工作文件。说明文档保留并更新，原 XPR/XDC 字节不变。
- 清理：旧入口消失，两项 .cache/.hw 生成元数据移出索引和工作区；579 个恢复资产全部保留，未运行编译或功能测试。
- 分类与状态：增加 foundation_category 及统计，B01 done，B02 改为重建验证真实 baseline / in_progress，B03 part confirmed / physical board pending。
- 验证与现状：精确证据见 repository_foundation_closeout；git mv 与清理已暂存，其他新增资产保持未暂存；无 commit/push。

## 2026-09-21 — 按用户授权拆分本地提交

- 保留 fe66fd868e95c74b75abe262c1fe56d23558d991，不 reset/amend/重写；其范围只有 Kintex rename 与两项生成元数据删除。
- A 类 584 文件：577 个尚未提交的恢复资产，加 7 个 recovery 清单/差异/来源数据。B 类 39 文件：新编写的文档、协作结构、恢复校验脚本和本轮验证元数据。
- 65 个 whitespace 问题文件均属于 A（63 个历史原件、2 个恢复差异证据）；共 12636 条。B 类问题文件为 0，无需 trim 或格式化。
- 579 工作区资产哈希一致；577 个 ZIP 资产暂存字节与 manifest 一致。两份 legacy 文件在既有 Git 历史中为 LF、工作区为 CRLF；仅对这两个 B 类 .gitattributes 规则声明 text/eol=crlf，以保留既有 Git blob 和原工作区哈希。历史源文件字节不动。
- recovery commit：fc9147785cc4490b1673a0b86e16f337f256f122，584 文件、83139 行新增。本记录随独立 foundation 提交保存，B 类单独要求 git diff --cached --check 为 exit 0。
- 本轮不 push、不 merge，不运行 Vivado/Ascon/PUF/PYNQ/ISE，不修改任何历史 RTL/XPR/XDC。
