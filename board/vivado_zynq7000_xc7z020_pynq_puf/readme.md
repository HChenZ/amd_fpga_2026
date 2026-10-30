# PYNQ overlay + PUF v1 self-test (pynq_puf)

2026-10-30; owner TBD. Independent overlay: the frozen PYNQ release
(`../vivado_zynq7000_xc7z020_pynq/release/`) and the JTAG project
(`../vivado_zynq7000_xc7z020_ascon/`) are not opened or modified.

## Why this exists

The PYNQ release build excludes `src/rtl/soc_top.v` and uses `rtl_p0/` (no PUF), so no
PYNQ test so far exercised the PUF. The only PUF board PASS (2026-10-27, keys_rv32 v3,
`data/ascon/results/board/uart_20261027_keys3.txt`) used the standalone JTAG design with a
physical CH340 UART. This overlay puts the same PUF v1 RTL and the same firmware COE behind
the PYNQ PS/mailbox path so the PUF can be tested from PYNQ.

## What is inside

| Item | Value |
|---|---|
| Tool / part / top | Vivado 2025.2, xc7z020clg400-1, `pynq_puf_wrapper` |
| CPU / SoC | `pynq_soc` -> `top` -> `src/rtl/soc_top.v` (PUF v1: 256 RO, DNA, `key_mmio`, `ro_clk` = clk/4 via BUFG) |
| Firmware | `ascon_keys.coe` = keys_rv32 v3 (commit a4ae769), byte-identical to the 10-27 board PASS image |
| Clock | FCLK0 100 MHz; UART CPU<->mailbox 100 MHz/16 |
| Constraints | PS7 generated + `pynq_puf_timing.xdc` (`ro_clk` generated clock, implementation only) |
| `pynq_ctl_0` | 0x40000000, ID `0x31554650` ("PFU1"), version 1; CTRL bit0 holds the CPU in reset |
| `pynq_mbox_0` | 0x40001000, ID `0x4D424F58`; RXDATA +0x4, RXSTAT +0xc |
| RO pblock | `pb_ro_puf` SLICE_X60Y115:X113Y149 created by `puf_opt_pre.tcl`; soft, see below |
| Not included | 3-mode SW/ISE/MMIO service, DMA/HW_DIRECT, PUF v2 |

The 3-mode PYNQ client checks ID `0x514E5950` and refuses this overlay by design.
RTL and firmware are unchanged; only constraints/implementation differ from the JTAG build.

## Current candidate (offline gates PASS, board NOT_RUN)

| Item | Result |
|---|---|
| Implementation | Performance_ExtraTimingOpt (+ post-route phys_opt step, no change needed) |
| clk_fpga_0 (10 ns) | WNS +0.062 / WHS +0.009 ns, 0 failing of 54422 endpoints |
| ro_clk (40 ns, generated) | WNS +16.371 / WHS +0.146 ns, 0 failing of 6127; clk<->ro_clk crossings pass |
| DRC / PS pins | 0 Error, 0 Critical Warning / no `Netlist 29-160` |
| RO structure | 1280 ring LUTs present, all assigned to `pb_ro_puf`; 585 physically inside its region |
| Resources | 18626 LUT / 32048 FF / 34.5 BRAM tile / 4 DSP |
| BRAM init | generated `.mif` = `ascon_keys.coe` word for word (32768 words) |
| HWH | `pynq_ctl_0` 0x40000000 ID 0x31554650 v1, `pynq_mbox_0` 0x40001000, FCLK0 100 MHz |
| Cosimulation | normal PASS (PASS line + DONE); mutant `KEY_USE_PUF=0` reports `FAIL dna-only fallback`, TB exits non-zero |
| Not signed off | RO counters only: 5120 no-clock pins, 15360 pins without max delay, 256 intentional loops |

Hashes: `candidate/sha256sums.txt`; context: `candidate/manifest.json`; every strategy tried
(both rounds): `candidate/reports/explore_impl.txt`. No clock/XDC exception was relaxed.

**Correction (2026-10-30).** The first candidate (bit `59e23742…`) was reported as
"1280/1280 RO LUTs in pblock". That counted the PBLOCK *assignment*. The placer turned
`pb_ro_puf` soft (Place 30-640: CARRY4 demand 1687 > 1470 sites), so only 468 of them were
physically inside. The gate now reports physical placement separately. Isolation is a
placement preference, not a functional requirement; the honest number is in `gate.txt`.

