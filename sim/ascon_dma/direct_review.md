# Direct core lifecycle review / handoff

> 2026-11-01 scope: HW_DIRECT lifecycle checks for the recorded experiment source, not PUF3 security acceptance.
> Keep historical PASS/FAIL and source hashes; current entrypoints are listed in docs/version_entrypoints.md.

2026-10-30; owner TBD. Verification-only subtask; production RTL/host unchanged.

## Parent fixes verified: strict PASS

Latest command: `python sim/ascon_dma/run_lifecycle.py --backend iverilog`, exit 0.
Evidence: `data/advanced/dma_direct/lifecycle_20261030_012755_701862/`.
Normal compile/run exits 0/0 with **201 checks**; LOAD_REVOKE and SYNC_GATE
focused replay exits both 0. Both assertions now execute unconditionally in
the normal positive suite, with nonzero/valid-result preconditions to avoid
vacuous success. Address latency checks cover valid-to-invalid and
invalid-to-valid transitions. Probe flags only shorten the replay after PASS.
The runner requires normal PASS, both probe PASS markers/exits, and successful
mutation compilation followed by runtime `BAD_TAG_ACCEPTED` failure (exit 1).
Summary status is **PASS**, with no open-probe exemption.

Tested core SHA-256:
`cf7e413314fb24a4ac52eb62d97ebe9c17d16daa6136c9751a0535f39d2098e4`.
The snapshot/live-source comparison at completion reports unchanged. Compare
this hash against the synthesis source snapshot before using earlier PPA.
The current normal TB finishes at 2,204,367 ns; watchdog remains 200,000,000 ns.
All original failure snapshots and logs listed below are preserved.

### Reset boundary: read-only audit

The core's memory/read-valid process (`ascon_aead_multiblock.v:46-48`) and
state/control process (`:61-66`) are `always @(posedge clk)`: `rst_n` and CLEAR
are **synchronously sampled**. Neither uses an asynchronous reset sensitivity
edge. After an asserted reset/CLEAR is sampled, success/tag/result visibility
is revoked and scrub begins. Memory scrub takes subsequent active clocks;
holding reset asserted prevents scrub progress until reset is released.

There is no promised immediate, between-clock output suppression when rst_n
falls, and no guarantee for a reset pulse that misses every rising edge.
Existing lifecycle tests drive reset/CLEAR before a rising edge and inspect
after NBA, consistent with this synchronous boundary. They do not certify
asynchronous reset assertion/release, CDC, pulse capture or physical clearing
without clocks. No asynchronous-reset defect is asserted or inferred.

## Historical executed evidence (before parent fixes)

Command: `python sim/ascon_dma/run_lifecycle.py --backend iverilog` (exit 0).
Historical evidence: `data/advanced/dma_direct/lifecycle_20261030_012056_377384/`.
`summary.json` records source/vector/oracle SHA-256, exact commands and exits;
`tool.log` records native Icarus version. No board or Vivado/XSim execution here.
Earlier lifecycle directories retain intermediate test revisions and results.

- Normal compile/run: 0/0, explicit `TEST_PASS`, 199 counted checks.
- Official pinned KAT 0001/0545/0579/1089: AD/message lengths 0/16/17/32;
  maximum 1024 uses the separately pinned upstream Python oracle and fixed seed,
  **not** an official 1024-byte KAT and not the production algorithm as oracle.
- Encryption/decryption/bad tag with all live control/data pins disturbed while
  busy; repeated START and memory writes; simultaneous START/load priority.
- Every one of 128 tag bits rejected on the 17-byte official KAT. All candidate,
  AD and input memories checked zero after failed authentication.
- Reset and CLEAR each tested at all 14 reachable FSM states, including PERM,
  AD/MSG fetch/consume/pad, VERIFY and failure scrub. Each abort is followed by
  a fresh authenticated operation; no ghost completion; memory/secret scrub.
