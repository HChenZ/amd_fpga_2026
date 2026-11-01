# 当前报告证据清单（自动生成）

范围：RV32/PYNQ 短消息三模式；历史 PL-only 单独分组。

| 条目 | 内容 | 原始工件 |
|---|---|---|
| C-1 | PYNQ v1 release（pynq-svc-v1，最终报告作历史对照）：bit/hwh/固件与构建身份 | `board/vivado_zynq7000_xc7z020_pynq/release/pynq.bit`<br>`board/vivado_zynq7000_xc7z020_pynq/release/pynq.hwh`<br>`board/vivado_zynq7000_xc7z020_pynq/release/pynq_svc.bin`<br>`board/vivado_zynq7000_xc7z020_pynq/release/pynq_svc.coe`<br>`board/vivado_zynq7000_xc7z020_pynq/release/pynq_svc.elf`<br>`board/vivado_zynq7000_xc7z020_pynq/release/manifest.json`<br>`board/vivado_zynq7000_xc7z020_pynq/release/sha256sums.txt` |
| C-2 | PYNQ v1 overlay 实现原件，Vivado 2025.2 | `build/reports/pynq_final_20261028/context.txt`<br>`build/reports/pynq_final_20261028/timing.rpt`<br>`build/reports/pynq_final_20261028/utilization.rpt`<br>`build/reports/pynq_final_20261028/drc.rpt`<br>`build/reports/pynq_final_20261028/bram_image.json` |
| C-3 | PYNQ v1 板级容量内官方 KAT，2026-10-28 | `data/pynq/board_20261028/pynq_board_full.json`<br>`data/pynq/board_20261028/pynq_board_full.log`<br>`data/pynq/board_20261028/identity.txt` |
| C-4 | PYNQ v1 固定输入 warm benchmark 与已执行 Notebook，2026-10-31 | `data/pynq/notebook_20261031_112052/identity.json`<br>`data/pynq/notebook_20261031_112052/pynq_board_smoke.json`<br>`data/pynq/notebook_20261031_112052/pynq_board_smoke.log`<br>`data/pynq/notebook_20261031_112052/pynq_warm_benchmark.json`<br>`data/pynq/notebook_20261031_112052/pynq_warm_benchmark.log`<br>`src/pynq/pynq_board_demo.ipynb` |
| C-5 | PYNQ v1 错误恢复与已执行 Notebook，2026-10-31（不是 PUF3 的错误门禁） | `data/pynq/error_gate_20261031_112812/identity.json`<br>`data/pynq/error_gate_20261031_112812/pynq_board_error_gate.json`<br>`data/pynq/error_gate_20261031_112812/pynq_board_error_gate.log`<br>`src/pynq/pynq_board_error_gate.ipynb` |
| C-6 | 归档仿真回归，2026-10-28；不是当前 HEAD 重跑 | `build/reports/pynq_final_20261028/smoke/summary.json`<br>`build/reports/pynq_final_20261028/regression_final/summary.json`<br>`build/reports/pynq_final_20261028/final_tests.json` |
| C-7 | host 标准验证与生产失败契约；修复前结果分列 | `data/ascon/results/host_validation.json`<br>`data/ascon/results/reference_gate.json`<br>`data/ascon/results/failure_contract.json`<br>`data/ascon/results/failure_contract_original_reproduction.json` |
| C-8 | 历史 PL-only 运行日志，不是当前 PYNQ 性能 | `data/ascon/results/board/uart_20261026_sw_and_ise.txt`<br>`data/ascon/results/board/uart_20261027_mmio.txt`<br>`data/ascon/results/board/xcom_raw_20261026.XDat`<br>`data/ascon/results/board/xcom_raw_20261027.XDat` |
| C-9 | 历史 PL-only 镜像与实现原件，本地备份 | `build/local/board_bitstream/top_pl_bram_sw.bit`<br>`build/local/board_bitstream/top_pl_bram_ise.bit`<br>`build/local/board_bitstream/top_pl_bram_hw.bit`<br>`build/local/proj_backup_first_time_20261027/first_time.runs/impl_1/top_pl_bram_timing_summary_routed.rpt`<br>`build/local/proj_backup_first_time_20261027/first_time.runs/impl_1/top_pl_bram_utilization_placed.rpt`<br>`build/local/proj_backup_first_time_20261027/first_time.runs/impl_1/top_pl_bram_drc_routed.rpt`<br>`build/local/proj_backup_first_time_20261027/first_time.runs/impl_1/top_pl_bram_route_status.rpt` |
| C-10 | 历史策略 sweep 逐项记录 | `data/ascon/results/strategy_sweep_20261017/strategy_sweep_summary.json`<br>`data/ascon/results/strategy_sweep_20261017/strategy_sweep_summary.csv` |
| C-11 | 实物正面照片，不替代芯片完整丝印取证 | `docs/tech_report/figs/board_photo.jpg` |
| C-12 | 独立 RO-PUF 原型，v2 失败与 v3 同次上电自检；非当前 overlay | `data/ascon/results/board/uart_20261027_keys3.txt`<br>`data/ascon/results/board/xcom_raw_20261027_keys3.XDat`<br>`src/rtl/keys/puf_key.v`<br>`src/rtl/keys/key_mmio.v`<br>`src/firmware/keys_rv32/main.c`<br>`docs/io_timing_signoff.md` |

工件 52 个；缺失 0；发布工件与板测引用 SHA-256/大小匹配。
清单路径相对仓库根，校验：sha256sum -c docs/tech_report/evidence/sha256sums.txt。
warm benchmark 的已执行 Notebook 本体尚缺；只列实际已有 JSON/log。
