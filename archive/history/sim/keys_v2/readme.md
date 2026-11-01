# PUF v2 offline verification and parent handoff

> 2026-11-01 scope: independent keys_v2 architecture; PUF3 uses PUF v1, not this implementation.
> These offline tests do not close the invalid puf_v2 SoC candidate or establish board/PVT reliability.

## Measured synchronous timing follow-up

See `src/rtl/keys_v2/synchronous_timing_20261030.md` for the retained 32-step
quality accumulator and constant-word MMIO decoder, final all-five XSim and full
Icarus/CPU evidence, exact source snapshots, timing comparison and IO/RO limits.
The AEAD TB now covers every population 1..128 plus counting-phase cancellation;
its unchanged 2ms simulation watchdog accommodates the 748636ns passing test.
Host runner timeout is 360 seconds and captures timeouts as explicit exit124.

## CDC capture follow-up

The parent supplied five passing XSim tops and physical OOC evidence in
`data/advanced/puf/physical_ooc_20261030_0054`. The subsequent narrow CDC-1 fix adds
a core payload-capture/publication stage; these earlier physical results do not
validate the updated source. `tb_ro_health_v2` now checks isolated capture,
START/deadline/reset cancellation, async reset assertion with stopped clocks,
two-local-edge release, and the intentional whole-sample failure for one tied
pair. Review `src/rtl/keys_v2/cdc_review_20261030.md`; parent owns re-synthesis/XSim.

## MMIO / RV32 continuation

`tb_puf_mmio_v2` is now included in sources.json: normal and explicit diagnostic
variants run side-by-side; all 16 WSTRB masks, command-byte strobes, busy START/
helper rejection, complete-byte helper loading, DNA model/shift, normal read
suppression, reconstruct consistency, CLEAR/late completion and length=32 refusal.
Image tests verify internal-key 16B authentication, bad tag, changed authenticated
metadata, target-policy mismatch and readiness revocation on metadata/input edits.
Global watchdog is 2ms.

`cpu_sources.json` supplies exact additional CPU sources, testbench/tops and HEX
plusarg. `run_cpu.py` builds real RV32 firmware and executes `tb_puf_cpu_v2` plus
`tb_puf_cpu_diag_v2` with 20ms watchdogs. Sources come from both manifests; simulation
only DNA_PORT model must never enter synthesis. New physical top is
`puf_mmio_physical_v2`; original physical/direct-control entries remain available.

First CPU run retained in `data/advanced/puf/cpu_v2_20261030_003054_911062`:
normal firmware printed PASS but TB incorrectly required >=12 commands (normal
flow intentionally uses 11, diagnostic 14). Diagnostic run passed. Checker fixed
to exact 11/14 counts; this was a testbench expectation defect, not firmware/RTL
failure. Subsequent final evidence contains the corrected run; parent should
record this fact in root lessons/progress logs.

Task P-A/offline P-B, owner TBD, 2026-10-30. Parent owns shared Vivado session
`vivado-20261029-235723-83fb5dde`; this worker issued no Vivado Tcl and launched no
Vivado sessions. Existing keys/SoC/release/report/root logs were not edited.

## Reproduce

From repository root: `python sim/keys_v2/run_regression.py`.
Explicit extra backend: Icarus 14.0 devel (`iverilog -g2012 -Wall`, `vvp`),
Python 3.13.9, host GCC 8.1.0 (`-std=c99 -Wall -Wextra -Werror`). Runner preserves
commands, real exit codes, version output, raw logs and SHA-256 of source bytes
in unique `data/advanced/puf/offline_v2_<timestamp>/results.json` directories.
Initial and expanded runs are preserved; neither had a functional failure.

`sources.json` is the exact XSim source list/include directory/top manifest.
Set language SystemVerilog. Both TBs have `$fatal` on failure, terminal
`TEST_PASS <top>` markers and global watchdogs. `tb_ro_health_v2` maximum 200 us;
`tb_puf_aead_v2` maximum 2 ms. No board/UNISIM models are needed for these behavioral
tops. For physical synthesis additionally read physical_only_sources and choose
`puf_physical_v2`, target xc7z020clg400-1, with library LUT1/LUT2 primitives.
No board-level constraints or blanket clock exceptions are provided.

## Verified contract coverage

| Test | Checks |
|---|---|
| tb_ro_health_v2 | Mixed-direction response; actual saturating 4-bit counters; equal counts; all-same direction; injected zero snapshot; injected watchdog; error raw=0/valid=0/locked; reset recovery. |
| tb_puf_aead_v2 | Missing helper; enroll -> fixed-message encrypt -> reconstruct -> identical CT/tag; correct decrypt; every one of 128 single-bit tag corruptions rejected; changed DNA/internal key rejects old tag; output zero before auth. |
| same top | Full reset then import helper/reconstruct without reenrollment -> same CT/tag; corrupt reference; empty mask; stopped ro_clk core deadline; stopped oscillator management watchdog; overlapping key START; key revocation during AEAD; 17B rejection. |
| same top | Missing sample done; no late key resurrection; missing KDF done outer deadline; missing AEAD done deadline; reset during all five active sampler phases; successful recovery. |
| test_helper_v2.py | JSON roundtrip, wrong board/build/parameters, corrupted response checksum, unsupported interface, empty mask, unknown fields, duplicate keys, invalid/oversized schema; valid reload after corruption cases. |
| test_firmware_v2.c | Expected id completion, stale done ignored, explicit error, bounded timeout/clear, done without key, busy-start rejection, invalid API arguments. |

Synthetic deterministic oscillator clocks are NOT entropy models. Reusing the
same fixed nonce/message is only an isolated consistency test. These tests are
not a new independent official AEAD KAT campaign or functional/structural coverage
closure. Original unchanged crypto_aead is the integration dependency.

## Parent follow-up

Read `src/rtl/keys_v2/readme.md` for exact ports/errors/lifecycle/security gates.
Run the two tops under XSim and preserve actual exit/status/PASS markers against
the same hashes. Consider OOC physical synthesis to count loops and identify CDC/
unconstrained paths; do not equate elaboration or positive WNS with asynchronous
RO correctness. No board work authorized. Parent updates project logs/task state;
worker changes remain uncommitted.
