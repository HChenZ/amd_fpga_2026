## 附录 C 原始证据与复算摘录 {.unnumbered}

报告表格为原始 JSON 复算；下列文本报告保留所选原文行。发布哈希与板测引用一致不等于已完成干净环境重建。

### 当前发布身份

来源：`board/vivado_zynq7000_xc7z020_pynq/release/manifest.json`

```text
{
  "source_commit": "86dc10f13e96adbb360f1adfe0c4891ce2f8e2a7",
  "source_dirty": true,
  "part": "xc7z020clg400-1",
  "top": "pynq_wrapper",
  "vivado": "2025.2 SW6299465 IP6300035",
  "artifacts": {
    "pynq.bit": {
      "bytes": 4045688,
      "sha256": "6e7f93203519269e1509f4ece1ee76b93c25c8254fe0f8ae9c942314a197d30d"
    },
    "pynq.hwh": {
      "bytes": 148833,
      "sha256": "3ebd26408504ed6181a1eac1f31a79ab0e5449c0f0d4d8f76f53fa6332067581"
    },
    "pynq_svc.bin": {
      "bytes": 47592,
      "sha256": "723631655c30d92352e2b0c557bdb07a5776927c3f75baa57b4b330a85e33a4e"
    },
    "pynq_svc.coe": {
      "bytes": 327742,
      "sha256": "401cbfdc1dfeb40a02bbfa28a329553eb22f77dce22b6887ef3874f2b4dcb946"
    },
    "pynq_svc.elf": {
      "bytes": 53880,
      "sha256": "c8b7001d5fd70df46f35f2b18390ab577f6562ec1841d032e94369b529b93f5b"
    }
  }
}
```

### 当前实现原件

#### 时序原文

来源：`build/reports/pynq_final_20261028/timing.rpt`

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Wed Oct 28 15:06:19 2026
| Host         : xyq running 64-bit major release  (build 9200)
| Command      : report_timing_summary -file E:/amd_fpga_2026/build/local/pynq_final/vivado/timing.rpt
| Design       : pynq_wrapper
| Device       : 7z020-clg400
| Speed File   : -1  PRODUCTION 1.12 2019-11-22
1. checking no_clock (0)
2. checking constant_clock (0)
3. checking pulse_width_clock (0)
4. checking unconstrained_internal_endpoints (0)
5. checking no_input_delay (0)
6. checking no_output_delay (0)
7. checking multiple_clock (0)
8. checking generated_clocks (0)
1. checking no_clock (0)
------------------------
 There are 0 register/latch pins with no clock.
4. checking unconstrained_internal_endpoints (0)
------------------------------------------------
 There are 0 pins that are not constrained for maximum delay.
5. checking no_input_delay (0)
------------------------------
 There are 0 input ports with no input delay specified.
6. checking no_output_delay (0)
-------------------------------
 There are 0 ports with no output delay specified.
    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints  
    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------  
      0.034        0.000                      0                62861        0.020        0.000                      0                62861        3.750        0.000                       0                 20822  
Clock             WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints  
-----             -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------  
clk_fpga_0          0.034        0.000                      0                51421        0.020        0.000                      0                51421        3.750        0.000                       0                 20822  
From Clock    To Clock          WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints  
----------    --------          -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------  

Path Group         From Clock         To Clock               WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints  
----------         ----------         --------               -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------  
**async_default**  clk_fpga_0         clk_fpga_0               0.771        0.000                      0                11440        0.873        0.000                      0                11440
```

#### 整机资源原文

来源：`build/reports/pynq_final_20261028/utilization.rpt`

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Wed Oct 28 15:06:23 2026
| Host         : xyq running 64-bit major release  (build 9200)
| Command      : report_utilization -file E:/amd_fpga_2026/build/local/pynq_final/vivado/utilization.rpt
| Design       : pynq_wrapper
| Device       : xc7z020clg400-1
| Speed File   : -1
| Slice LUTs                 | 14269 |     0 |          0 |     53200 | 26.82 |
| Slice Registers            | 19691 |     0 |          0 |    106400 | 18.51 |
| Slice Registers                            | 19691 |     0 |          0 |    106400 | 18.51 |
| Block RAM Tile    | 34.5 |     0 |          0 |       140 | 24.64 |
| DSPs           |    4 |     0 |          0 |       220 |  1.82 |
```

#### DRC 汇总原文

