# PYNQ Notebook 与 warm benchmark 验证（2026-10-29）

任务 Y04/Y05 的实板证据，owner TBD。正点原子领航者 ZYNQ7020，PYNQ 2.7.0，
Python 3.8.2，Linux 5.4.0-xilinx-v2020.2 armv7l。板端身份见
`data/pynq/notebook_20261029_130920/identity.json`，Notebook 顺序执行时间为
2026-10-29T13:09:20Z。

## 发布身份

- 板端 Git commit：`ac9143d5c6acc9e7ac61f907a7e802eb6b35cddd`
- release manifest source commit：`86dc10f13e96adbb360f1adfe0c4891ce2f8e2a7`
- bit：`6e7f93203519269e1509f4ece1ee76b93c25c8254fe0f8ae9c942314a197d30d`
- hwh：`3ebd26408504ed6181a1eac1f31a79ab0e5449c0f0d4d8f76f53fa6332067581`
- service：`pynq-svc-v1`，`simulated=false`，`selftest_mask=7`，最大 PT/AD 各 16 bytes

## Notebook smoke

Notebook 从头顺序完成三模式 smoke：

| mode | 容量内 KAT | 错误 Tag 拒绝 | 结果 |
|---|---:|---:|---|
| SW | 6/6 | 6/6 | PASS |
| HW | 6/6 | 6/6 | PASS |
| ISE | 6/6 | 6/6 | PASS |

`pynq_board_smoke.json` 报告 `board_validation=PASS`。完整容量内 289/289 KAT
已在 2026-10-28 独立记录；超过 16-byte 的 800 组仍为 `NOT_RUN`。

## Warm benchmark

固定使用锁定官方 KAT `#529`：plaintext=16 bytes、AD=0。每种模式预热 5 次，不计入结果；
随后各采集 30 次加密和 30 次解密。每次调用均检查 CT、Tag 和明文，并验证
`simulated=false`、`mcycle>0`。

| mode | operation | median cycles | cycles/byte | speedup vs SW |
|---|---|---:|---:|---:|
| SW | encrypt | 23,342 | 1,458.875 | 1.000× |
| HW/MMIO | encrypt | 1,439 | 89.938 | **16.221×** |
| ISE | encrypt | 3,995 | 249.688 | **5.843×** |
| SW | decrypt | 24,005 | 1,500.312 | 1.000× |
| HW/MMIO | decrypt | 1,388 | 86.750 | **17.295×** |
| ISE | decrypt | 4,385 | 274.062 | **5.474×** |

每档 30 个原始 `mcycle` 值完全一致，因此 min/median/P95/max 相同。这是确定性 CPU
执行证据，不是从单次结果外推。PS 调用 wall time 中位约 4.96–5.22 ms，变化显著且包含
Python、MMIO 和串口传输，只作端到端描述，不参与 speedup。

`mcycle` scope 是 RV32 固件 `svc_aead_encrypt/decrypt` 调用边界，不包含 PS/UART。
FCLK 配置为 100 MHz；独立频率测量仍为 `not_measured`。

## V03 错误与恢复门禁

2026-10-29T13:40:23Z 在相同 release 和板卡上完成永久错误门禁。`9/9` checks PASS，
`7/7` 次故障恢复成功，epoch 从 1 依次推进到 8；每次 reset 后 SW/HW/ISE 三个模式的
KAT 都重新通过。

| check | 结果 | 关键证据 |
|---|---|---|
| 17B plaintext | PASS | 板端返回 `LENGTH`，epoch 1→2 后三模式 KAT PASS |
| 17B AD | PASS | 板端返回 `LENGTH`，epoch 2→3 后三模式 KAT PASS |
| 半帧 | PASS | 60B 部分帧在 0.25s 内无响应；epoch 3→4 后恢复 |
| deadline | PASS | 96B 请求已提交，过期 deadline 抛 `BackendTimeoutError`；epoch 4→5 后恢复 |
| 重复 request_id | PASS | 首次 `OK`、重复帧 `INTERNAL`；epoch 5→6 后恢复 |
| 错误 epoch | PASS | 返回 `INTERNAL`；epoch 6→7 后恢复 |
| RX FIFO overflow | PASS | 连续 5 帧不读响应触发 overflow；epoch 7→8 后恢复 |
| 三模式连续请求 | PASS | 每模式 50 次加密+解密全部匹配 KAT |
| 初始健康检查 | PASS | `pynq-svc-v1`、`simulated=false`、selftest mask=7 |

缓存可见性按当前架构记为 `NOT_APPLICABLE`：PS/PL 使用 AXI-Lite FIFO 与 RV32 UART
uncached MMIO (`0x20000000`)，没有共享 cacheable buffer。

错误门禁证据目录：`data/pynq/error_gate_20261029_134023/`

```text
f04a034bd2673bcfc1d210842954ebd762b89f15185c481482dc504bd7404850  identity.json
54380aa840fa2cbe8fd6010ea0a1b2bee08fe1d7a85576243298ea118c22b882  pynq_board_error_gate.json
70e8b50b3a227154eee3057e37892f510e06fe9a057447129b769bf424fd1a01  pynq_board_error_gate.log
a8eed832c0428ef4551d8970c3102a2c8df5b3701dbb6f85d0a95c2debaa1292  pynq_board_error_gate.ipynb
```

## 证据文件

目录：`data/pynq/notebook_20261029_130920/`

```text
ac4cd35de320e26ce0f760e61e1d0238b897b58b5e070ea964d0e248bfa011c5  identity.json
43951650486984e445816d3ccb91c8d21f0ea1c1726361a13d509adf0eb2dd78  pynq_board_smoke.json
0bdb4f7736b39b8a9e77ed21cec1094b7e095a9f09769547af45bf6c6ce8618a  pynq_board_smoke.log
fb59cd8391dbe193447037120e4eb5c8e4a90e6822b0ad16cfea33d330fdfea1  pynq_warm_benchmark.json
11022813231e05f9984bb5dc61a03126047f44d4c5762f28a5cd0b5f3b577ee7  pynq_warm_benchmark.log
```

## 结论与边界

- Y04 的 Notebook 从头顺序执行、三模式正确性和 CPU/wall time 分列已取得实板证据。
- Y05 的自动 smoke、固定输入 benchmark、失败非零出口和原始数据已具备实板证据。
- V03 的板级错误、超时、重复命令、RX overflow 与恢复门禁全部通过。
- error-gate 已执行 Notebook 本体、身份、JSON 和日志均已归档；warm-benchmark
  Notebook 的已执行本体仍未归档。
- 尚未完成重复上电稳定性和独立 FCLK 测量；缓存可见性按当前 UART 架构为 N/A。
- 不把本结果与 PL-only 固件历史 cycles 混合；报告性能表以本目录同一次 PYNQ run 为准。

