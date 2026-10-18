# dcache Pipeline Fix Checklist

**V10 retention update:** older RPTs, intermediate fix_r1/A/C JSONs and lint
reports referenced below were deleted at the user's request. Final V09
dual-strategy reports and current regression inputs are retained; see
[cleanup and fresh verification](workspace_cleanup.md).

**Latest continuation (V09, 2026-10-18):** A/C/B and dual-strategy validation
are complete. Final WNS is +0.001 / +0.007 ns, TNS=0 and 0 setup/hold failures
under existing 100 MHz constraints; IO/board signoff remains incomplete.
Store/MMIO cycles are back to HEAD. See [the current report](timing_acb_validation.md). The fix_r1
numbers and RTL descriptions below are retained as historical evidence.

For the AI working on the dcache timing optimization. All findings are from an
independent re-measurement after the 02:00-02:50 collision window; the earlier
"no effect / all RTL experiments failed" conclusions from that window are
invalid (two Vivado masters were fighting over the same project at the time).

## 1. CRITICAL — MMIO read deadlock (both variants hang the CPU)

**Symptom:** sw-mode regression TIMEOUT (8,000,000 cycles, no DONE, zero UART
characters). CPU never gets past boot.

**Debug trace** (`build/local/strategy_sweep_log/tb_ascon_sw_dbg.v`): at t≈275
the CPU is stuck at `pc=0x100083f0`, dcache `state=IDLE`, `cpu_stall_o=1`
forever, no bus activity, `rdata_valid_i=0` forever.

**Root cause:** the MMIO-read wait logic was rewritten:
- old: fixed 2-cycle shift
  (`mmio_read_wait_r <= mmio_read_now; uncached_req_r <= mmio_read_wait_r;`)
- new: wait for `bus_rdata_valid_i` to clear `mmio_read_wait_r`
  (`else if (bus_rdata_valid_i) mmio_read_wait_r <= 1'b0;`)

MMIO reads never produce `bus_rdata_valid_i`. In `src/rtl/bus_interconnect.v`,
the peripherals (CLINT/UART/GPIO/CPI/ASCON) are decoded combinationally from
`mmio_re` and return data one cycle later through `*_re_reg`. But
`cpu_rdata_valid` is driven only by `dcache_rdata_valid`
(`cache_rid_i == 1 && cache_rdata_valid_i`), which is the AXI cacheable-fill
path. So after an MMIO read nothing ever clears `mmio_read_wait_r`; it stays 1
and the CPU stalls forever. The first MMIO read during boot (UART/CLINT)
causes the hang, which is why zero UART characters come out.

**Fix (pick one, prefer b):**
- (b, recommended) Restore the fixed-latency wait for uncached reads and do
  not gate the stall on `bus_rdata_valid_i`. **Note that the shift must be
  re-aligned:** MISS_CAPTURE moves `bus_mmio_re_r` one cycle later than in
  HEAD (asserted at T+2 instead of T+1), so the peripheral data comes back at
  T+3. A plain copy of the old 2-cycle shift will sample `bus_rdata_i` one
  cycle too early. Derive `mmio_read_wait_r` / `uncached_req_r` from the
  registered `bus_mmio_re_r` (for example `uncached_req_r <= bus_mmio_re_r;`)
  so the alignment follows the request, not the detection cycle.
- (a) Add an explicit MMIO read-valid to `bus_interconnect.v`
  (`cpu_rdata_valid = dcache_rdata_valid | (|read_sel_q[5:1])`). This changes
  the interconnect interface and every consumer of `cpu_rdata_valid`; record
  it in `docs/interfaces.md` and re-run all modes. Do not gate on AXI
  `arready`/`awready`: MMIO does not go through AXI.

**Also fix — live signals used in MISS_CAPTURE.** `cpu_stall_o` is registered
relative to the request, so during MISS_CAPTURE `cpu_addr_i` / `cpu_re_i` may
already belong to the next instruction. Every MISS_CAPTURE decision must use
the captured values only:
- `next_state`: `captured_re && cacheable` → use cacheable of `captured_addr`
  (latch `captured_cacheable` in IDLE).
- `bus_mem_re_r` / `bus_mem_we_r` / `bus_mmio_re_r` / `bus_mmio_we_r`: same.
- `bus_load_miss_r` / `bus_store_miss_r`: `... && !hit` uses the live `hit`.
  Latch `captured_hit` (or `store_miss` / `load_miss_now`) in IDLE.