- New START revokes old result; busy/failure output checked every clock;
  length 1025 rejected; done pulse checked; valid-address synchronous RAM read
  latency checked before and after the sampling edge.
- Isolated source mutation changes `enc || computed_tag == expected_tag` to
  `enc || 1'b1`. Compile exit 0, run exit 1 at `BAD_TAG_ACCEPTED bit=127`,
  11320 ns. This is functional mutation detection, not a compile failure.

Overall summary is `PASS_WITH_OPEN_CONTRACT_PROBES`, not an unconditional
closure of the following two interface findings.

## Historical reproduced findings (resolved by parent, verified above)

1. **Accepted input LOAD retains previous authenticated result.**
   `src/rtl/ascon_dma/ascon_aead_multiblock.v:51-52,73-85` writes new input in
   IDLE, but clears success/tag only on START. `:42` therefore still exposes
   old result while new input is being loaded. Diagnostic `+PROBE_LOAD_REVOKE`
   fails at 23327 ns (`probe_load_revoke.log`, exit 1).
   If first LOAD begins ownership of a new operation, revoke success/tag there.
   Otherwise explicitly document that only START/CLEAR/reset revokes results.
   The AXIS wrapper clears between packets, so this is **not demonstrated as
   a DMA packet plaintext leak**. The current written contract does not define
   input-load revocation; do not silently label the probe passed.

2. **Result data is synchronous but address-valid gating is asynchronous.**
   `ascon_aead_multiblock.v:42,46`: `result_q` belongs to the sampled address,
   whereas `result_addr < plen` uses the live address. Changing valid to invalid
   before the next clock immediately changes output to zero. Conversely,
   invalid-to-valid can expose the previously sampled invalid-address byte
   until the next edge. Diagnostic `+PROBE_SYNC_GATE` fails at 23331 ns
   (`probe_sync_gate.log`, exit 1). Valid-to-valid latency tests do pass.
   If the declared one-cycle contract covers the whole output, pipeline the
   address-valid qualification with the RAM read (retain immediate lifecycle
   suppression for abort/busy). If intentional, document the mixed-latency
   interface and require consumers to wait a clock after address changes.
   `ascon_axis_direct.v:143-149` supplies FETCH settling cycles, so this review
   does not establish a wrong DMA response from this standalone-core issue.

## Other read-only review observations

- RX capacity count saturates at the configured bound (`ascon_axis_direct.v:
  97-100`); overflow marks a bad packet. A bad packet with no TLAST still
  advances the watchdog (`:93-95`). No wraparound defect found at MAX_BYTES=1024.
- SEND watchdog (`:151-158`) saturates by leaving its counter unchanged once
  the threshold is hit; it latches fault while retaining stalled AXIS data.
  This preserves AXIS stability; recovery is external, not autonomous return
  to idle. Host polls fault and requests reset/quiescence (`dma_transport.py:
  225-226,248-271`). Do not call it automatic packet cancellation.
- Epoch writes are gated by held reset (`dma_direct_top.v:65-67`). Identity,
  mode-4 capability/max-length offsets match host `_caps()`; no ABI mismatch
  found in the reviewed snapshots.
- No early successful publication found: core VERIFY gates success and failed
  authentication waits for scrub before done. This is directed simulation,
  not formal security/physical-zeroization proof.

## Parent XSim / task-log handoff

Use the **normal** three files in `sources.json`, top `tb_core_lifecycle`, and
the listed `+VECTORS=...` argument. The TB has a fatal 200,000,000 ns watchdog;
normal Icarus completion is 2,204,317 ns. The mutation file must only replace
the core for its separate negative run, never enter the normal source set.
`--prepare-only` emits a fresh frozen source/vector manifest without simulation.

Parent owns shared logs/task board: append actual progress/development activity
and keep the two failing contract probes visible in lessons/remaining work.
This subtask intentionally writes only its assigned TB, runner, review note
and `data/advanced/dma_direct/lifecycle_*` evidence. No commit/push.