## Timing signoff status

STA uses AMD's characterized delay models (slow/fast corners); no board delay measurement is
involved. Three domains, three different states:

1. **CPU / Ascon / AXI / mailbox (clk_fpga_0)** - signed off, see table above.
2. **PUF sampling control (`ro_clk` = FCLK0/4)** - signed off since this candidate.
   It only needed to be declared (`pynq_puf_timing.xdc`); the router then fixed the hold
   paths that the previous candidate had (acc->raw_r -0.100 ns, req_tgl->req_sync -1.610 ns,
   visible when the old bit is analysed with the same clock). This removed 5824 of the
   10944 no-clock pins.
3. **RO oscillator counters (256 x 20 bit)** - **not signed off, and cannot be by
   constraints alone.** `ro_corner_sta.tcl` (analysis only, bit unchanged) computes each
   routed ring's period from the same delay models and checks each corner with that corner's
   own RO period, so ring and counter track together:

| Corner | Fastest ring | Counter setup (worst of 4 groups) | Counter hold |
|---|---|---|---|
| Slow | 2.716 ns = 368 MHz | -0.748 .. -1.163 ns | -0.039 .. -0.499 ns |
| Fast | 0.927 ns = 1079 MHz | -0.690 .. -0.910 ns | -0.147 .. -0.344 ns |

   Causes are structural: each counter is clocked by a LUT output on general routing
   (0.5 - 1.5 ns skew between its 20 flip-flops), and the 20-bit counter wraps above
   400 MHz within the 65536 x 40 ns window. Measuring the real RO frequency on the board
   would not change this conclusion (hold violations do not depend on the period).
   Fixing it needs an RTL change to PUF v1: a divide-by-2/4 prescaler flip-flop next to each
   ring, enable synchronised into each ring domain, and counters kept beside their ring.
   That is a new, unverified PUF and is not part of this candidate.

A board PASS (10-27 JTAG, or this overlay once run) therefore shows the PUF working on that
one board at its conditions; it does not prove operation across voltage/temperature corners.

## Build and offline checks (repository root)

```sh
vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl -notrace
python -X utf8 sim/pynq_puf/run.py
vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf/ro_corner_sta.tcl -notrace \
  -tclargs build/local/pynq_puf/vivado/pynq_puf.runs/impl_1/pynq_puf_wrapper_postroute_physopt.dcp build/local/pynq_puf/ro_sta
python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf/package.py
```

`build.tcl` refuses an existing `build/local/pynq_puf/vivado` and stops (no bit) unless
setup/hold >= 0 for all declared clocks, no DRC Error/Critical Warning, no `Netlist 29-160`
and all 1280 RO LUTs present. Placement results vary between strategies on this design;
`explore_impl.tcl` (parallel strategies) and `finalize_run.tcl <run> <strategy>` (same
gates, bit from that run) are how the current candidate was produced from impl_3.
`package.py` re-checks the gates, the cosimulation and that `ro_corner_sta.txt` came from
the checkpoint of the released bit, then writes `candidate/` with hashes.

## Board test (teammate: this is the only step)

Copy the repository (or at least this directory with `candidate/`) to the PYNQ board:

```sh
sudo -E python3 board/vivado_zynq7000_xc7z020_pynq_puf/board_test.py \
  --candidate board/vivado_zynq7000_xc7z020_pynq_puf/candidate \
  --out data/pynq_puf/board_20261030_run1 --runs 5
```

The script verifies bit/HWH against `candidate/manifest.json`, downloads the overlay, checks
identity and FCLK0, then per run holds/releases the CPU reset and reads the ASCII log until
`DONE` (or the firmware's final `FAIL`). PASS = every run prints
`PASS key subsystem: enroll + reconstruct stable`, no `FAIL`, no mailbox overflow, and the
same DNA in every run. Raw logs: `uart_runNN.txt`, summary `result.json`. Exit code 0 only
on PASS. Keep the output directory unchanged as evidence.

## Limits (do not claim)

- Each run enrolls again (helper is volatile): in-session repeatability only, not
  cross-power-cycle reconstruction. Entropy, BER, temperature, uniqueness: not_measured.
- RO counter domain not timing-signed-off (section above).
- REF/RAW/MASK/DNA are readable over MMIO in PUF v1; no confidentiality claim.
- Board result is NOT_RUN until `board_test.py` output exists.
