# 决策记录

## ADR-017 accepted — 已提交简介固定；高级功能按独立阶段验证（2026-10-29）

- 用户说明此前贴出的简介仅用于接手，已不能修改；不以本地新简介候选替换已提交文本。
- 本轮要求DMA/PUF实现验证方案与计划表，不代表授权执行任何不可逆硬件安全配置。
- 推荐DMA先接RV32 uncached endpoint以保留三模式主线，多块核/直连加速另阶段。
- PUF先修采样失败传播与旧key有效状态，再做AEAD内部key使用证明；持久化诊断与保密重建分开验收。
- 日期仍按11-01提交冻结；新计划未执行，已有报告/简介/生产代码/发布物本轮保持不动。

## ADR-016 accepted — 2026-10-29 当前提交范围与日期重订

- 依据：用户本轮明确要求 2026-11-01 实际提交并冻结，取代先前内部日期。
- 主线：当前已实板验证 RV32/PYNQ、PT/AD 各 ≤16B、SW/HW/ISE；固定 release 身份。
- 扩展：保留已实现的独立 RO-PUF/DNA 原型；v3 同次上电 quality=128/128 与重建状态通过。
  不称其为跨上电稳定、保密隔离或完整安全启动，不把扩展 RO 时序状态套到当前 PYNQ。
- 尚未实现的 DMA、多块硬件/大消息与独立核 PPA 不作为本次成果或承诺。
- 10-30 优先验证实际交付 Skill；额外跨算法/跨平台/小时级实验非阻塞，未做项保留 not_measured。
- 允许必要交付代码与缺陷修复，需相应验证；不默认改动当前 bit/固件，不自动提交或推送。
- 原完整任务验收记录不抹除；本轮交付以 `tasks/release_plan_20261101.md` 为准。

更新：2026-09-21。记录已授权的工程规则与待定设计，不能以文档决策代替实现验证。

| ID | 状态 | 决策 / 原因 | 后果与关联任务 |
|---|---|---|---|
| ADR-001 | accepted | 复用 CICC1000023 CPU，先恢复 baseline，再扩展 Ascon ISE | B02/B03/B04 前置；本轮不动原 RTL/IP/XPR/XDC |
| ADR-002 | accepted | 现有 src、board、ascon 原位映射；新增协作文档与未占用目录 | 保留 Vivado 相对路径；路径异常记录到审计，D05/D06 再处理发布问题 |
| ADR-003 | accepted | Ascon-AEAD128 以 NIST SP 800-232 final 为准 | C01 锁定参考/KAT；当前 C 1.3.0 与 draft README 只视为待验证线索 |
| ADR-004 | accepted | 第一期 inline asm/intrinsic，不改 GCC backend | I06 提供反汇编和执行证据；自动编译优化后置 |
| ADR-005 | accepted | P0→P1→P2；PUF 与启动认证受门禁控制 | 10-21 前置节点通过且主线稳定才评估，不能侵占冻结/材料窗口 |
| ADR-006 | accepted | 任务/日期/实际事实/失败记录分离；所有 owner TBD | 避免文档宣布尚未验证的成果；人员由项目方分配 |
| ADR-007 | accepted | build 保留脚本与精选报告，忽略临时输出；已跟踪生成文件本轮保留 | 不以 ignore 代替历史清理；清理前保证可再生 |
| ADR-008 | accepted | baseline 新配置与迁移验证隔离，main 维持可构建目标 | 已有 Kintex/XC7Z020 差异需 B02/B03 解决，不直接改 part |
| ADR-009 | pending | 具体板卡/revision/PYNQ image、Zynq IP/约束和 firmware loading | B03/Y01 定案后记录依据和验证版本 |
| ADR-010 | pending | ISE 指令粒度、RV32 状态表示、编码与流水行为 | 等 C04/I01 热点数据；由 I02 给出可测试 spec |
| ADR-011 | pending | PS/PL 用 AXI/shared BRAM/mailbox 的最终实现与内存一致性 | Y01 给出版本化协议和 buffer 生命周期 |

更新模板：日期、任务号、状态、问题、可选项、决定、依据链接/证据、影响接口、下游验证。accepted 表示方案约定，不表示代码已完成。

## 2026-09-21 — 原始比赛归档恢复

- ADR-012 accepted：以 ZIP 的真实 XC7Z020 XPR/XCI/XDC/COE/imports 恢复 baseline，不新造空工程。原 Kintex 与当前 RTL 保留；共有 RTL 无换行外差异，不判断哪个更新。
- ADR-013 accepted：保留 .srcs 层次，仅去除生成增量 DCP 依赖；先检查活动引用再复制。Kintex 同深度复制到 legacy，原路径不移动。变更与双哈希见恢复 manifest。
- ADR-014 accepted：选择恢复软件/测试源与构建输入、两个 add HEX、bootloader COE 和精选历史报告；不批量导入 ELF/生成目录。小写存储名通过隔离还原脚本映射回原名，避免静默重写源码。
- ADR-009 更新：原 Zynq IP 参数、XDC、初始化已找到；具体板卡兼容性、PYNQ image 与可重建 firmware loading 仍 pending。历史成功不代替本轮重建。

## 2026-09-21 — foundation 收口取代临时双入口

ADR-015 accepted：用户明确授权比较后去重。XPR/XDC 字节相同，legacy 副本从工作区移出并在仓库外备份；使用 git mv 将原 tracked 工程统一到 legacy，同深度保留相对引用。ADR-002/013 中“原路径不移动”属于之前临时保护策略，本次授权取代该限制。删除原两项 cache/hw 生成元数据，原件有 Git HEAD 和外部备份；不改 RTL/XPR/XDC。

579 资产按用途新增 foundation_category，保留原归档 A/B/C/D 分类作为 provenance。B02 改为 Rebuild and verify recovered XC7Z020 CICC baseline；B03 target part confirmed，physical board model pending。foundation 提交可记录恢复与组织工作，不等于 B02/B03 验收通过。
