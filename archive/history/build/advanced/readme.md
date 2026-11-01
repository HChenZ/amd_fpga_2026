# 独立实验构建脚本，不是 PUF3 构建入口

更新：2026-11-01。程序与原默认值保留，各脚本只对自己的工程/快照负责。

| 集合 | 对象 |
|---|---|
| cpu_dma_80mhz.tcl | CPU-DMA 最终80MHz候选；不是 PUF3 降频版本 |
| cpu_dma_export_ps/finish_setup/refine_prepare/refine_finish | CPU-DMA 当时的修正/中间工作区步骤；不是独立通用一键命令 |
| cpu_dma_xsim/cpu_dma_xsim_dma/cpu_dma_xsim_units/cpu_dma_sim_run | CPU-DMA 的有界模型/vendor IP 验证；不代替 PUF3 板测 |
| package_direct.py/verify_direct_evidence.py/vendor_dma_xsim.tcl | 无CPU的 HW_DIRECT/DMA 实验 |
| puf_physical_ooc.tcl/puf_xsim.tcl | 独立 PUF v2 内核物理/行为探索，旧SoC候选仍INVALID |

原 source/bit/HWH/STA/功能结果分别对应记录版本，不从脚本名称推断当前可交付。
当前 PUF3 请使用 board 下专用 build.tcl；全部入口见 docs/version_entrypoints.md。
