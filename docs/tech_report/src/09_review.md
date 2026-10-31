## 定稿审查清单 {.unnumbered}

本文件为内部检查单，不进入五部分正式稿。

- 本次主线：RV32/PYNQ、PT/AD 各 ≤16 B、SW/HW/ISE；独立 RO-PUF 原型单章展示，不混入当前 overlay。
- 最新安排：11 月 1 日提交并冻结；额外通用性、长时可靠性实验非阻塞，但不能伪报通过。
- 当前主性能表只用 KAT #529 的 30 次 warm 采样；历史 PL-only 数据单列。
- CPU 周期与 PS 墙钟分别标注；WNS、资源与 DRC 明确 top、run、工具及工件身份。
- host 1089 与板级 289 分列；17 B 返回 LENGTH 不计为标准长消息通过。
- error-gate 已执行 ipynb 已归档；warm benchmark 的执行结果存在，本体仍待补。
- 正面实物照片已在 figs/board_photo.jpg；补核心芯片丝印、背面、跳线、SD 镜像与现场运行说明。
- 小时级稳定性、独立频率、板上 ISA、完整异常矩阵、通用 Skill 和 clean-clone 不伪报完成。
- 重新生成 src_template → report.md/index.html → LaTeX → PDF/上传包；检查旧图预渲染缓存。
- 本轮不 commit/push，不更改 release/RTL/固件，不重写历史原始证据。
