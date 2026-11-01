# 独立实验数据，不是当前 PUF3 数据

更新：2026-11-01。current_candidates.json只管理本目录实验候选，不是项目全局主演示/提交指针。
当前PUF3板测看data/pynq_puf3，提交包看submission/current_evidence.json。

| 子目录 | 对象/状态 |
|---|---|
| dma_cpu | 独立CPU-DMA；SW/ISE各1089、HW289目标仿真，XSim7418包；最终物理候选80MHz，板测NOT_RUN |
| dma_direct | 无CPU的HW_DIRECT多块实验；最终候选024214，板测NOT_RUN |
| puf / puf_soc | 独立PUF v2内核/SoC；旧SoC候选INVALID、禁止上板，正时序子集与功能仿真不能豁免 |
| puf_min | 无RV32的最小PUF探索，不能称PUF3板测或已发布替代版 |

记录按当时source/vector/firmware/bit/HWH追溯；snapshot、原始日志、FAIL、验证摘要不为文档统一而重写。
全量目标CPU仿真已存在于DMA版本，但不能转记为PUF3全1089板测。
