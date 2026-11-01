# 11-01 冻结清单（V04 留档，自动生成）

- 生成时间：2026-11-01T18:39:56+08:00；生成命令：`python -X utf8 docs/tech_report/evidence/freeze_manifest.py`
- 冻结源码提交：`92159b9eb2b368814f86fef0030bd95b71613896`（main；生成时 upstream `c05782d`，未推送）
- 源码包：`submission/source_92159b9.zip`，4881 文件，132.8 MB，SHA-256 `0ade4e665743d94d0e3fd173197eb5e34b5ccc3db3b289f3fdba2a22031d95eb`（git archive，仅本机，不入库）
- 证据包：`submission/evidence_20261101_20261101_183826.zip`（267 文件），SHA-256 `2a0f0304e975dd14ca3d53989cac78e000f7584aa8303ed6e5f82fe1500dffec`；目录已入库
- 最终报告：`docs/tech_report/amd_fpga_2026_latex_final/amd_fpga_2026_report/output/pdf/final_report.pdf`，SHA-256 `603c625a8e8f3c1271d9d96f1d4982e15ded676de9262c4ef3813111124e4825`，构建 build_20261101_174743；板测主采样 `data/pynq_puf3/notebook_20261031_114512/result.json`；PDF 已入库
- 未入库文件 196 个（截图、LaTeX 源等，按用户要求不单独入库），不在源码包内，随证据包提供
- 校验：D02 PASS 64/64（对最终报告）；PUF3 板测绑定 candidate、PYNQ v1 release 与 benchmark/错误门禁绑定、Skill L3 均 PASS

## 交付工件

### PUF3 overlay candidate（最终报告主演示）

`board/vivado_zynq7000_xc7z020_pynq_puf3/candidate`；part xc7z020clg400-1，top pynq_puf3_wrapper，Vivado 2025.2；构建时源码 `27f24bb`（dirty=True）；板测证据：`data/pynq_puf3/notebook_20261031_114512/result.json`

| 文件 | SHA-256 |
|---|---|
| pynq_puf3.bit | `769ed24c4ef4b155eccf5b92569a94d00315f7f6913b68c7eaffe65a96fa4654` |
| pynq_puf3.hwh | `4a0e7b95b6cb2d25c0a387e3a193aae56e937f0e2201346c67320dbc973a9675` |
| pynq_svc_puf.bin | `857df29c4310cd483e92730d81f333a68e6970658d5cb81344faf29ec50dd9b7` |
| pynq_svc_puf.coe | `bf3b0591afb251695d81846e6f844b2c5087b6ed38047242dcdde3fea05c6a9e` |
| pynq_svc_puf.elf | `d7ceb168daba6de16e67f8ef753b373ee0b87e2797ab2746297a45b5d3f3ff28` |
| manifest.json | `291e1708d4f307734decfa8a9f7878c99ab18f6937cc08cdbab40bfcc70d6a08` |

### PYNQ v1 release（历史对照）

`board/vivado_zynq7000_xc7z020_pynq/release`；part xc7z020clg400-1，top pynq_wrapper，Vivado 2025.2 SW6299465 IP6300035；构建时源码 `86dc10f`（dirty=True）；板测证据：`data/pynq/notebook_20261031_112052/pynq_warm_benchmark.json`、`data/pynq/error_gate_20261031_112812/pynq_board_error_gate.json`

| 文件 | SHA-256 |
|---|---|
| pynq.bit | `6e7f93203519269e1509f4ece1ee76b93c25c8254fe0f8ae9c942314a197d30d` |
| pynq.hwh | `3ebd26408504ed6181a1eac1f31a79ab0e5449c0f0d4d8f76f53fa6332067581` |
| pynq_svc.bin | `723631655c30d92352e2b0c557bdb07a5776927c3f75baa57b4b330a85e33a4e` |
| pynq_svc.coe | `401cbfdc1dfeb40a02bbfa28a329553eb22f77dce22b6887ef3874f2b4dcb946` |
| pynq_svc.elf | `c8b7001d5fd70df46f35f2b18390ab577f6562ec1841d032e94369b529b93f5b` |
| manifest.json | `9e33f85f4ef3cea9d2efa52c8a3b2383d548e525e8b2d72240de94f7f684423d` |

### 非 Ascon AXI DMA 回环 candidate（Skill L3）

`board/vivado_zynq7000_xc7z020_axi_dma_loopback/candidate`；part xc7z020clg400-1，top dma_loop_wrapper，Vivado 2025.2；构建时源码 `cd5276d`（dirty=True）；板测证据：`data/skill/l3_20261031_063709/30_non_ascon_dma.json`

| 文件 | SHA-256 |
|---|---|
| axi_dma_loopback.bit | `890add35201fb7b9ec930d5421236f928f2f7f130fd78dc9cebbe37fec22213d` |
| axi_dma_loopback.hwh | `27bcceca04459d91d97a598bd5c9bcce6cb1c41190d6d2f6f00666851a3d785f` |
| manifest.json | `a0b2a44533d1422ea9ee03a12dedb7c06239d82d0a1d6ed85ca0c181c2146471` |

## 已知限制（不因冻结变为通过）

- PUF3（主演示）：跨上电/PVT/BER/熵/唯一性 not_measured；RO 计数器域未签核（Slow/Fast 角负 slack）；REF/MASK/RAW/DNA 可读，未证明保密隔离；墙钟只有 summary 中位；PUF3 未跑完整错误门禁矩阵。
- PYNQ v1 release 在最终报告中作历史对照；其 9/9 错误门禁、7 次 reset 属于 pynq-svc-v1，不代表 PUF3。
- Skill：L2 为 simulated，with vs placebo 不显著，留出任务未复现；L3 验证版本 7bc1abf，其后 S04/gen 修复仅离线验证；DMA 吞吐、short_output/missing_tlast 未测。
- 消息/AD 各 ≤16 B；非 1089 全量板测；小时级/断电稳定性未测。
- 未验收研发项（按 10-29 授权不阻塞提交）：B02 原 baseline 重建、B04 FreeRTOS 固件、I02/I04/I05 RV64 与完整异常矩阵、V01 完整门禁、D05 干净环境复现。
- 10-29/10-30 板测目录已由 ae7a270/c05782d 移出工作树（含 10-30 首次 62.5 MHz 失败运行），仅存于 Git 历史；实机演示视频与 PPT 不在本清单内。
