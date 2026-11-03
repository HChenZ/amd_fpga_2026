# 当前与旧入口速查

> **2026-11-02 布局更新**：当前总入口为project_board.md。下面旧布局表是此前审计记录；其中独立board/src/sim/
> build/Skill验证工具现已整体隔离到archive/history的相同相对子树，不能按旧根路径直接运行。
> 当前PUF3及实际共享依赖仍保留原位，当前交付看delivery/README.md，不再生成证据包附件。
> 原始记录在archive/evidence，旧完整包本机隔离；目录改变不表示补做了硬件验证。

更新：2026-11-01；owner TBD。只定义说明层面的版本职责，不修改任何程序默认值。
全部工程/固件/包的历史与审计结果见 [版本清单](version_inventory_20261101.md)，P0 覆盖见
[证据复核](p0_evidence_review_20261101.md)。

## 1. 当前主演示：PUF3

| 项目 | 唯一当前选择 |
|---|---|
| 工件目录 | `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/` |
| bit / hwh | `pynq_puf3.bit`（769ed24c…）/ `pynq_puf3.hwh`（4a0e7b95…） |
| 控制身份 / 固件 | PQF3=0x33465150 / pynq-svc-puf3 |
| 板端入口 | `src/pynq_puf3/pynq_puf3_board_test.ipynb`，顺序运行全部单元 |
| Python 驱动 | Notebook 内嵌 Puf3BridgeRegs / PynqPuf3Transport；公共 API/帧编解码来自 src/pynq |
| 固件构建 | `src/firmware/pynq_svc_puf/build.py`；不要换成 pynq_svc/build.sh |
| 实现 / 协同仿真 | `board/vivado_zynq7000_xc7z020_pynq_puf3/build.tcl` / `sim/pynq_puf3/run.py` |
| 关键源选择 | 排除 src/rtl/soc_top.v、keys/key_mmio.v，换入 PUF3 board 下的两个变体；以专用 build.tcl 为准 |
| 报告主采样 | `data/pynq_puf3/notebook_20261031_114512/result.json` |
| 报告 PDF | `report/technical/amd_fpga_2026_latex_final/amd_fpga_2026_report/output/pdf/final_report.pdf` |
| 发布入口 | `delivery/manifest.json` 与 `delivery/README.md`；旧证据索引在 `archive/evidence/`，按各包清单选择版本 |

PUF3 指三模式 + PUF v1，不是 PUF 第三代。板端 PT/AD 各 ≤16 B；PUF 只有会话内功能证据，
RO 计数器域未签核、跨上电/PVT/BER 未测。加载 candidate 与重新构建是两件事：重建/重发布可能改变工件，
不能未经重测复用旧板测哈希。已验证数据与边界见 [项目简介](project_intro_20261101.md)。

## 2. 旧入口保留，不能当作 PUF3

| 入口 | 实际对象 | 当前使用方式 |
|---|---|---|
| `src/pynq/board_demo.py`、`board_benchmark.py`、`board_error_gate.py` | 旧 PYNQ v1 release，pynq-svc-v1，ID 0x514e5950 | 仅历史复测；只改 --release 目录不能变成 PUF3 |
| `src/pynq/pynq_board_demo.ipynb`、`pynq_board_error_gate.ipynb` | 同上 | 已执行证据保留；不要用它们录当前 PUF3 视频 |
| `src/pynq/pynq_transport.py` 的直接 BridgeRegs/from_overlay | 默认旧 ID | PUF3 使用 Notebook 子类；不全局改共享驱动 ID |
| `sim/ascon/run_cpu_regression.py`、`run_ascon_*.sh` | 早期 PL-only CPU 自测，默认源列表已缺 keys/BUFG | 默认 elaboration exit 4；--pynq-p0 只选旧无 PUF 版本，不是 PUF3；本轮不修程序 |
| `sim/board/run_tests.py --pynq-p0`、`sim/pynq/elab_check.sh` | 旧 PYNQ v1/rtl_p0 验证 | 原结果与源码版本保留，不作当前 PUF3 全回归 |
| `docs/tech_report/build_report.py` 等 Markdown/HTML/LaTeX 旧流水线 | v0.9 旧报告 | 不再用来生成最终 PDF；旧 verify_report.py 还引用已移出的 10-29 路径 |
| `build/build_timing_acb.tcl` 等时序/策略实验 | 当时的 top_pl_bram/源快照 | 不等于 PUF3 构建步骤，不能无版本选择直接重跑 |

以上默认值不改、目录不删除、历史 PASS/FAIL 不回写；入口失效或未覆盖应明示，不冒充当前程序已修复。

## 3. 共享文件不是旧垃圾

- PUF3 固件复用 `pynq_svc/{svc_io.c,ascon_modes.c,svc.h,bin2coe.py}` 和
  `ascon_hw_rv32/{crt0.S,libc_min.c,riscv.ld,bin2vhex.py}`，但不使用这两目录的旧 main。
- `svc.h` 的旧固件字符串由 PUF3 main 显式覆写，不能据此误判固件错版。
- PUF3 Notebook 复用 `src/pynq` 的 API/协议/golden 及 benchmark 的纯函数，不调用旧 prepare_hardware。
- PUF3 构建导入 `board/..._ascon/.../ip` 的 AXI BRAM/blk_mem_gen XCI；不能整目录删旧工程。

## 4. 不要求改成 PUF3 的对象

- 通用 `skill/pynq-overlay-workflow` 保持配置驱动；已冻结 Skill L3 的 Ascon 对象是旧 v1，另有 Base GPIO/DMA 回环。
  不改旧 Notebook/哈希使它“看起来测了 PUF3”。
- CPU-DMA / HW_DIRECT / PUF v2 / PUF-MIN 是不同协议与源集的独立实验，当前不用于主演示。
  CPU-DMA 已有 SW/ISE 各 1089 组目标仿真，但不能当成 PUF3 全量板测；PUF v2 旧候选明确禁止上板。
- 原 CICC baseline、Kintex、PL-only、PUF-only 原型和日期文档保留为来源/研究/历史。

## 5. 当前证据/文档的范围

当前证据包 `evidence_20261101_20261101_183826`（267 文件）与源码留档 `source_92159b9.zip`
冻结于本轮说明收口之前。说明改动不会偷偷改旧包、manifest、PDF 或其哈希；需要新交付快照时，
按 [submission/README](../../submission/README.md) 重新核对与装配。它们是完整工程/证据留档，不是仅含 PUF3 的精简部署包。

当前 PDF 已入库；独立 LaTeX 源与截图按用户安排不单独入库、随证据包提供。在只有 Git checkout 的环境中，
必须先从已核验的包恢复报告源与本机历史原件，才能运行需要这些输入的报告/装配脚本，不能承诺空环境一键复现。

## 6. 文档读法

1. 当前导航/使用说明：按此表与 README 顶部选版本。
2. 带日期的评审、验证、计划：正文保留当时事实；开头的 11-01 提示只说明适用版本，不改原数据。
3. 原始结果、生成 manifest、包内快照、锁定参考、Skill 实验材料：不为文案同步修改字节。
4. `not_measured`、`NOT_RUN`、已执行 FAIL、验收未关闭分别记录；不因主演示换版而互相转记。
