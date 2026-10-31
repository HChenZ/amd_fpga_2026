# Advanced DMA CPU validation handoff

Task: independent CPU-preserving DMA endpoint/firmware/host. Owner TBD.
Status: implemented and passing the executed no-board gates below. Root logs and
release files intentionally remain under the parent session's ownership.

## Final executed gates

| Gate | Result | Evidence under `data/advanced/dma_cpu/` |
|---|---|---|
| Native RV32 build, GCC 15.2.0 | PASS, all commands exit 0 | `build_20261030_0021/build.json` |
| custom-0 disassembly | PASS, 27 instructions, P12/P8/state read/write | `build_20261030_0021/dma_svc.disasm.txt` |
| Real CPU/AXI memory/endpoint/firmware | PASS, 95/95 packet cases | `20261030_002124_404425/run_1.log` |
| CPU cancellation/recovery | PASS partial request, actual ISE start, stalled response, post-reset KAT | same log |
| Endpoint BFM | PASS TKEEP 1/3/7/15, backpressure, invalid keep, overflow, watchdog, invalid commit, epoch abort | `unit_20261030_002131_789567/test_1.log` |
| AXI-Lite BFM | PASS AW-first/W-first, strobes, R/B stalls, identity/capacities, reset-only epoch writes | `unit_20261030_002131_789567/test_3.log` |
| Offline host | PASS 20 unittest methods | `unit_20261030_002131_789567/test_4.log` |
| Board source wrapper elaboration | PASS, exit 0, wiring-only | `unit_20261030_002131_789567/test_5.log` |

Icarus executable: `C:/wenjian/.vscode/iverilog/bin/iverilog.exe`, vvp alongside.
Exact commands, exit codes and version logs are in each run directory.
CPU test ran to 13,573,710 ns with a 1-second simulated-time global watchdog.

The 95 cases comprise 26 selected official KAT vectors, each encrypted,
decrypted and tag-tampered (78 transactions), plus 17 protocol/session/capacity
rejections. A further recovery encryption is checked after cancellation tests.
Lengths cover 0,1,7,8,15,16,17,31,32 as appropriate; HW remains <=16.
The test parses the repository's pinned official KAT via `parse_kat()` and runs
the actual CPU instruction stream, cache, bus, ISE and MMIO accelerator. There
are no crypto stubs. Header and payload bytes are checked; measured cycles are
not compared against invented constants, and failure cycles must be zero.

Malformed cases include version/flags, unsupported operation/mode, bad lengths,
capacity, missing/extra body bytes, wrong/zero epoch, zero/repeated ID. Invalid
TKEEP or missing TLAST reaches the endpoint fault/reset path in the unit TB.

Earlier passing runs remain available (`20261030_000947_944363`,
`20261030_001530_008597`, `unit_20261030_001353_865162`). The final firmware added
explicit HW timeout distinction and capacity guards; the final 95-case run uses
the new firmware hash, not those earlier images.

## Reproduction and XSim

Use `run_unit.py` and `run.py` with explicit `--iverilog` / `--vvp`. The latter
expects `build/local/pynq_dma_svc/dma_svc.hex`. Unique evidence directories are
created for each run; terminal PASS markers are required in addition to exit 0.
The four readmemh "not enough words" warnings reflect deliberately oversized
static TB arrays; accesses are bounded by generated per-packet sizes/counts.

Exact XSim source manifest:
`data/advanced/dma_cpu/20261030_002124_404425/sources.json`.
Top `tb_dma_cpu`; includes `src/rtl`, `src/rtl/ascon`; all files SystemVerilog.
Plusargs:

```text
HEX=<absolute path>/build/local/pynq_dma_svc/dma_svc.hex
DATA=<absolute path>/data/advanced/dma_cpu/20261030_002124_404425
CASES=95
```

Unit XSim tops and exact two-file source sets are in the independent board
handoff readme. At the initial handoff the parent owned Vivado and no separate
session was opened. The authorized continuation below uses an independent session.

