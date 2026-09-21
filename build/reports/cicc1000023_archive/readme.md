# 历史实现报告（非本轮运行）

从原 CICC1000023 ZIP 精选导出 6 个报告/日志，内容字节不变，文件名映射及哈希见 data/recovery/cicc1000023/manifest.json。原 .runs 目录、DCP、bitstream 均未入库。

报告来自 2026-08-08 / Vivado 2025.2：synthesis utilization、placed utilization、post-route physopt timing、route status、synth/impl runme.log。它们证明归档中存在成功构建的历史证据，**不能证明本次恢复工程已重新构建或上板**。

100 MHz 时钟组的历史 WNS=0.056 ns、TNS=0；placed 利用率为 LUT=4806、FF=3129、BRAM tile=38.5、DSP=4。placed 报告与 post-route timing 是不同阶段；不可合成虚构的 post-route PPA 表，也不能把 100 MHz 叫实测 Fmax。约束覆盖与日志 warning 应一并审查。
