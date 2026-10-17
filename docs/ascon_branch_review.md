# Ascon 分支有限审查

2026-10-17，owner TBD。使用Matt Pocock `code-review` 工作流，规范与需求两个独立只读agent，
均未编辑源码、运行Vivado或长回归。固定点origin/main=`c37ecae4bba050d833079d56f8aec05365637aad`，
受审HEAD=`2b48a8a730267787b399fe06304ae5e2b53ff203`；命令`git diff origin/main...HEAD`。
Tracker为[PR4](https://github.com/HChenZ/amd_fpga_2026/pull/4)，需求来源为用户任务及密钥/接口文档。

## Standards

发现1项P2：原`sim/ascon/summarize_timing_review.py:61–65`仅遍历已有快照文件并用all判定，
缺失或空目录得到空集合，all为True；部分缺失时也只检查余下文件，可能将缺失实现证据标为匹配。
违反AGENTS的缺失证据不得冒充完成、technical_rules的数据证据要求。
现有真实快照完整，因此此问题不否定已保留的实现结果。

未发现其他文档规范违例或值得整改的Fowler代码异味；HDL FSM与清零分支不应按通用OO建议重构。

修复：提取`checked_rtl_snapshot`门禁，要求目录存在、期望RTL非空、`.v/.vh`文件集合完整且
逐字节hash一致，才返回成功。5项测试覆盖匹配、缺失、空、部分缺失和内容改变。
修复前3项失败/exit1，修复后5项通过/exit0；真实快照和六组CPU输入复核通过。
规范审查agent只读复核修复后确认原P2已关闭，无新发现。

## Spec

0项可确认的新缺陷、遗漏或越界实现。核对了MMIO START/BUSY/ZEROIZE/失败门禁、ISE非法完整
索引/模式/完成保持/cancel、同步返回前失败输出擦除及长度0、部分密文Tag指针、动态黄金密钥。
失败时不清理容量未知的历史尾部、无并发DMA契约、缺少完整抢占ABI和物理抗提取证明均已明确限定。
100 MHz负WNS如实记录，符合用户允许阶段性提交的边界。

审查agent独立重算全部LF规范化源码hash，未发现不匹配，六组CPU报告PASS。

规范轴：1项P2，已关闭；需求轴：0项。该有限代码审查不替代HDL回归、STA或实际板卡测试。
