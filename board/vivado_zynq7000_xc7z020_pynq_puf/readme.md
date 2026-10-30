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
| `pynq_ctl_0` | 0x40000000, ID `0x31554650` ("PFU1"), version 1; CTRL bit0 holds the CPU in reset |
| `pynq_mbox_0` | 0x40001000, ID `0x4D424F58`; RXDATA +0x4, RXSTAT +0xc |
| RO placement | pblock `pb_ro_puf` SLICE_X60Y115:X113Y149, created by `puf_opt_pre.tcl` (BD hierarchy) |
| Not included | 3-mode SW/ISE/MMIO service, DMA/HW_DIRECT, PUF v2 |

The 3-mode PYNQ client checks ID `0x514E5950` and refuses this overlay by design.

## Current candidate (2026-10-30, offline gates PASS, board NOT_RUN)

| Item | Result |
|---|---|
| Implementation | Performance_RefinePlacement, FCLK0 10.000 ns |
| Setup / hold | WNS +0.208 ns, TNS 0 / WHS +0.016 ns, THS 0 (66816 endpoints) |
| DRC / PS pins | 0 Error, 0 Critical Warning / no `Netlist 29-160` |
| RO structure | 1280 RO LUTs, 1280 inside `pb_ro_puf` |
| Resources | 18571 LUT / 32001 FF / 34.5 BRAM tile / 4 DSP |
| BRAM init | generated `.mif` = `ascon_keys.coe` word for word (32768 words) |
| HWH | `pynq_ctl_0` 0x40000000 ID 0x31554650 v1, `pynq_mbox_0` 0x40001000, FCLK0 100 MHz |
| Cosimulation | normal PASS (PASS line + DONE); mutant `KEY_USE_PUF=0` reports `FAIL dna-only fallback`, TB exits non-zero |
| Not signed off | no_clock 5824 + 5120 pins (RO/ro_clk domain), 27312 pins without max-delay constraint, 256 intentional loops |

Hashes: `candidate/sha256sums.txt`; full context: `candidate/manifest.json`.

Timing history on the same netlist and constraints (`candidate/reports/explore_impl.txt`):
the PYNQ-release strategy Performance_ExploreWithRemap failed (WNS -0.135 after its own
post-route phys_opt; extra phys_opt directives + reroute only reached -0.117). The failing
paths were inside the existing CPU (id_ex forwarding -> dcache store data, 9 logic levels,
~82 % routing), not in the PUF. Performance_Explore +0.031, NetDelay_high -0.097,
ExtraTimingOpt +0.154, RefinePlacement +0.208 (selected). No clock/XDC/exception change.
The candidate bit was written from that run by `finalize_run.tcl impl_5 Performance_RefinePlacement`;
`build.tcl` now uses the same strategy for a fresh build.

## Build and offline checks (repository root)

```sh
vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl -notrace
python -X utf8 sim/pynq_puf/run.py
python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf/package.py
```

`build.tcl` refuses an existing `build/local/pynq_puf/vivado` and stops (no bit copy) unless
setup WNS/WHS >= 0, no DRC Error/Critical Warning, no `Netlist 29-160`, exactly 1280 RO LUTs
and all of them inside `pb_ro_puf`. `sim/pynq_puf/run.py` runs the real RV32 with the COE
image, `pynq_ctl` reset release and AXI-Lite mailbox readout (behavioral RO/DNA, KEY_WINDOW
256). `package.py` re-checks both gates and writes `candidate/` with hashes.

## Board test

Copy the repository (or at least this directory with `candidate/`) to the PYNQ board:

```sh
sudo -E python3 board/vivado_zynq7000_xc7z020_pynq_puf/board_test.py \
  --candidate board/vivado_zynq7000_xc7z020_pynq_puf/candidate \
  --out data/pynq_puf/board_20261030_run1 --runs 5
```

The script verifies bit/HWH against `candidate/manifest.json`, downloads the overlay, checks
identity and FCLK0, then per run holds/releases the CPU reset and reads the ASCII log until
`DONE`. PASS = every run prints `PASS key subsystem: enroll + reconstruct stable`, no `FAIL`,
no mailbox overflow, and the same DNA in every run. Raw logs: `uart_runNN.txt`, summary
`result.json`. Exit code 0 only on PASS. Keep the output directory unchanged as evidence.

## Limits (do not claim)

- Each run enrolls again (helper is volatile): this is in-session repeatability, not
  cross-power-cycle reconstruction. Entropy, BER, temperature, uniqueness: not_measured.
- RO sampling domain is not timing-signed-off (unclocked/unconstrained endpoints remain; see
  `candidate/reports/check_timing.rpt`). Positive WNS covers defined clocks only.
- REF/RAW/MASK/DNA are readable over MMIO in PUF v1; no confidentiality claim.
- Board result is NOT_RUN until `board_test.py` output exists.