## Remaining validation

- The initial handoff had not run XSim or implementation. The continuation below
  supplies actual implementation, bit/HWH and vendor-IP XSim evidence. Physical
  PYNQ/DDR execution remains unmeasured.
- No physical board, PYNQ allocation/cache API or DDR DMA hardware was available.
  Host tests use explicit fake adapters and are not crypto/performance evidence.
- The initial result above was directed KAT coverage. The continuation below
  completes all supported official vectors. Long-run stability, throughput
  saturation and fault-injected HW timeout are still not measured.
- Cross-platform WSL compiler was absent; native xPack compiler was used. XSim
  execution was subsequently completed as recorded below.
- The real PYNQ backend retains globally referenced buffers on failed quiesce;
  keep its process alive until recovery/hardware reset, as documented for bringup.

Next receiver: parent session for shared direct-core control-map adoption,
Vivado/XSim checks, independent BD creation and board bringup. Firmware SHA-256,
control map and notebook example are in the owned firmware/RTL/board readmes.

## 2026-10-30 continuation: full KAT, scrub-aware host, permanent CLI

New repeatable full regression entry:

```text
python sim/pynq_dma_cpu/run_full.py --iverilog <iverilog> --vvp <vvp> --workers 10
python sim/pynq_dma_cpu/verify_full.py <full_evidence_directory>
```

`run_full.py` compiles one real-CPU snapshot and splits official vectors into
bounded independent simulation processes. SW/ISE each cover all 1,089 vectors;
HW covers all 289 capacity-supported vectors. Every vector has encrypt, decrypt
and bad-tag rejection: 7,401 cryptographic transactions total, plus the 17
protocol negatives and reset/recovery checks in every shard. There is no crypto
stub and no production RTL or firmware modification for the full run.

Run directory: `data/advanced/dma_cpu/full_20261030_002958_293520/`.
`xsim_all/` contains all 7,418 unsharded packets and exact source/plusarg manifests.
Every shard has its own command log, terminal PASS requirement, source identities,
version logs and vectors. `verify_full.py` independently parses request/response
bytes against the pinned official KAT, checks uniqueness/completeness, vector
hashes, source hashes, snapshot hash, per-case markers and reset markers.
Both `--vectors-only` and final result verification passed. Final Icarus run:
**PASS**, 19/19 shards, 7,401/7,401 cryptographic transactions, SW 1,089/1,089,
HW 289/289, ISE 1,089/1,089. Every shard also passed 17 protocol negatives,
partial/active-ISE/pending-result cancellation and a recovery KAT. Thus the
executed sharded packet count is 7,724 plus 19 recovery encryptions; the unsharded
XSim file has 7,418 packets because its protocol negatives occur once.
`result.json` records all exit codes and snapshot SHA-256; `verified_full.json`
records the independent full-results/vector audit. Icarus is 14.0 (devel).
Measured host simulator elapsed time was 1,779.967 seconds; it is not board
latency or a CPU benchmark. Firmware binary/HEX hashes remain those in the
firmware readme and each manifest; no firmware rebuild was needed for full KAT.

Continuation host/CLI/RTL unit gates passed in
`data/advanced/dma_cpu/unit_20261030_005944_999468/`:

- 30 host unittest methods, including direct-core scrub wait, timeout/abort,
  fresh DMA completion events, actual S2MM length, buffer retention, close and
  interruption during launch/cleanup.
- 10 CLI methods: all official counts through an explicitly simulated adapter,
  1,024-byte direct-mode benchmark orchestration, identity rejection, nonzero
  failures, quarantine ownership, and raw-MMIO creation without a DMA driver.
- Endpoint/control RTL tests, executable CLI `--help`, and board-wrapper
  elaboration passed. The unit directory records source hashes and exit codes.

