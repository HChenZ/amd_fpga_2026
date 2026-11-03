# 隔离的历史工程与源码

本目录不参与当前PUF3默认构建。当前工程仍在根目录board/src/sim；不要把所有历史模块加入同一Vivado工程。

| 子树 | 内容 |
|---|---|
| board/ | 旧PYNQ v1/PUF-only、Kintex、baseline、CPU-DMA、HW_DIRECT、PUF v2/MIN与Skill回环工程 |
| src/rtl/ | 独立DMA/PUF v2/MIN/CPU-DMA/Cache实验RTL |
| src/firmware/ | 历史单镜像/PUF自检/DMA固件与original_cpu源资产 |
| src/pynq/ | 独立DMA/PUF v2/MIN主机工具 |
| sim/ | 历史CPU/板前/独立DMA/PUF验证工具与原始单元资产 |
| build/ | 原时序/策略/物理探索脚本 |
| skill/ | 独立验证工具、L2/L3流程与辅助RTL纪律Skill，不是本次唯一安装包 |
| docs/、tasks/ | 原阶段说明、旧报告源与任务卡 |

目录中使用original_cpu作为中性显示名；原始记录与真实字节保存在相邻evidence归档及Git历史，第三方版权/许可不删除。
部分旧脚本的ROOT/相对路径属于原布局，因此这里首先是**源码留档**，不承诺原位一键重建。

## 快速定位各独立版本

| 版本 | 入口 | 说明 |
|---|---|---|
| 旧PYNQ v1 | [pynq](board/vivado_zynq7000_xc7z020_pynq/readme.md) | 无PUF，pynq-svc-v1；历史9项错误门禁与Skill旧工件 |
| PUF-only PYNQ | [pynq_puf](board/vivado_zynq7000_xc7z020_pynq_puf/readme.md) | PFU1，自检固件，不是三模式服务 |
| baseline | [工程XPR](board/vivado_zynq7000_xc7z020_baseline/riscv_vivado_project.xpr) | 原始配置/源资产，文档原件见证据归档 |
| Kintex | [legacy](board/vivado_kintex7_legacy/readme.md) | 不用于目标XC7Z020 |
| CPU-DMA | [pynq_dma_cpu](board/vivado_zynq7000_xc7z020_pynq_dma_cpu/readme.md) | 最终候选80MHz，全量CPU离线仿真，未板测 |
| HW_DIRECT | [dma_direct](board/vivado_zynq7000_xc7z020_dma_direct/readme.md) | 无CPU、多块mode4，未板测 |
| PUF v2 | [puf_v2](board/vivado_zynq7000_xc7z020_puf_v2/readme.md) | 旧候选INVALID、禁止上板 |
| PUF-MIN | [puf_min](board/vivado_zynq7000_xc7z020_puf_min/readme.md) | 无RV32的探索，非PUF3 |
| DMA回环 | [axi_dma_loopback](board/vivado_zynq7000_xc7z020_axi_dma_loopback/readme.md) | 非Ascon，仅Skill历史L3工件 |

独立历史源码ZIP会另附当前共享支持，实际重跑仍须核对当时源快照和工具，不能沿用旧PASS。

旧PUF v2候选仍INVALID_DO_NOT_PROGRAM。CPU-DMA最终物理候选80MHz，未板测；HW_DIRECT无RV32，未板测；
它们的容量、时钟和全量仿真不转记到PUF3。原始报告/生成物另在evidence，不作为源码附件重复装配。
