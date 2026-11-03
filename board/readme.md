# 当前 PUF3 工程与共享配置

| 目录 | 职责 |
|---|---|
| [vivado_zynq7000_xc7z020_pynq_puf3](vivado_zynq7000_xc7z020_pynq_puf3/readme.md) | **唯一主演示**，构建Tcl/两个关键RTL变体/已验证candidate |
| vivado_zynq7000_xc7z020_ascon | 保留的AXI BRAM/blk_mem_gen IP配置与内存输入来源，PUF3 build.tcl直接复用；不是当前上板入口 |
| atk_navigator_7020 | 板卡资料与引脚核验说明，不是overlay |

独立旧v1/PUF-only、Kintex、baseline、DMA、PUF v2/MIN、Skill回环工件已隔离到
`archive/history/board/`，各自源码与原始记录保留，不在当前工程中混用。
不要全量导入src/rtl：PUF3明确换入本目录下变体soc_top/key_mmio。板测用src/pynq_puf3中的Notebook。
