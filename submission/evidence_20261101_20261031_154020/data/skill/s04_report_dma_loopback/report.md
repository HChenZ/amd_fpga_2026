# AXI DMA loopback overlay: resources, timing and board transfer evidence

## Environment

- python: 3.13.9
- platform: Windows-11-10.0.26200-SP0
- pynq: not_installed

## Metrics (16 configured, 1 not_measured)

| metric | value | unit | evidence | source | note |
|---|---|---|---|---|---|
| LUT * | 2436 | cells | tool_report | util:`all.Slice LUTs.used` |  |
| FF * | 3333 | cells | tool_report | util:`all.Slice Registers.used` |  |
| BRAM tiles | 2 | tiles | tool_report | util:`all.Block RAM Tile.used` |  |
| DSP | 0 | cells | tool_report | util:`all.DSPs.used` |  |
| latches * | 0 | cells | tool_report | util:`all.Register as Latch.used` |  |
| design state | Physopt postRoute |  | tool_report | util:`header.design_state` |  |
| WNS * | 1.736 | ns | tool_report | timing:`wns_ns` |  |
| WHS * | 0.025 | ns | tool_report | timing:`whs_ns` |  |
| timing met | True |  | tool_report | timing:`timing_met` |  |
| board transfers * | 6 | count | measured | board:`transfers.*.received` |  |
| bytes received (total) | 369 | B | measured | board:`transfers.*.received` |  |
| largest transfer | 256 | B | measured | board:`transfers.*.received` |  |
| all comparisons passed * | True |  | measured | board:`transfers.*.comparison.ok` |  |
| max transfer (from hwh) | 16383 | B | tool_report | board:`dma_config.max_transfer` |  |
| loopback throughput | - | MB/s | not_measured | board:`transfers.*.throughput_mbps` | path 'transfers.*.throughput_mbps' not found ('throughput_mbps') |
| stream peak (theoretical) | 400 | MB/s | estimated | constant | basis: FCLK0 100 MHz x 32-bit AXI-Stream (c_m_axis_mm2s_tdata_width=32), one beat per cycle, no DMA/AXI overhead |

`*` = required. Source files: `30_non_ascon_dma.json` (sha256 213f81bdddcf...), `timing_summary.rpt` (sha256 0ab2413739ec...), `utilization.rpt` (sha256 34e29d561fd7...)
