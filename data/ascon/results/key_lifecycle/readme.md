# V06 review evidence, 2026-10-16

Owner TBD. `final_validation_summary.json` indexes the timing continuation;
`validation_summary.json` retains the pre-optimization review. Values are simulation
or implementation reports, never board measurements. `.log.gz` files are lossless
UTF-8 log compression; use Python gzip or any gzip reader. Scripts retain plain
logs when rerun. Test keys, nonces, plaintexts and derived answers are public.

- `host_after`, `c_failure_after`: full Final host KAT and raw failure-buffer gate.
- `rtl_final`: existing complete standalone regression, including official subset.
- `key_rtl_after`, `cpu_units`: new MMIO/ISE lifecycle and execution controls.
- `*_final`, `ise_security_final_verified`: final CPU runs; six rebuilt loadable
  images match those used in simulation (`final_firmware_rebuild.json`).
- `public_vectors`: three distinct public keys, 27 reference-derived cases,
  21 within MMIO capacity. References independently pass all 1089 official KATs.
- `*_before`: original main defects and initial runner compatibility failures.
- `ise_after` / `ise_security_after`: intermediate CPU failure before the missing
  early operand decode was repaired. `*_decode_fix` records that repair passing.
- `ise_security_final`: an intentionally stopped run after discovering the TB
  force/release reset remained asserted. `final_retry` has vvp PASS but runner
  FAIL due to GBK console encoding. `final_verified` is the successful UTF-8 run.
  Reset can interrupt the UART startup banner; byte-accurate PASS/count markers
  and the final CPU result are checked after restart.
- `rtl_after`: the initial 30-second outer timeout expired during concurrent
  Vivado/CPU load. `rtl_final` passes with a 120-second bound and unchanged RTL/TB
  watchdogs; this is not a changed golden answer.
- `vivado_attempt1/2/3`: missing optional glob, source language, and stale archive
  implementation-run metadata, respectively. The completed synthesis is reused
  by the new run via `build/build_ascon_review.tcl ... resume`.

No generated HDL, IP caches, firmware images, waves, DCP or bitstream is included.
Raw compiler/disassembly output is retained in compressed CPU logs. Protected
baseline/reference paths remain unchanged; `recovery_hash_check.log` verifies
all 579 restored assets. Broader limitations and interface changes are in
`docs/ascon_key_management.md`.

Continuation evidence:

- `*_timing_final`, `hw*_timing_r1`: final source-matched host/CPU runs. Round two changes only
  implementation strategy and reuses the identical RTL synthesis; no CPU result is reused across an RTL change.
- `rtl_timing_r1`, `key_rtl_timing_r1`: full standalone/reference and lifecycle regressions after the tail edit.
- `cpu_units_timing_final`, `rtl_harness_timing_final`: baseline/execute and negative-test harness gates.
- `tail_equivalence`: 867 requests, 43098 cycles, identical outputs and latency against original main.
- `final_validation_summary`: original and both new physical results, source/raw-report hashes,
  normalized LF source hashes, and a check that every final CPU input matches the implemented RTL snapshot.
- `vivado_timing_r2_attempt1`: pre-launch error using the property spelling as the run step name;
  no implementation ran. The corrected never-started run continues with `resume`.