来源：`build/reports/pynq_final_20261028/drc.rpt`

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Wed Oct 28 15:06:23 2026
| Host         : xyq running 64-bit major release  (build 9200)
| Command      : report_drc -file E:/amd_fpga_2026/build/local/pynq_final/vivado/drc.rpt
| Design       : pynq_wrapper
| Device       : xc7z020clg400-1
| Speed File   : -1
1. REPORT SUMMARY
2. REPORT DETAILS

1. REPORT SUMMARY
-----------------
            Netlist: netlist
          Floorplan: impl_1
| CHECK-3   | Warning  | Report rule limit reached  | 2      |
| DPOP-1    | Warning  | PREG Output pipelining     | 3      |
| DPOP-2    | Warning  | MREG Output pipelining     | 4      |
| RBOR-1    | Warning  | RAMB output registers      | 3      |
```

### 容量内 KAT 复算

来源：`data/pynq/board_20261028/pynq_board_full.json`

```text
sw: KAT=289/289 bad_tag=289/289; cycles min/mean/median/max=17584/23801.7/23543/33595
hw: KAT=289/289 bad_tag=289/289; cycles min/mean/median/max=1229/1589.0/1594/1797
ise: KAT=289/289 bad_tag=289/289; cycles min/mean/median/max=3012/4122.0/4137/5209
```

### 固定输入 warm 复算（KAT #529，PT16/AD0，5 次预热）

来源：`data/pynq/notebook_20261031_112052/pynq_warm_benchmark.json`

```text
sw/encrypt: n=30 median_cycles=23342; median_wall_ms=5.151629
sw/decrypt: n=30 median_cycles=24005; median_wall_ms=4.898594
hw/encrypt: n=30 median_cycles=1439; median_wall_ms=4.421964
hw/decrypt: n=30 median_cycles=1388; median_wall_ms=4.193070
ise/encrypt: n=30 median_cycles=3995; median_wall_ms=5.096612
ise/decrypt: n=30 median_cycles=4385; median_wall_ms=4.892817
```

### 错误门禁记录

来源：`data/pynq/error_gate_20261031_112812/pynq_board_error_gate.json`

```text
initial_health: PASS
over_capacity_data_17B: PASS
over_capacity_ad_17B: PASS
half_frame_requires_reset: PASS
deadline_timeout_requires_recovery: PASS
duplicate_request_id_rejected: PASS
stale_epoch_rejected: PASS
rx_fifo_overflow_detected: PASS
repeated_requests: PASS
```

### 归档仿真回归

#### smoke

来源：`build/reports/pynq_final_20261028/smoke/summary.json`

```text
{
  "timestamp_utc": "2026-10-28T06:36:22.776263+00:00",
  "source_head": "0f5d49c38597947dace3f1c99220deca8ef48e14",
  "evidence_kind": "host_and_rtl_simulation",
  "counts": {
    "PASS": 6,
    "FAIL": 0,
    "BLOCKED": 0,
    "NOT_RUN": 9
  },
  "elapsed_s": 18.739,
  "status": "PASS"
}
```

#### regression_final

来源：`build/reports/pynq_final_20261028/regression_final/summary.json`

```text
{
  "timestamp_utc": "2026-10-28T06:47:35.854091+00:00",
  "source_head": "0f5d49c38597947dace3f1c99220deca8ef48e14",
  "evidence_kind": "host_and_rtl_simulation",
  "counts": {
    "PASS": 15,
    "FAIL": 0,
    "BLOCKED": 0,
    "NOT_RUN": 1
  },
  "elapsed_s": 400.168,
  "status": "PASS"
}
```

### host 标准验证与失败契约

#### host_validation

来源：`data/ascon/results/host_validation.json`

```text
{
  "passed": 28661,
  "failed": 0,
  "exit_code": 0
}
```

#### reference_gate

来源：`data/ascon/results/reference_gate.json`

```text
{
  "passed": 12936,
  "failed": 0,
  "exit_code": 0
}
```

#### failure_contract

来源：`data/ascon/results/failure_contract.json`

```text
{
  "passed": 23965,
  "failed": 0,
  "exit_code": 0
}
```

#### failure_contract_original_reproduction

来源：`data/ascon/results/failure_contract_original_reproduction.json`

```text
{
  "passed": 1,
  "failed": 1,
  "exit_code": 1
}
```

### 历史 PL-only 日志选行

#### SW 与 ISE 镜像（2026-10-26）

来源：`data/ascon/results/board/uart_20261026_sw_and_ise.txt`

```text
=== ASCON-AEAD128 software on RV32IM ===
KAT empty : PASS
KAT 1B : PASS
KAT 16B : PASS
KAT 16B+AD : PASS
KAT 17B : PASS
KAT 32B : PASS
tamper reject : PASS
KAT: 6/6 PASS
enc 16B : 20806 cycles, 4495 inst, CPI 462 (x100)
enc 32B : 25787 cycles, 5606 inst, CPI 459 (x100)
dec 16B : 21360 cycles, 4722 inst, CPI 452 (x100)
dec 32B : 26444 cycles, 5857 inst, CPI 451 (x100)
===DONE===
KAT empty  : PASS
KAT 1B     : PASS
KAT 16B    : PASS
KAT 16B+AD : PASS
dec round  : PASS
tamper     : PASS
ISE cycles   : 2570
===DONE===
```

#### MMIO 镜像（2026-10-27）

来源：`data/ascon/results/board/uart_20261027_mmio.txt`

```text
!hi 
"
?
?
?
A
A?
?
-
KAT empty   : PASS
KAT 1B      : PASS
KAT 16B     : PASS
KAT 16B+AD  : PASS
dec roundtrip: PASS
tamper reject: PASS
len reject  : PASS
crypto latency : 103 cycles
full MMIO      : 688 cycles
===DONE===
```

### 历史 PL-only 时序原文

来源：`build/local/proj_backup_first_time_20261027/first_time.runs/impl_1/top_pl_bram_timing_summary_routed.rpt`

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Tue Oct 27 18:42:44 2026
| Host         : DESKTOP-5H4M0DR running 64-bit major release  (build 9200)
| Command      : report_timing_summary -max_paths 10 -routable_nets -report_unconstrained -file top_pl_bram_timing_summary_routed.rpt -pb top_pl_bram_timing_summary_routed.pb -rpx top_pl_bram_timing_summary_routed.rpx
| Design       : top_pl_bram
| Device       : 7z020-clg400
| Speed File   : -1  PRODUCTION 1.12 2019-11-22
    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints  
    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------  
      0.087        0.000                      0                55572        0.021        0.000                      0                55572        3.750        0.000                       0                 17227  
Clock                     WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints  
-----                     -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------  
clk                                                                                                                                                                     7.000        0.000                       0                     1  
From Clock    To Clock          WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints  
----------    --------          -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------  

Path Group          From Clock          To Clock                WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints  
----------          ----------          --------                -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------  
**async_default**   clk_out1_clk_wiz_0  clk_out1_clk_wiz_0        0.448        0.000                      0                11217        0.983        0.000                      0                11217
```