**Also note (performance, not correctness):** stores and MMIO writes now also
go through MISS_CAPTURE, so `state != IDLE` stalls the CPU for one extra cycle
on every store. Measure the cycle impact (`mcycle`) before accepting it. If
it is significant, only send load misses through MISS_CAPTURE.

## 2. Duplicate module files (already fixed — keep it that way)

`dcache_timing_optimized.v` and `dcache_aggressive_fsm.v` both declare
`module dcache`. Vivado does NOT error on this; it silently elaborates one of
them (file order), which contaminated an earlier timing measurement. They have
been moved to `src/rtl/dcache_experiments/` (kept, not deleted). Do NOT move
them back into `src/rtl/`, and never add another file declaring a duplicate
module name to the build glob.

## 3. Verification gates before any further timing work

- Screen script (isolated RTL copy, no working-tree changes):
  `bash build/screen_dcache_donttouch.sh dt|head`
  (`head` = committed original dcache, expected PASS)
- Full runner (native xpack toolchain):
  `python sim/ascon/run_cpu_regression.py --mode sw|hw|ise [--security] --label <name> --cc-prefix C:/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-`
- Hang-monitor TB for debugging:
  `build/local/strategy_sweep_log/tb_ascon_sw_dbg.v`

## 4. Timing status (Performance_ExplorePostRoutePhysOpt, xc7z020clg400-1)

| Version | WNS | TNS | Failing endpoints | Functional |
|---|---:|---:|---:|---|
| HEAD original | -0.177 | -2.968 | 31 | PASS |
| DONT_TOUCH variant (dcache_timing_optimized.v) | -0.078 | -0.594 | 14 | FAIL (deadlock) |
| MISS_CAPTURE variant (pre-fix dcache.v) | -0.055 | -1.122 | 40 | FAIL (deadlock) |
| MISS_CAPTURE fix_r1 (historical, see section 11) | -0.128 | -11.213 | 156 | PASS |
| V09 A+C+B (PostRoute, current RTL) | +0.001 | 0.000 | 0 | PASS (known ISA ma_data failure unchanged) |

V09 Remap strategy: WNS=+0.007, TNS=0, 0 failing endpoints, WHS=+0.023;
PostRoute WHS=+0.031. Both meet existing constraints, with only 1–7 ps setup
margin. See the current report for IO constraints, resources and the remaining
board verification gates. The subsequent fix_r1 analysis is historical.

The pipeline concept works for timing (WNS -0.177 → -0.055). After the
functional fix, the remaining worst path is
`id_ex_u/rs1_o_reg → u_dcache/captured_addr_reg/CE` — the miss-detect cone
moved onto the capture register's enable. Next timing lever: decouple that
enable path (enable capture unconditionally on every active request, or
precompute the enable one cycle earlier).

## 5. Evidence locations

- FAIL report: `data/ascon/results/key_lifecycle/sw_dcache_pipe2.json`
- PASS control: `build/local/strategy_sweep_log/dcache_head_screen.log`
- Timing reports (MISS_CAPTURE): `build/reports/dcache_pipe_20261018/`
- DONT_TOUCH measurement log: `build/local/strategy_sweep_log/vivado_dcache_pipe.log`
- Debug trace log: `build/local/strategy_sweep_log/dcache_pipe_regression3.log`
- Pre-change reference RTL: `git show HEAD:src/rtl/dcache.v`; manual backup
  in `src/rtl/dcache_experiments/dcache.v.backup_manual`

## 6. Fix order (do these in sequence, one change per verification run)

1. Check `git status`. Keep the uncommitted work of others. Make sure only one
   Vivado / simulation master uses the project (that is what caused the
   02:00-02:50 collision).
2. Fix the MMIO read wait (section 1, option b) and re-align it to the
   delayed `bus_mmio_re_r`.
3. Latch `captured_cacheable` / `captured_hit` in IDLE. Switch every
   MISS_CAPTURE decision and bus-request register over to them.
4. Run the hang-monitor TB. Confirm the CPU gets past `pc=0x100083f0` and that
   UART characters appear.
5. Run the sw / hw / ise regressions (plus `--security`) with the full runner.
   All must PASS with the same KAT results as HEAD.
