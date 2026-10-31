# Measured synchronous timing repair

2026-10-30, owner TBD. Final implementation uses Vivado 2025.2, xc7z020clg400-1,
top puf_mmio_physical_v2, out-of-context mode. Only yielded general session
vivado-20261030-004722-a44ab1cf was used. Original RTL/release/root logs unchanged.

## Two substantiated RTL changes, same implementation conditions

1. **puf_key_v2:** original mode -> 128-bit population sum -> helper-write control
   was the measured -1.082ns setup path. Replace it with a 128-bit shift register,
   balanced 4-bit local count, 8-bit accumulator and 32 fixed nibble steps. Capture
   reconstruction mismatch in its own register before the final decision. The
   final compare/helper update is a separate cycle. This removes the large count
   cone from helper write enables, rather than hiding it with a timing exception.
2. **puf_mmio_v2:** after the first repair, the worst path was addr -> combinational
   rdata (-0.945ns) with the same 2ns input and 2ns output budgets. Replace range /
   address subtraction / variable part-select read logic with explicit constant
   register-word selects. Bus timing, ports, register map and response latency do
   not change. No register stage or handshake delay was added to MMIO.

Only these two measured edits were tried. Both used the same default synth,
opt_design, place_design, route_design flow, the same clocks/constraints and the
same provisional IO budgets. No strategy sweep, new false path, relaxed frequency,
invented RO bound, or relaxed interface delay was used.

## Results

| Source variant | Whole defined-path setup WNS | TNS | Core internal max/min slack | IO-inclusive WHS |
|---|---:|---:|---|---:|
| Baseline | -1.082ns | -370.555ns | worst setup was internal key-quality control | -0.502ns |
| Serial quality only | -0.945ns | -13.052ns | +1.029ns / +0.098ns | -0.502ns |
| Serial quality + constant read decode (retained) | **+0.054ns** | **0ns** | **+1.648ns / +0.098ns** | **-0.502ns** |

The retained design has **zero failing setup endpoints among currently defined
paths**. Core register-to-register setup and hold meet this OOC model. Management
internal max-path slack is +5.070ns (worst is local-reset recovery), and min slack
is +0.097ns. Full timing is still **NOT MET** because 823 IO-inclusive hold endpoints
fail (THS=-231.510ns). The complete summary and the unchanged original boundary
trace are retained; reporting internal paths does not exclude them from analysis.

Final routed resources: 25,021 LUTs, 20,328 registers. All 38,905 routable nets
routed, zero routing errors. Exact ring/CDC audit still passes: 256 five-LUT loops,
1280 ring connections, 2568 ASYNC_REG flops, 133 payload-capture flops. CDC-1 remains
absent. CDC-10 reset merge / CDC-15 bundled capture remain explicitly documented.

## Bounded operation and lifecycle

After acquisition, state 2 captures count input, comparison flag and private
candidate material. State 5 performs exactly 32 steps; state 6 checks count and
mismatch, publishes quality, commits helper only on success, and advances to KDF.
This adds **33 core cycles** versus the previous single-cycle quality decision.
The existing outer deadline `(CORE_DEADLINE+32)*SAMPLES+128` remains unchanged;
the added work fits its fixed overhead allowance. If the deadline nevertheless
expires, the existing fail-closed 0x85 behavior has priority, including during
counting. START/CLEAR/reset erase count/candidate state. No key becomes valid
before successful completion. Ports/error codes/helper semantics are unchanged.

Regression checks all populations **1 through 128**, exact quality values, the
63/64 threshold, zero-mask rejection, START/CLEAR cancellation during count,
enroll/reconstruct consistency, all bad-tag cases, missing completions and recovery.
The MMIO test independently checks each of 24 staging word addresses and normal
versus diagnostic read access, plus unaligned/reserved read rejection.

## Evidence

- Original failed path / original IO hold trace / baseline source:
  `data/advanced/puf/physical_final_20261030_0121/`.
- Serial-only DCP/source snapshots/reports:
  `data/advanced/puf/physical_quality_20261030_021240/`.
- **Retained routed DCP/reports/topology/source snapshots/hashes:**
  `data/advanced/puf/physical_quality_decode_20261030_023728/`.
- Final full Icarus/helper/HAL suite (exit 0):
  `data/advanced/puf/offline_v2_20261030_022850_012028/`.
- Final actual RV32 CPU normal/diagnostic executions (exit 0):
  `data/advanced/puf/cpu_v2_20261030_022902_404177/`.
- Final all-five-top XSim suite (exit 0):
  `data/advanced/puf/xsim_final_20261030_022912/`.

The first expanded population sweep exceeded the old **120-second host wall-clock
limit**, not the HDL watchdog. The inconclusive run and exception record remain in
`offline_v2_20261030_020237_959932`. The runner now preserves timeout stdout/exit124
and allows 360 seconds. The unchanged HDL watchdog is 2ms; the expanded AEAD test
completed at 748636ns in both Icarus and XSim. No checker was weakened.

## Conditional boundary and RO status

Core=100MHz and independent management=25MHz. External input/output budgets remain
max=2ns, min=0ns, exactly as baseline. The -0.502ns hold trace is an external
input-to-register path under these provisional integration assumptions. No measured
board launch delay, BUFG source site or real top-level clock skew was invented.
These assumptions must be replaced/verified in the actual integration; the current
positive internal slack is not unconditional silicon signoff.

No justified oscillator minimum period was supplied. RO timing remains
NOT_MEASURED with 7424 no-clock pins and 18688 unconstrained internal endpoints.
The guarded physical helper still requires an explicit external RO bound/provenance
before it creates oscillator clocks. No entropy, ECC or BER claim follows from
the digital setup fix. See physical_readme.md and cdc_review_20261030.md for those
unchanged boundaries.
