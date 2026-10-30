# RTL design discipline Skill 验证停止记录

日期：2026-10-30

状态：`STOPPED_INCONCLUSIVE`

历史结果保留在：

- `data/skill/results/20261030_rtl_discipline_g0/`
- `data/skill/results/20261030_rtl_discipline_g2/`
- `data/skill/results/20261030_rtl_discipline_g3/`
- `data/skill/results/20261030_rtl_discipline_g4_g5/`
- `data/skill/results/20261030_rtl_discipline_g6_g8/`

## 保留的有效事实

- 一个显式提供 Skill 的独立生成会话生成了 `counter8`。
- 生成 RTL 通过冻结 TB 和固定 seed 功能测试。
- load/clear 优先级故障注入被冻结 TB 拒绝。
- 恢复原始 RTL 后 hash 不变并重新通过。

## 复核发现的问题

1. G0 模型身份记录与实际 G3/G6 会话不一致：原始会话为
   `deepseek-flash / deepseek / reasoning=max`，G0 却记录为 OpenAI Codex/GPT-5。
2. 无 Skill 对照仍收到“按加载的 RTL design discipline”的提示词，A/B 存在方法暗示混杂。
3. Testbench 与参考模型由同一主会话编写，只做到对生成会话隐藏，未做到作者独立。
4. G0 冻结 prompt v1，而实际生成使用补模块名后的 prompt v2，版本链未在单一 manifest 中统一。
5. 完整原始会话轨迹未进入公共证据，公共目录仅有人工整理的摘要。
6. 仅验证一个简单非密码 counter，未覆盖 Skill 针对的复杂嵌套、补丁式修改和多优先级场景。
7. 未测试自动 Skill discovery；只验证了显式提供文本内容。
8. 未综合，LUT/FF/latch/时序改善均为 `NOT_MEASURED`。
9. 单次 A/B 两组都通过，不能证明 Skill 带来功能或质量收益。

## 结论

不再继续该 Skill 的验证，也不在报告、PPT 或视频中宣传 Skill 已带来资源或广泛质量提升。
历史运行结果可作为“一次受限功能样例”保留，但不得替代通用 Skill 验证。

## 清理

- 已删除仓库外隔离 oracle、G3/G6 生成工作区。
- 已删除仓库 `build/local` 中的未脱敏原始副本和临时 validator 虚拟环境。
- 保留 `data/skill/results/` 中已脱敏的验证结果及哈希。