6. Only after step 5 passes, re-run timing with the same strategy
   (`Performance_ExplorePostRoutePhysOpt`, xc7z020clg400-1) and fill in a new
   row of the table in section 4.
7. Only then try the next timing lever (`captured_addr_reg/CE` decoupling, see
   section 4), and repeat steps 4-6 for it.

## 7. Acceptance criteria (definition of done)

A dcache variant is "integrable" only when **all** of the following hold:

- [ ] `sw`, `hw`, `ise` regressions PASS, with and without `--security`. The
      JSON results are under `data/ascon/results/` with the tool and toolchain
      versions recorded.
- [ ] Ascon-AEAD128 KAT outputs are bit-identical to the HEAD control.
- [ ] Cycle counts (`mcycle`) are recorded for each mode and compared with HEAD.
      Any regression is stated explicitly, not hidden.
- [ ] Post-route timing for the same strategy and part is recorded: WNS, TNS
      and failing endpoints, with reports under `build/reports/<run>/`, plus
      `build_context.txt` (Vivado version, part, top, strategy, commands).
- [ ] Utilization is compared with HEAD (`route_utilization.rpt`).
- [ ] Only one file in the build glob declares `module dcache`.
- [ ] `project_log/actual_progress.md`, `project_log/lessons_learned.md` and
      the development log are updated.

Elaboration or synthesis alone is **not** a functional pass. A timing gain on a
functionally failing variant does not count (see the table in section 4).

## 8. Do not

- Do not report a WNS improvement from a variant that has not passed
  regression.
- Do not run two Vivado instances against the same project or run directory.
- Do not edit generated files (`.cache`, `.runs`, IP output products) to "fix"
  timing. Change the source or the Tcl script and regenerate.
- Do not move, rename or delete the baseline Vivado projects or
  `src/rtl/dcache_experiments/`.
- Do not change `bus_interconnect.v` / the CPU interface without updating
  `docs/interfaces.md` and re-running every mode.
- Do not commit or push. Leave reviewable working-tree changes.

## 9. Handoff report format

When handing back, report:

- Task ID (TBD if not assigned), owner: TBD
- Changed files and any interface changes
- Verification commands, tool/toolchain versions, exit codes and paths to the
  evidence files
- Updated section 4 table row (WNS / TNS / failing endpoints / functional)
- Cycle deltas compared with HEAD per mode, or `not_measured`
- What has not been verified yet, current blockers, and the next task to pick up

## 10. Open items

| Item | Status |
|---|---|
| MMIO read deadlock fix | done (fix_r1) |
| Captured `hit` / `cacheable` in MISS_CAPTURE | done (fix_r1, registered request-type flags) |
| Held `bus_mem_re_r` during FILL (found while fixing) | done (fix_r1, 1-cycle strobes) |
| Cycle cost of store-path MISS_CAPTURE | measured: sw +0.3%, hw +7.0%, ise +2.2% |
| Timing after functional fix | measured: WNS -0.128, not met (section 11) |
| `captured_addr_reg/CE` enable decoupling | not started (no longer the worst path) |
| ASCON ISE `s_reg` reset fan-out path (new worst path) | open |
| Board (PYNQ) run of the fixed dcache | not_measured |

## 11. Verification status — fix_r1 (2026-10-18)

Owner TBD. Base f52bc49 + working tree. `src/rtl/dcache.v` SHA256
`1A4FABCCB180F71802397251AF20F9248237C696135AE578DCAB4975E7B35ED8`.

**What changed in `src/rtl/dcache.v`:**

- MMIO read wait is a fixed shift aligned to the delayed request:
  `mmio_read_wait_r <= in_capture && cap_mmio_re_q; uncached_req_r <= mmio_read_wait_r;`
  (T: decode, T+1: MISS_CAPTURE, T+2: `bus_mmio_re_o`, T+3: data returned and stall released).
  No dependency on `bus_rdata_valid_i`. The interconnect interface is unchanged.
- Request-type flags `cap_load_miss_q / cap_store_q / cap_store_miss_q /
  cap_mmio_re_q / cap_mmio_we_q` are registered every cycle from the IDLE decode.
  MISS_CAPTURE (next state and all bus strobes) uses only these flags, never the
  live `hit` / `cacheable` / `cpu_re_i`.
