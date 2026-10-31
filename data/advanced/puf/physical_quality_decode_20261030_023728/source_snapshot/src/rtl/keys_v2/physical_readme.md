# Final offline physical preparation (2026-10-30)

**Historical baseline:** subsequent measured RTL fixes and retained results are
in `synchronous_timing_20261030.md`. The failures below are preserved evidence;
they are not the final current digital setup result.

Owner TBD. Vivado 2025.2; target xc7z020clg400-1; top puf_mmio_physical_v2;
`synth_design -mode out_of_context`. Only yielded general session
vivado-20261030-004722-a44ab1cf was used. No board, bitstream, eFuse, package pin
assignment, released-original change or root-log edit.

## Evidence and actual result

- Five bounded XSim tops PASS on the final payload-capture RTL:
  `data/advanced/puf/xsim_final_20261030_011517/`.
- OOC synth/opt/place/route and reports:
  `data/advanced/puf/physical_final_20261030_0121/`.
- Raw, placed, initial-routed and final-routed DCPs retained.
- Exact source/artifact SHA-256 and full session log: `verification_manifest.json`
  and `vivado_session_full.log` in the physical evidence directory.

All 39,514 routable nets routed; zero routing errors. Final LUTs=25,453,
registers=20,187. Exactly 256 five-LUT rings, 1,280 verified ring arcs, 2,568
ASYNC_REG flops, and 133 core payload-capture registers survived routing.
`topology_final.tsv` gives cell locations/BELs, attributes and every ring link.
No package pins assigned; OOC clock sources have no invented HD.CLK_SRC site.

CDC-1 count is **zero** in new synthesis and final routed reports. CDC-15=133
is the explicit bundled-data capture boundary; CDC-10=1 is the documented
async reset merge. These counts only cover domains with defined clocks and are
not full RO-domain CDC signoff.

**Timing is NOT MET:** WNS=-1.082ns, TNS=-370.555ns (713 failing endpoints),
WHS=-0.502ns, THS=-232.850ns (831 failing endpoints). Worst setup is
`keys/mode_reg_rep__1` through quality/popcount control to `keys/mask_reg[35]/CE`,
11 logic levels / 10.793ns data delay. Worst hold is MMIO wdata[0] to
data_length_reg[0]/D under provisional zero-minimum external input delay.
No exception was added to hide either violation. Real clock-source placement and
top-level timing budgets are required before these OOC values can represent an
integrated design. Future concrete RTL work may pipeline quality evaluation; no
unrequested timing-driven RTL change was made in this run.

RO bound was **not supplied**. There are 7,424 non-clocked sequential pins and
18,688 unconstrained internal endpoints in this structural scenario. Methodology
lists 1,000 TIMING-17 examples (report cap), not the full count. No positive slack
in the management domain or completion bus overrides this missing coverage.

## Constraint helper and assumptions

`physical_constraints.tcl` is a post-synthesis, fail-on-count-mismatch helper.
It does not waive checks or apply asynchronous clock groups. It verifies exactly
256 five-LUT rings and acknowledges only their enumerated feedback nets using
ALLOW_COMBINATORIAL_LOOPS. Other loops remain unacknowledged. No
CLOCK_DEDICATED_ROUTE override or package-pin assignment is used.

Core input is 100MHz (10ns); management input is an **independent primary 25MHz
clock (40ns)**, not a generated divide-by-four clock or assumed phase relation.
The executed OOC engineering scenario explicitly used input/output max delays
2ns, min delays 0ns. Those values are design budgets, not board measurements.
Source clocks and budgets are recorded in constraint_inventory.txt.

To enable conditional RO timing, the caller must provide:

```tcl
set ::env(PUF_RO_PERIOD_NS) $externally_justified_minimum_period_ns
set ::env(PUF_RO_BOUND_SOURCE) $provenance_of_bound_or_explicit_scenario
set ::env(PUF_IO_INPUT_MAX_NS) $integration_input_budget_ns
set ::env(PUF_IO_OUTPUT_MAX_NS) $integration_output_budget_ns
set ::puf_physical_out $new_evidence_directory
source src/rtl/keys_v2/physical_constraints.tcl
```

The helper creates **256 independent primary RO clocks**, one on each verified
`bank/rings[i].stages[4].inv0/O`, using that explicit assumed minimum period.
There is no default RO period. A provisional scenario remains conditional and
must not be represented as a measured bound. Ideal clocks cannot establish
startup, duty-cycle, jitter, noise, metastability, BER, entropy or reliability.
This clock-creation branch is prepared but was not exercised with an invented
period during the present run.

Without a bound, the helper refuses unless the caller deliberately sets
`PUF_ALLOW_UNBOUNDED_STRUCTURE=1`; that is the path executed here. It explicitly
records RO_TIMING=NOT_MEASURED and creates no fictitious RO clocks. Structurally
successful routing must never be labeled fully timing-constrained signoff.

## Precisely scoped handshake/reset constraints

| Crossing | Bound | Reason / retained limitation |
|---|---|---|
| complete -> cp stage0 | 10ns datapath-only | Only first synchronization stage; later stages stay timed |
| request -> rq stage0 | 40ns datapath-only | Independent management domain; final-stage toggle detection |
| result/error -> captured core payload | 20ns datapath-only | Source-held payload arrives within the three-core-edge completion synchronization window |
| phase -> each oscillator p0 stage | 20ns datapath-only | Enumerated 512 first-stage D pins; no cut to later stages |
| each oscillator ack -> management a0 | 40ns datapath-only | Enumerated 512 first-stage D pins |
| stopped count/overflow -> snapshot | 40ns datapath-only, 20ns skew | Stop acknowledgement plus explicit settle state provides stable-data window; RO-side timing remains unmeasured without clocks |
| rst_n and registered clear -> reset-sync CLR | Exact 514 CLR pins only | Intentional asynchronous assertion; final release-stage to functional resets NOT excluded |

Vivado's `set_max_delay -datapath_only` automatically disables the unrelated
hold check on the selected crossing; no separate blanket hold/clock cut exists.
All bounds are physical design requirements to verify, not oscillator measurements.
The final completion-result path report has 1.783ns delay and +18.246ns slack
against its explicit 20ns bound in this routed scenario. It does not sign off
the other unknown-clock boundaries.

Initial extra bus-skew constraints on the result/error capture mux paths caused
TIMING-37/39 (fanout/logic-depth applicability warnings). They were removed while
retaining the identical 20ns absolute arrival bounds, which are the actual
bundled-data coherency requirement. Original constraints/reports/DCP remain;
`constraint_diff.html` shows this correction. No data path was false-pathed.
Final TIMING-37/39 counts are zero. Count/overflow bus-skew reports are NA until
RO clocks have a justified definition; NA is not PASS.

## Remaining physical warnings

- DRC LUTLP-2: 256 explicitly acknowledged five-LUT oscillators.
- PDRC-153: 256 gated/fabric oscillator clocks; requires physical clock review.
- PLHOLDVIO-2: 256 clock/data intra-site connection warnings; not waived.
- ZPS7-1: standalone Zynq OOC has no PS7; integration must supply system context.
- LUTAR-1 / CDC-10: reset merge, justification in cdc_review_20261030.md;
  pulse width and recovery/removal still require physical checks.
- TIMING-17: no measured/justified RO period; TIMING-23: intentional loops.
- TIMING-16: real core setup violations; clock-source-site/OOC hold limitations.

No blanket waiver or green-score claim. Reuse the source manifests, constraints
and DCPs for explicit-bound analysis and eventual separately authorized board work.