### 历史策略 sweep 记录

逐项记录为 JSON/CSV，篇幅较长不摘录；路径与哈希见证据清单 C-10。

### 实物正面照片

照片即图 3-1（`docs/tech_report/figs/board_photo.jpg`），不替代芯片完整丝印取证。

### 独立扩展原型状态摘录（保留失败段，非可靠性统计）

来源：`data/ascon/results/board/uart_20261027_keys3.txt`

```text
# 来源：XCOM 串口捕获（COM7 / 115200 8N1），原始字节见 xcom_raw_20261027_keys3.XDat
# 本文件含两段连续捕获：
#   第 1 段 = PUF 握手 v2 固件（固件未等 idle 抢跑，读数误判，结论作废，仅作问题记录）
#   第 2 段 = v3 固件（先等 idle 再发 START），板级全通过

[第 1 段：v2 固件 — 抢跑误判]
=== KEY SUBSYSTEM SELF-TEST ===
STATUS boot   : 00000001 busy=1 enrolled=0 done=0 quality=0
STATUS pre-enr: 00000001 busy=1 enrolled=0 done=0 quality=0
STATUS enrol: 00000023 quality=0
FAIL enroll not marked
FAIL quality=0
STATUS pre-rec: 00007f05 busy=1 enrolled=1 done=0 quality=127
STATUS recon: 00007f26
FAIL
[第 2 段：v3 固件 — 板级通过]
STATUS boot   : 00000001 busy=1 enrolled=0 done=0 quality=0
STATUS idle   : 0000003a busy=0 enrolled=0 done=1 quality=0
STATUS enrol: 00008026 quality=128
STATUS recon: 00008026
PASS key subsystem: enroll + reconstruct stable
```
