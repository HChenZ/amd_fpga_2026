# Completion capture and reset-path review

Task P-A CDC follow-up, 2026-10-30, owner TBD. Input evidence:
`data/advanced/puf/physical_ooc_20261030_0054/cdc.rpt`, synthesized
`puf_mmio_physical_v2`, Vivado 2025.2. Parent reported all five XSim tops passed
and OOC synthesis preserved 1280 ring LUTs. Those results predate this change;
parent must resynthesize and rerun the changed testbench before updating signoff.
No Vivado command, constraint, CDC waiver or timing exception is added here.

## CDC-1: stable payload was decoded before core capture

The supplied report identifies:

- management `sample_error_reg[5]` -> core `locked_reg`;
- management `sample_error_reg[4]` -> core `valid_reg`.

Even though source result/error is held before its completion toggle traverses
the three-stage cp synchronizer, the previous RTL put an asynchronous multi-bit
zero/nonzero decode directly in destination status D cones. The revised RTL:

1. Detects completion using final `cp[2]` versus registered `cp_seen` only.
2. Copies source `result` and `sample_error` directly into core-domain
   `captured_result` and `captured_error`, setting `capture_pending`.
3. On the next core edge, publishes raw/error/valid/locked using ONLY those
   core-domain registers, then erases capture buffers/pending.

Normal completion latency increases by one core cycle. It remains busy during
capture, and done/valid stay low. Priority is reset, START, core deadline,
pending publication, new completion capture. START or deadline erases pending
payload, publishes the existing explicit failure, and prevents later success.
Reset clears both pending and data immediately. Deadline is not extended by a
capture: a result captured on the last allowed cycle is rejected if the following
publication edge reaches the deadline. Ports, error bits, and transaction IDs are
unchanged.

This is still **bundled-data CDC**, not a per-bit double-flop bus synchronizer.
Source result/error and complete are registered on the same management edge;
result/error hold until another accepted sample/reset. Destination capture occurs
only after completion crosses three flops. Physical source-to-capture data paths
must arrive within that stability window, and source hold must cover capture.
CDC-15 warnings on direct payload capture are therefore expected to need path-
specific analysis. The added register does not excuse arbitrary bus skew/delay
or prove the existing RO-clock/ack/snapshot paths safe. Parent should verify the
new captured registers remain in the synthesized topology and the reported
CDC-1 direct decode paths disappear, rather than merely comparing warning counts.

`tb_ro_health_v2` now checks capture-before-publication, faults the asynchronous
payload *after* capture to prove publication uses the core copy, and separately
cancels pending success with START, deadline and reset. This deliberate payload
fault violates normal source hold only for testing the registered boundary.

## CDC-10: clear -> reset-release synchronizer CLR

Exact reported destination:
`peripheral/keys/sampler/ro_reset_release_reg[0]/CLR` from
`peripheral/clear_reg` (report row lists its source clock pin). This is not the
functional D input of the request/data synchronizer. Actual RTL path is:

`puf_mmio_v2.clear` (core-clock register)
-> `puf_key_v2.local_rst_n = rst_n && !clear`
-> asynchronous reset pins of `ro_reset_release[1:0]`
-> final `ro_reset_release[1]` drives management-local reset.

The two reset-release flops both asynchronously clear to 0. With input reset
released, they shift `{old_stage0,1}` on management-clock edges. Local reset stays
asserted through the first edge and deasserts after the second; management logic
can first operate on the next edge. Each RO counter separately implements the
same two-stage release chain in its oscillator domain. There is no combinational
path that directly deasserts management or oscillator functional-register reset.

This **intentional async-assert/sync-release** is needed: a stopped management
clock or dead oscillator must still clear state when the core issues recovery.
Replacing async clear with a normal two-flop data synchronizer would lose that
recovery property. The combinational reset merge is retained, with these explicit
conditions (not a blanket CDC waiver):

- Runtime clear is a single core-clock register output, not a combinational bus
  decoder. It is asserted for a full core period; global rst_n stays high during
  an ordinary software clear, leaving only one changing merge input.
- Global reset assertion is clean; release is core-clock synchronous with clear
  already reset low. Do not independently toggle global-reset release and clear
  assertion as unrelated asynchronous sources. Direct-control users must satisfy
  the same documented clk-synchronous clear contract.
- Physical implementation must verify reset minimum pulse width at destination
  CLR pins, ASYNC_REG placement, actual local reset fanout, and recovery/removal
  timing from the final release stage to functional registers. A one-core-period
  pulse is a functional specification, not a measured routing/pulse-width proof.
- If a destination clock is stopped, both release stages stay at zero even when
  clear goes away; operation cannot resume until two destination edges occur.
  The core sampler's own reset release is clk-synchronous because clear is
  registered in that domain; system rst_n must obey its core-release contract.

Directed simulation now stops both management and oscillator clocks, asserts
reset, checks local reset assertion without clock edges, releases the input and
checks local resets remain asserted, then checks two-edge local release and a
successful new sample. Existing integration tests exercise software CLEAR and
stopped-clock fault recovery. Simulation does not establish analog metastability
MTBF, minimum reset pulse widths or physical reset recovery/removal closure.

## Strict health policy retained intentionally

The current sampler rejects the **entire 128-bit acquisition if any pair ties**,
has zero counts or reaches saturation, and rejects an all-same-direction vector.
The new directed test includes one tied pair with the other pair healthy; the
whole sample must still return valid=0/raw=0/locked=1. Consequently a single tied
pair on hardware can prevent enrollment. This is an intentionally conservative
fail-closed prototype policy, not a claim that all 128 physical pairs will pass.

Enrollment's multi-sample mask only filters direction instability among otherwise
healthy complete acquisitions; it does not rescue locally unhealthy pairs. Quality
counts selected engineering bits, not entropy or security strength. Physical data
may motivate a separate reviewed per-bit validity interface/window policy later;
this narrow CDC repair does not silently relax health checks or invent ECC/entropy.
