# Methodology status, PUF SoC diagnostic candidate

> 2026-11-01: this is the recorded methodology review of the old independent PUF v2 candidate.
> That candidate was later invalidated (candidate/INVALID.md); positive timed-subset/offline results below
> do not authorize programming or publishing it, and do not apply to current PUF3.

Owner TBD; new project only. Constraint sources and full object details are in
`data/advanced/puf_soc/optimized/{methodology.rpt,applied_constraints.xdc,clocks.rpt,cdc_details.rpt}`.

| Check | Count | Disposition |
|---|---:|---|
| TIMING-6 | 2 | Unresolved PS core/management primary-clock relationship |
| TIMING-7 | 2 | Unresolved common-clock-node relationship; inter-clock slack is not CDC proof |
| TIMING-17 | 1000 reported examples | Unresolved;7424 actual no-clock sequential pins; requires measured RO bounds |
| TIMING-23 | 256 | Intentional ring loops acknowledged individually; physical timing remains unverified |
| LUTAR-1 | 4 | Unresolved reset/control logic review |
| ULMTCS-1 | 1 | Control-set utilization warning retained |

No methodology waiver, global clock-group cut, false-path blanket, or clock-period
change was applied. No missing RO period was invented. Vendor PS XDC creates only
10ns/40ns primary clocks; vendor reset XPM files contain two scoped first-stage
reset synchronizer false paths. This integration added only256 enumerated ring
feedback ALLOW_COMBINATORIAL_LOOPS acknowledgements. Constraint semantics did not
change between initial route and physical optimization, so there is no constraint
fix/diff to claim.

The real synchronous setup violation (−0.249ns) was resolved by post-route
AggressiveExplore logic/routing optimization, resulting in +0.009ns WNS and
+0.019ns WHS. That resolves the measured timing failure but does not resolve the
above clock/CDC/methodology limitations. No RO-domain timing/security signoff.

Referenced skill guidance: TIMING-6/7/17; no TIMING-23 reference was available.
The AMD documentation-search MCP server is unavailable. The installed Vivado2025.2
does not accept the skill's `report_methodology -json` example and has no
`write_json_report` help topic. Full native text reports and failing commands are
retained instead; optional JSON export failure did not alter the design.