- All bus request strobes are exactly one cycle. Before, `bus_mem_re_r` stayed high
  through FILL, so `bus_interconnect` queued a second, bogus read burst
  (`dcache_re_buf`).
- `captured_re` / `captured_we` were removed. The CE of `captured_addr/wdata/wmask`
  is unchanged (`load_miss_now || store_now || mmio_*_now`).

**Functional gates (Icarus, xpack riscv-none-elf-gcc 15.2.0-1):**

| Gate | Result | Evidence |
|---|---|---|
| 4.1 HEAD dcache screen | PASS | `build/local/strategy_sweep_log/dcache_head_screen_fix_r1.log` |
| Working-tree dcache screen (`screen_dcache_donttouch.sh wt`) | PASS | `build/local/strategy_sweep_log/dcache_wt_screen_fix_r1.log` |
| 4.2 sw / hw / ise | PASS (KAT 6/6, 7/7, 6/6) | `data/ascon/results/key_lifecycle/{sw,hw,ise}_fix_r1.json` |
| 4.2 hw / ise `--security` | PASS (123/0, 402/0) | `.../{hw,ise}_security_fix_r1.json` |
| 4.3 unit tests | PASS (4/4) | `.../cpu_units_fix_r1.json` |
| Extra: ise `--stall` / `--reset` | PASS | `build/local/dcache_fix_r1/reg_ise_{stall,reset}.log` |
| Ross `vivado-rtl-lint` (dcache only) | 2 warnings (ASSIGN-1, ASSIGN-6), identical to HEAD | `build/local/dcache_fix_r1/lint*/` |

`--security` needed `build/local/key_audit/key_cases.h`, generated by
`python sim/ascon/prepare_key_vectors.py` (27 public cases PASS against both references).

**Cycles compared with HEAD dcache (same toolchain, HEAD run in a temporary detached worktree):**

| Metric | HEAD | fix_r1 | Delta |
|---|---:|---:|---:|
| sw enc 16B / 32B | 17353 / 21515 | 17410 / 21588 | +0.3% |
| sw dec 16B / 32B | 17847 / 22094 | 17911 / 22171 | +0.4% |
| hw full MMIO | 670 | 717 | +7.0% |
| ise | 2496 | 2550 | +2.2% |

The cost comes from the extra MISS_CAPTURE cycle on every store and MMIO access.

**Timing (gate 4.4):** Vivado 2025.2, xc7z020clg400-1, top `top_pl_bram`,
`Performance_ExplorePostRoutePhysOpt` to post-route phys_opt. Isolated copy
`build/local/ascon_dcache_pipe_fix_r1`, run with
`build/build_dcache_pipe.tcl -tclargs fix_r1`, reports in
`build/reports/dcache_pipe_20261018_fix_r1/`, log
`build/local/strategy_sweep_log/vivado_dcache_fix.log`.

- `RESULT wns=-0.128 tns=-11.213 failing=156 whs=0.005`. Routing is complete with 0 routing errors.
- **Gate 4.4 is not met** (target WNS ≥ -0.078). **100 MHz timing is not met.**
- The post-place estimate was +0.221, but it did not hold after routing. Only the
  final post-route number counts.
- WNS improved compared with HEAD (-0.177), but TNS and the number of failing
  endpoints got much worse (-2.968/31 → -11.213/156).
- The worst 20 paths contain **no dcache cells**. The new worst path is
  `u_if_stage/pc_reg[5] → u_ex_stage/u_ascon_ise/u_p8|u_p12/s_reg_reg[*]/R`:
  8 logic levels, 79.8% route delay. This is the reset/flush fan-out of the ISE
  permutation state, so the large failing-endpoint count is most likely the
  wide `s_reg` bank on that one cone. The dcache change did not create this path.
  It most likely moved because placement changed. Not proven, and no per-endpoint breakdown was done.
- Utilization compared with the pre-fix MISS_CAPTURE build: LUT 11482 → 11536, FF 16025 → 16022, BRAM 38.5 / DSP 4 unchanged.

**Next:** analyze the `pc_reg → ascon_ise s_reg/R` path (pipeline or register
the ISE cancel/flush signal, or move the state clear off the synchronous reset pin).
Optionally run a lower-latency variant that sends only load misses through
MISS_CAPTURE (store/MMIO as in HEAD) to win back the hw +7% cycle cost.
Then re-measure with the same strategy and also with `Performance_ExploreWithRemap`.
