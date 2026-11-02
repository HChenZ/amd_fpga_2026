# 当前 PUF3 板测入口

更新：2026-11-01；owner TBD。本目录的 **pynq_puf3_board_test.ipynb 是当前完整板测入口**，
没有独立 Python CLI；不能把旧 src/pynq/board_demo.py 只换目录就当成它。

## 在板上使用已发布 candidate

1. 使用完整仓库/源码留档，确保 `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/` 的 bit/hwh/manifest 配套。
2. 打开本目录 Notebook，核对首代码单元 REPO 默认 `/home/xilinx/jupyter_notebooks/amd_fpga_2026`；
   换位置用已有 ASCON_REPO 配置，不修改驱动或身份门禁。
3. Restart Kernel and Run All Cells。默认 FULL_KAT=True，三模式各跑 289 组，另有 benchmark 和 PUF 段。
4. Notebook 内嵌 Puf3BridgeRegs/PynqPuf3Transport，检查 PQF3=0x33465150 与 pynq-svc-puf3；
   下载前后校核时钟，不把原版 PYNQ 显示 150 MHz 当真实频率。
5. 结果写入新的 `data/pynq_puf3/notebook_<时间>/`。保留失败，不覆盖 10-31 已归档结果；
   新运行结果不能在不核对工件/输入的情况下替换报告主采样。

Notebook 的“单文件”指驱动和板测编排内嵌，不是零依赖：仍使用 src/pynq 的 API、协议、golden 与
board_benchmark 的纯函数，不调用其旧 prepare_hardware。已执行 Notebook 不为说明更新而重写。

## 当前证据与边界

- 报告主采样 `data/pynq_puf3/notebook_20261031_114512/result.json`，bit/hwh/manifest 与 candidate 绑定。
- PT/AD 各 ≤16 B；KAT #529、HWKEY 关闭时测三模式性能；PUF 功能在后续独立段验证。
- 只有会话内注册/重建/HWKEY 证据；RO 计数器域、跨上电/PVT/BER 等未闭合。
- 旧 PYNQ v1 的 9/9 错误门禁与 Skill L3 Ascon 结果不属于 PUF3 完整错误门禁。
- 说明/重建/发布边界见 [版本入口](../../report/design/version_entrypoints.md)；本页不授权重建或覆盖 candidate。