Permanent CLI: `board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py`.
PYNQ 2.7 source audit and lifecycle details: sibling `pynq27_audit.md`.
The host waits for idle-ready after response completion (including error replies),
so direct-core output scrubbing does not make the next transaction fail. Transport
errors hold endpoint/CPU reset before DMA reset/halted proof. Closed transports
cannot be recovered after releasing their process lock.
The final review also fixed interruption cleanup: `KeyboardInterrupt` after
publishing an RX address must abort/quiesce, and interruption inside quiescence
must retain buffers rather than allowing exception unwinding to release them.
Both cases are now checked by the final host regression.

### Preserved failure and correction

`unit_20261030_004149_514085/test_5.log` preserves the first CLI test failure:
the injected reference adapter used `capabilities` instead of the actual
transport's `capacities` attribute. Correcting that adapter exposed the intended
tests without changing hardware/protocol checks. Subsequent full unit runs passed;
the original failure was not deleted or reclassified as PASS.

The later authorized continuation supersedes the earlier XSim/PPA limits.
The permanent CLI is executable and offline-tested, not a claim of board results.

## Final authorized non-board results

- Own Vivado Tcl session: `vivado-20261030-010908-1cbde35d`; neither parent session
  was used. Actual project `build/local/dma_cpu/fclk80/cpu_dma.xpr`.
- Qualified **80 MHz** bit/HWH: `data/advanced/dma_cpu/vivado_20261030_040257/candidate/`.
  WNS +0.601 ns, hold +0.024 ns, period 12.500 ns, error/critical DRC 0 and invalid
  PS-pin constraints 0. Actual LUT 17179, FF 21936, BRAM 36.5, DSP 4. Five LUTAR-1
  warnings remain; no waiver, severity downgrade or Fmax extrapolation.
- Fixed-port **100 MHz failed** by 0.046 ns on the existing high-fanout cache path.
  A bounded legal post-route optimization made no change. Failure/DCP/path
  evidence remains in `vivado_20261030_025251` and `physopt_20261030_030502`.
  The earlier internally wired PS-port build `vivado_20261030_015408` is
  superseded and not deployable, despite its positive PL timing.
- Full **unsharded XSim 7418/7418 PASS**, plus partial/active-ISE/pending-result
  cancellation and recovery KAT, in `xsim_20261030_014606_238543`. This uses the
  actual CPU firmware, vendor AXI BRAM controller and initialized block memory,
  not the Icarus memory BFM. Simulated time 1,495,022,810 ns; runtime wall duration
  10,070.438 s. These are simulator quantities, not board benchmarks.
  `verified.json` independently checks markers, count, error/fatal messages and
  unchanged compiled-source hashes. Compile/elaborate PASS evidence is in
  `xsim_20261030_013758_403545`; its original unquoted-Windows-plusarg runtime
  FAIL remains recorded. Only the corrected invocation was rerun.
- Real AXI DMA 7.1 + CPU/control wrapper + vendor private BRAM **95/95 PASS** in
  `xsim_20261030_030042_215364`, independently verified. Includes DMA soft reset,
  both halted flags, fresh IOC events, actual S2MM_LENGTH, RX-before-TX ordering,
  guard bytes, odd lengths and 4 KiB burst splitting. The PS-memory BFM is limited
  to aligned 32-bit INCR bursts, single outstanding read/write and random stalls;
  it is not PS/DDR silicon or the 64-bit HP upsizer model.
- XSim endpoint/control/reset units all PASS; see the board readme for directories.
- Final Icarus units, **32 host tests**, **10 CLI tests** and wrapper elaboration
  PASS in `unit_20261030_043721_118939`. Host inputs freeze byte contents and
  lengths before control callbacks; tests cover caller mutation and array byte
  counts as well as scrub waiting, deadlines and buffer lifetime.

Paths above are under `data/advanced/dma_cpu/` unless fully qualified.
Native functional simulations ran at a 100 MHz behavioral clock; the qualified
physical artifact is the separately configured 80 MHz design with the same CPU,
endpoint and firmware logic. No post-route SDF or physical-board claim is made.
Board-only cache behavior, platform clock interpretation, DDR electrical behavior,
sustained board stability and performance remain for hardware bringup.
